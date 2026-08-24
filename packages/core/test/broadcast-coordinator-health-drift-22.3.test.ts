import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.3 coordinator health / drift detection", () => {
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

  it("defines coordinator health",()=> {
    expect(service).toContain("BroadcastCoordinatorHealth");
    expect(service).toContain("evaluateBroadcastCoordinatorHealth");
  });

  it("detects GO_LIVE intent with stopped runtime",()=> {
    expect(service).toContain('"INTENT_GO_LIVE_RUNTIME_STOPPED"');
  });

  it("detects live-session/runtime drift",()=> {
    expect(service).toContain('"GO_LIVE_LIVE_RUNTIME_NOT_LIVE"');
  });

  it("detects emergency-stop runtime drift",()=> {
    expect(service).toContain('"EMERGENCY_STOP_RUNTIME_ACTIVE"');
  });

  it("provides health endpoint",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/health"');
    expect(route).toContain("evaluateBroadcastCoordinatorHealth");
  });

  it("keeps drift detection observational",()=> {
    const start=service.indexOf("export function evaluateBroadcastCoordinatorHealth");
    const block=service.slice(start);
    expect(block).not.toContain("setBroadcastCoordinatorIntent({");
    expect(block).not.toContain("startEncoderRuntime(");
    expect(block).not.toContain("stopEncoderRuntime(");
  });
});
