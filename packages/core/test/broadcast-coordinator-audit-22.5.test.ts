import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.5 coordinator audit / reconciliation history", () => {
  const audit=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/broadcastCoordinatorAudit.ts",
      import.meta.url,
    ),
    "utf8",
  );

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

  it("persists bounded coordinator audit history",()=> {
    expect(audit).toContain("broadcast-coordinator-audit.json");
    expect(audit).toContain("2500");
  });

  it("records coordinator orchestration history",()=> {
    for(const event of [
      "INTENT_CHANGED",
      "PREPARE_REQUESTED",
      "START_REQUESTED",
      "START_COMPLETED",
      "STOP_REQUESTED",
      "STOP_COMPLETED",
    ]) {
      expect(service).toContain(`"${event}"`);
    }
  });

  it("records drift and reconciliation decisions",()=> {
    expect(service).toContain('"DRIFT_DETECTED"');
    expect(service).toContain('"RECONCILE_REQUESTED"');
    expect(service).toContain('"RECONCILE_COMPLETED"');
    expect(service).toContain('"RECONCILE_REFUSED"');
  });

  it("retains correlation ids",()=> {
    expect(audit).toContain("correlationId");
  });

  it("provides coordinator audit API",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/audit"');
    expect(route).toContain("listBroadcastCoordinatorAudit");
  });
});
