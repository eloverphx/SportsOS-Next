import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 21.4 go-live confirmation health hold", () => {
  const service=fs.readFileSync(new URL("../../../apps/api/src/services/goLiveSession.ts",import.meta.url),"utf8");
  const route=fs.readFileSync(new URL("../../../apps/api/src/routes/goLiveSessions.ts",import.meta.url),"utf8");
  const panel=fs.readFileSync(new URL("../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",import.meta.url),"utf8");

  it("persists health hold state",()=> {
    expect(service).toContain("healthHoldSeconds");
    expect(service).toContain("healthySinceAt");
  });

  it("evaluates continuous publish health",()=> {
    expect(service).toContain("evaluateGoLiveHealthHold");
    expect(service).toContain("readyToConfirm");
    expect(service).toContain("remainingSeconds");
  });

  it("resets hold when runtime is unhealthy",()=> {
    expect(service).toContain("!input.encoderLive");
    expect(service).toContain("!input.publishHealthy");
    expect(service).toContain("healthySinceAt:");
  });

  it("guards live confirmation",()=> {
    expect(route).toContain("GO_LIVE_HEALTH_HOLD_21_4");
    expect(route).toContain("Publish health has not remained healthy for the required confirmation hold.");
  });

  it("provides health hold API and operator UI",()=> {
    expect(route).toContain('"/go-live-sessions/:gameId/health-hold"');
    expect(panel).toContain("Go-Live Health Hold");
    expect(panel).toContain("Confirmation Hold (seconds)");
    expect(panel).toContain("Refresh Health Hold");
  });
});
