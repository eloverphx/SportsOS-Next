import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  evaluateBroadcastResilienceSupervisor,
} from "../../../apps/api/src/services/broadcastResilienceSupervisor";

describe("Milestone 24.3 coordinator/runtime reconciliation supervisor", () => {
  it("keeps healthy live state consistent",()=> {
    const now=100_000;

    const result=
      evaluateBroadcastResilienceSupervisor({
        coordinatorIntent:
          "GO_LIVE",
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          new Date(
            now -
            5_000,
          ).toISOString(),
        stateAgeMs:
          5_000,
        nowMs:
          now,
      });

    expect(
      result.heartbeat.state,
    ).toBe(
      "HEALTHY",
    );

    expect(
      result.recovery.action,
    ).toBe(
      "observe",
    );
  });

  it("escalates stale runtime to operator review",()=> {
    const now=100_000;

    const result=
      evaluateBroadcastResilienceSupervisor({
        coordinatorIntent:
          "GO_LIVE",
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          new Date(
            now -
            30_000,
          ).toISOString(),
        stateAgeMs:
          30_000,
        nowMs:
          now,
      });

    expect(
      result.heartbeat.state,
    ).toBe(
      "STALE",
    );

    expect(
      result.recovery.action,
    ).toBe(
      "require-operator-review",
    );
  });

  it("does not auto-stop unexpected live runtime",()=> {
    const now=100_000;

    const result=
      evaluateBroadcastResilienceSupervisor({
        coordinatorIntent:
          "STOPPED",
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          new Date(
            now -
            60_000,
          ).toISOString(),
        stateAgeMs:
          60_000,
        nowMs:
          now,
      });

    expect(
      result.recovery.action,
    ).toBe(
      "require-operator-review",
    );
  });

  it("escalates failed runtime",()=> {
    const result=
      evaluateBroadcastResilienceSupervisor({
        coordinatorIntent:
          "GO_LIVE",
        runtimeStatus:
          "ERROR",
        lastActivityAt:
          null,
        stateAgeMs:
          60_000,
      });

    expect(
      result.recovery.action,
    ).toBe(
      "require-operator-review",
    );
  });

  it("provides read-only supervisor API",()=> {
    const route=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/:gameId/resilience-supervisor"',
    );

    expect(route).toContain(
      "evaluateBroadcastResilienceSupervisor",
    );
  });
});
