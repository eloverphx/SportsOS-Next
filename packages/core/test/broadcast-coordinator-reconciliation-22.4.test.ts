import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.4 coordinator reconciliation / safe repair actions", () => {
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

  it("defines bounded reconciliation actions",()=> {
    for(const action of [
      "NONE",
      "RESET_INTENT",
      "STOP_RUNTIME",
      "REFUSE_AMBIGUOUS",
    ]) {
      expect(service).toContain(`"${action}"`);
    }
  });

  it("can reset stale intent",()=> {
    expect(service).toContain("Stale GO_LIVE intent was reset to IDLE.");
    expect(service).toContain('intent:\n        "IDLE"');
  });

  it("can stop unexpectedly active runtime",()=> {
    expect(service).toContain("stopEncoderRuntime");
    expect(service).toContain("Unexpected active runtime was stopped");
  });

  it("refuses ambiguous drift",()=> {
    expect(service).toContain("Coordinator drift is ambiguous and requires operator review.");
    expect(route).toContain('"REFUSE_AMBIGUOUS"');
    expect(route).toContain("reply.code(409)");
  });

  it("does not auto-start or confirm live during reconciliation",()=> {
    const start=service.indexOf("export async function reconcileBroadcastCoordinator");
    const block=service.slice(start);
    expect(block).not.toContain("startEncoderRuntime(");
    expect(block).not.toContain("armGoLiveSession(");
    expect(block).not.toContain("markGoLiveLive(");
  });

  it("provides reconciliation API",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/reconcile"');
    expect(route).toContain("reconcileBroadcastCoordinator");
  });
});
