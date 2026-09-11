import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const coordinatorFile = path.resolve(__dirname, "../src/services/broadcastSessionCoordinator.ts");
const source = readFileSync(coordinatorFile, "utf8");

function branchBetween(issue: string, nextIssue: string): string {
  const start = source.indexOf(`if (ids.has("${issue}"))`);
  const end = source.indexOf(`if (ids.has("${nextIssue}")`, start + 1);

  expect(start).toBeGreaterThan(-1);
  expect(end).toBeGreaterThan(start);

  return source.slice(start, end);
}

describe("M37.14 supervisor stop parity", () => {
  it("reconciles normal STOP drift through the coordinated stop path", () => {
    const branch = branchBetween("INTENT_STOP_RUNTIME_ACTIVE", "EMERGENCY_STOP_RUNTIME_ACTIVE");

    expect(branch).toContain("await stopCoordinatedBroadcast(gameId)");
    expect(branch).not.toContain("await stopEncoderRuntime(gameId)");
  });

  it("reuses durable STOPPING/COMPLETE sync and recording finalization", () => {
    const start = source.indexOf("export async function stopCoordinatedBroadcast");
    const end = source.indexOf("export type BroadcastCoordinatorHealth", start);
    const stopSource = source.slice(start, end);

    expect(stopSource).toContain("markGoLiveStopping(gameId)");
    expect(stopSource).toContain("syncDurableGoLiveSession");
    expect(stopSource).toContain("completeGoLiveSession(gameId)");
    expect(stopSource).toContain("stopAndFinalizeRecordingCapture(gameId)");
  });

  it("keeps emergency-stop reconciliation non-finalizing", () => {
    const branch = branchBetween("EMERGENCY_STOP_RUNTIME_ACTIVE", "INTENT_GO_LIVE_RUNTIME_STOPPED");

    expect(branch).toContain("await stopEncoderRuntime(gameId)");
    expect(branch).not.toContain("stopCoordinatedBroadcast(gameId)");
    expect(branch).not.toContain("stopAndFinalizeRecordingCapture(gameId)");
  });

  it("preserves the STOP_RUNTIME reconciliation action", () => {
    const normalBranch = branchBetween(
      "INTENT_STOP_RUNTIME_ACTIVE",
      "EMERGENCY_STOP_RUNTIME_ACTIVE",
    );
    const emergencyBranch = branchBetween(
      "EMERGENCY_STOP_RUNTIME_ACTIVE",
      "INTENT_GO_LIVE_RUNTIME_STOPPED",
    );

    expect(normalBranch).toContain('action: "STOP_RUNTIME"');
    expect(emergencyBranch).toContain('action: "STOP_RUNTIME"');
  });
});
