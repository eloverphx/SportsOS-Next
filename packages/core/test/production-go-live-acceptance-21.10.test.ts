import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 21.10 production go-live acceptance", () => {
  const acceptance=fs.readFileSync(
    new URL(
      "../../../docs/GO-LIVE-OPERATIONS-ACCEPTANCE.md",
      import.meta.url,
    ),
    "utf8",
  );

  const session=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/goLiveSession.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const audit=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/goLiveAudit.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const finalPreflight=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/gameDayGoLivePreflight.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const panel=fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("documents the non-authoritative go-live boundary",()=> {
    expect(acceptance).toContain("must never become authoritative");
    expect(acceptance).toContain("Authoritative game state remains");
  });

  it("retains production lifecycle and emergency state",()=> {
    for(const state of [
      "ARMED",
      "STARTING",
      "LIVE",
      "DEGRADED",
      "COMPLETE",
      "EMERGENCY_STOPPED",
    ]) {
      expect(session).toContain(`"${state}"`);
    }
  });

  it("retains health-hold and degraded incident state",()=> {
    expect(session).toContain("healthHoldSeconds");
    expect(session).toContain("degradationReason");
    expect(session).toContain("incidentAcknowledgedAt");
  });

  it("retains final game-day preflight",()=> {
    expect(finalPreflight).toContain("evaluateGameDayGoLivePreflight");
    expect(finalPreflight).toContain("EMERGENCY_STOP");
    expect(finalPreflight).toContain("DEGRADED_INCIDENT");
  });

  it("retains production audit history",()=> {
    expect(audit).toContain("go-live-audit.json");
    expect(audit).toContain("EMERGENCY_STOP");
    expect(audit).toContain("INCIDENT_ACKNOWLEDGED");
  });

  it("retains operator production controls",()=> {
    expect(panel).toContain("Production Go-Live");
    expect(panel).toContain("Game-Day Go-Live Preflight");
    expect(panel).toContain("Live Broadcast Watchdog");
    expect(panel).toContain("Emergency Broadcast Stop");
    expect(panel).toContain("Go-Live Session History");
  });

  it("documents final validation gates",()=> {
    expect(acceptance).toContain("npm run typecheck && npm test");
    expect(acceptance).toContain("npm run test:e2e:docker");
  });
});
