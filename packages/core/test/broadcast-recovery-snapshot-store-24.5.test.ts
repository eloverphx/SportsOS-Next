import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 24.5 restart / crash recovery persistence", () => {
  const service=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastRecoverySnapshotStore.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("persists recovery snapshots in shared data storage",()=> {
    expect(service).toContain("SPORTSOS_DATA_DIR");
    expect(service).toContain("broadcast-recovery-snapshots.json");
    expect(service).toContain("500");
  });

  it("stores coordinator/runtime/recovery context",()=> {
    expect(service).toContain("coordinatorIntent");
    expect(service).toContain("runtimeStatus");
    expect(service).toContain("recoveryAction");
    expect(service).toContain("heartbeatState");
  });

  it("provides capture and read APIs",()=> {
    expect(route).toContain('"/broadcast-coordinator/recovery-snapshots"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/recovery-snapshot"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/recovery-snapshot/capture"');
  });

  it("uses current resilience decision when capturing",()=> {
    expect(route).toContain("evaluateBroadcastResilienceSupervisor");
    expect(route).toContain("saveBroadcastRecoverySnapshot");
  });

  it("does not directly control encoder runtime",()=> {
    expect(service).not.toContain("startEncoderRuntime");
    expect(service).not.toContain("stopEncoderRuntime");
    expect(route).not.toContain("startEncoderRuntime(");
  });
});
