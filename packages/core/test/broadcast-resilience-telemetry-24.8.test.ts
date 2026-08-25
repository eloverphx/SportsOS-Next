import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 24.8 resilience telemetry / operator visibility", () => {
  const route=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const focus=
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/[gameId]/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("provides resilience status API",()=> {
    expect(route).toContain(
      '"/broadcast-coordinator/:gameId/resilience-status"',
    );

    expect(route).toContain(
      "evaluateBroadcastResilienceSupervisor",
    );

    expect(route).toContain(
      "getBroadcastRecoverySnapshot",
    );
  });

  it("provides operator resilience telemetry UI",()=> {
    expect(focus).toContain(
      "Resilience Telemetry",
    );

    expect(focus).toContain(
      "resilienceStatus",
    );
  });

  it("shows heartbeat and recovery reasoning",()=> {
    expect(focus).toContain(
      "Heartbeat Reason",
    );

    expect(focus).toContain(
      "Recovery Reason",
    );

    expect(focus).toContain(
      "stale after",
    );
  });

  it("shows destructive and automatic flags",()=> {
    expect(focus).toContain(
      "Destructive",
    );

    expect(focus).toContain(
      "Automatic",
    );
  });

  it("shows persisted restart context",()=> {
    expect(focus).toContain(
      "Persisted Recovery Snapshot",
    );

    expect(focus).toContain(
      "persistedSnapshot",
    );
  });

  it("remains read-only",()=> {
    expect(route).not.toContain(
      '"/resilience-status/execute"',
    );
  });
});
