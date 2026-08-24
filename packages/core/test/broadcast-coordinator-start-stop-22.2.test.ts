import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.2 coordinator start / stop orchestration", () => {
  const service=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/broadcastSessionCoordinator.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route=fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("reuses final game-day preflight",()=> {
    expect(service).toContain("evaluateGameDayGoLivePreflight");
    expect(service).toContain("Final game-day go-live preflight is blocked.");
  });

  it("reuses existing go-live and encoder services",()=> {
    expect(service).toContain("armGoLiveSession");
    expect(service).toContain("markGoLiveStarting");
    expect(service).toContain("startEncoderRuntime");
    expect(service).toContain("stopEncoderRuntime");
    expect(service).toContain("completeGoLiveSession");
  });

  it("provides start and stop orchestration APIs",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/start"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/stop"');
  });

  it("tracks GO_LIVE and STOP coordinator intents",()=> {
    expect(service).toContain('intent:\n      "GO_LIVE"');
    expect(service).toContain('intent:\n      "STOP"');
  });

  it("does not define another encoder lifecycle",()=> {
    expect(service).not.toContain("BroadcastEncoderStatus");
    expect(service).not.toContain("CoordinatorEncoderState");
  });
});
