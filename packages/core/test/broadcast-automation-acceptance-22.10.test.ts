import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.10 broadcast automation acceptance", () => {
  const coordinator=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/broadcastSessionCoordinator.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const supervisor=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/broadcastSessionCoordinatorSupervisor.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const audit=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/broadcastCoordinatorAudit.ts",
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

  const app=fs.readFileSync(
    new URL(
      "../../../apps/api/src/app.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("retains coordinator health and bounded reconciliation",()=> {
    expect(coordinator).toContain("evaluateBroadcastCoordinatorHealth");
    expect(coordinator).toContain("reconcileBroadcastCoordinator");
    expect(coordinator).toContain('"REFUSE_AMBIGUOUS"');
  });

  it("retains bounded retry and supervisor behavior",()=> {
    expect(coordinator).toContain("BroadcastCoordinatorRetry");
    expect(coordinator).toContain("runBroadcastCoordinatorSupervisorTick");
    expect(coordinator).toContain('"EXHAUSTED"');
  });

  it("retains persistent automation audit history",()=> {
    expect(audit).toContain("broadcast-coordinator-audit.json");
    expect(audit).toContain('"DRIFT_DETECTED"');
    expect(audit).toContain('"RECONCILE_REFUSED"');
    expect(audit).toContain('"SUPERVISOR_TICK_FAILED"');
  });

  it("uses controlled runtime scheduling and clean shutdown",()=> {
    expect(supervisor).toContain("setInterval");
    expect(supervisor).toContain("clearInterval");
    expect(supervisor).toContain("runBroadcastCoordinatorSupervisorTick");
    expect(app).toContain("stopBroadcastCoordinatorSupervisor?.()");
  });

  it("uses authoritative active broadcast discovery",()=> {
    expect(coordinator).toContain("listActiveBroadcastGameIds");
    expect(app).toContain("gameIds: () => listActiveBroadcastGameIds()");
    expect(app).not.toContain("gameIds: () => []");
  });

  it("does not let the supervisor runtime directly start a broadcast",()=> {
    expect(supervisor).not.toContain("startEncoderRuntime");
    expect(supervisor).not.toContain("startCoordinatedBroadcast");
  });

  it("keeps operator-facing inspection endpoints",()=> {
    expect(route).toContain('"/broadcast-coordinator/active"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/health"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/audit"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/retry"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/supervisor/tick"');
  });
});
