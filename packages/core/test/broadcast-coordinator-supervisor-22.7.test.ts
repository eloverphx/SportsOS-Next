import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.7 coordinator supervisor", () => {
  const service=fs.readFileSync(new URL("../../../apps/api/src/services/broadcastSessionCoordinator.ts",import.meta.url),"utf8");
  const audit=fs.readFileSync(new URL("../../../apps/api/src/services/broadcastCoordinatorAudit.ts",import.meta.url),"utf8");
  const route=fs.readFileSync(new URL("../../../apps/api/src/routes/broadcastSessionCoordinator.ts",import.meta.url),"utf8");

  it("supports bounded actions",()=> {
    ["NONE","RETRY_EXECUTED","RECONCILED","REFUSED"].forEach(x=>expect(service).toContain(`"${x}"`));
  });
  it("executes only due scheduled retries",()=> {
    expect(service).toContain('retry.state === "SCHEDULED"');
    expect(service).toContain("Date.parse(retry.nextRetryAt)");
    expect(service).toContain("executeBroadcastCoordinatorRetry");
  });
  it("reuses safe reconciliation",()=>expect(service).toContain("reconcileBroadcastCoordinator"));
  it("audits supervisor decisions",()=> {
    ["SUPERVISOR_TICK","SUPERVISOR_RETRY_EXECUTED","SUPERVISOR_RECONCILED","SUPERVISOR_ACTION_REFUSED"].forEach(x=>expect(audit).toContain(`"${x}"`));
  });
  it("does not auto-start encoder",()=> {
    const block=service.slice(service.indexOf("export async function runBroadcastCoordinatorSupervisorTick"));
    expect(block).not.toContain("startEncoderRuntime(");
    expect(block).not.toContain("startCoordinatedBroadcast(");
  });
  it("provides tick endpoint",()=>expect(route).toContain('"/broadcast-coordinator/:gameId/supervisor/tick"'));
});
