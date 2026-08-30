import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 21.8 go-live audit timeline / session history", () => {
  const audit=fs.readFileSync(new URL("../../../apps/api/src/services/goLiveAudit.ts",import.meta.url),"utf8");
  const route=fs.readFileSync(new URL("../../../apps/api/src/routes/goLiveSessions.ts",import.meta.url),"utf8");
  const panel=fs.readFileSync(new URL("../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",import.meta.url),"utf8");

  it("persists bounded go-live audit history",()=> {
    expect(audit).toContain("go-live-audit.json");
    expect(audit).toContain("2000");
  });

  it("records core production lifecycle events",()=> {
    for(const event of [
      "ARMED",
      "START_REQUESTED",
      "STARTING",
      "LIVE_CONFIRMED",
      "DEGRADED",
      "RECOVERED",
      "EMERGENCY_STOP",
    ]) {
      expect(route).toContain(`"${event}"`);
    }
  });

  it("records incident acknowledgement and retry",()=> {
    expect(route).toContain('"INCIDENT_ACKNOWLEDGED"');
    expect(route).toContain('"INCIDENT_RETRY"');
  });

  it("provides audit API",()=> {
    expect(route).toContain('"/go-live-sessions/:gameId/audit"');
    expect(route).toContain("listGoLiveAuditEvents");
  });

  it("provides operator session history",()=> {
    expect(panel).toContain("Go-Live Session History");
    expect(panel).toContain("Refresh Go-Live History");
    expect(panel).toContain("/audit?limit=25");
  });
});
