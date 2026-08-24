import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 21.3 scheduled auto-arm / operator countdown", () => {
  const service=fs.readFileSync(new URL("../../../apps/api/src/services/goLiveSession.ts",import.meta.url),"utf8");
  const route=fs.readFileSync(new URL("../../../apps/api/src/routes/goLiveSessions.ts",import.meta.url),"utf8");
  const panel=fs.readFileSync(new URL("../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",import.meta.url),"utf8");

  it("persists auto-arm configuration",()=>{ expect(service).toContain("autoArmEnabled"); expect(service).toContain("autoArmLeadMinutes"); });
  it("calculates countdown",()=>{ expect(service).toContain("evaluateGoLiveCountdown"); expect(service).toContain("secondsUntilStart"); expect(service).toContain("autoArmDue"); });
  it("provides APIs",()=>{ expect(route).toContain('"/go-live-sessions/:gameId/auto-arm"'); expect(route).toContain('"/go-live-sessions/:gameId/countdown"'); expect(route).toContain('"/go-live-sessions/:gameId/auto-arm/evaluate"'); });
  it("gates auto-arm on readiness",()=>expect(route).toContain("Auto-arm is due but streaming readiness preflight failed."));
  it("provides operator controls",()=>{ expect(panel).toContain("Auto-Arm Countdown"); expect(panel).toContain("Enable scheduled auto-arm"); expect(panel).toContain("Save Auto-Arm"); });
});
