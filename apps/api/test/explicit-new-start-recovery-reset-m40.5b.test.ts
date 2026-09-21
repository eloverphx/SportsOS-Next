import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const encoder = readFileSync(path.resolve(__dirname, "../src/services/encoderRuntime.ts"), "utf8");

const coordinator = readFileSync(
  path.resolve(__dirname, "../src/services/broadcastSessionCoordinator.ts"),
  "utf8",
);

describe("M40.5 explicit new-start recovery reset", () => {
  it("exports the encoder recovery reset for explicit coordinator use", () => {
    expect(encoder).toContain("export function resetEncoderRecovery(gameId: string): void");
  });

  it("only resets exhausted recovery for an inactive prior broadcast", () => {
    expect(coordinator).toContain("resetExhaustedEncoderRecoveryForExplicitNewStart");
    expect(coordinator).toContain('coordinator.intent === "IDLE"');
    expect(coordinator).toContain('["IDLE", "COMPLETE", "ERROR"].includes(goLive.status)');
    expect(coordinator).toContain("!runtime.runtimeActive");
    expect(coordinator).toContain('runtime.recovery.state === "EXHAUSTED"');
    expect(coordinator).toContain("resetEncoderRecovery(gameId)");
  });

  it("resets before prepare preflight is evaluated", () => {
    const start = coordinator.indexOf("export function prepareBroadcastSession");
    const end = coordinator.indexOf("export async function startCoordinatedBroadcast", start);
    const prepare = coordinator.slice(start, end);

    expect(
      prepare.indexOf("resetExhaustedEncoderRecoveryForExplicitNewStart(gameId)"),
    ).toBeGreaterThan(-1);

    expect(prepare.indexOf("evaluateGameDayGoLivePreflight(gameId)")).toBeGreaterThan(
      prepare.indexOf("resetExhaustedEncoderRecoveryForExplicitNewStart(gameId)"),
    );
  });

  it("also protects direct explicit start calls", () => {
    const start = coordinator.indexOf("export async function startCoordinatedBroadcast");
    const end = coordinator.indexOf("export async function stopCoordinatedBroadcast", start);
    const startFunction = coordinator.slice(start, end);

    expect(startFunction).toContain("resetExhaustedEncoderRecoveryForExplicitNewStart(gameId)");
  });

  it("does not make supervisor ticks reset exhausted recovery", () => {
    const start = coordinator.indexOf(
      "export async function runBroadcastCoordinatorSupervisorTick",
    );
    const supervisor = coordinator.slice(start);

    expect(supervisor).not.toContain("resetEncoderRecovery(gameId)");
    expect(supervisor).not.toContain("resetExhaustedEncoderRecoveryForExplicitNewStart");
  });
});
