import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 21.6 live incident acknowledgement / operator recovery controls", () => {
  const service=fs.readFileSync(new URL("../../../apps/api/src/services/goLiveSession.ts",import.meta.url),"utf8");
  const route=fs.readFileSync(new URL("../../../apps/api/src/routes/goLiveSessions.ts",import.meta.url),"utf8");
  const panel=fs.readFileSync(new URL("../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",import.meta.url),"utf8");

  it("persists incident acknowledgement",()=> {
    expect(service).toContain("incidentAcknowledgedAt");
    expect(service).toContain("incidentAcknowledgedBy");
    expect(service).toContain("acknowledgeGoLiveIncident");
  });

  it("allows acknowledgement only for degraded sessions",()=> {
    expect(route).toContain("Only a DEGRADED go-live session can be acknowledged.");
  });

  it("provides acknowledgement and retry endpoints",()=> {
    expect(route).toContain('"/go-live-sessions/:gameId/incident/acknowledge"');
    expect(route).toContain('"/go-live-sessions/:gameId/incident/retry-watchdog"');
  });

  it("does not treat acknowledgement as recovery",()=> {
    const start=route.indexOf('"/go-live-sessions/:gameId/incident/acknowledge"');
    const end=route.indexOf('"/go-live-sessions/:gameId/incident/retry-watchdog"',start);
    const block=route.slice(start,end);
    expect(block).not.toContain("clearGoLiveDegraded");
  });

  it("provides operator incident controls",()=> {
    expect(panel).toContain("Live Incident Controls");
    expect(panel).toContain("Acknowledge Incident");
    expect(panel).toContain("Retry Health Check");
    expect(panel).toContain("incidentAcknowledgedAt");
  });
});
