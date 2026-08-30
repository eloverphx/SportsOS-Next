import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 21.9 game-day go-live readiness / final operator preflight", () => {
  const service=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/gameDayGoLivePreflight.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route=fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/goLiveSessions.ts",
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

  it("provides final production readiness service",()=> {
    expect(service).toContain("evaluateGameDayGoLivePreflight");
    expect(service).toContain('"STREAMING_PREFLIGHT"');
    expect(service).toContain('"EMERGENCY_STOP"');
    expect(service).toContain('"DEGRADED_INCIDENT"');
  });

  it("provides final preflight API",()=> {
    expect(route).toContain('"/go-live-sessions/:gameId/game-day-preflight"');
    expect(route).toContain("evaluateGameDayGoLivePreflight");
  });

  it("blocks arm when final preflight fails",()=> {
    expect(route).toContain("GAME_DAY_GO_LIVE_PREFLIGHT_21_9");
    expect(route).toContain("Game-day go-live preflight failed.");
  });

  it("provides operator final preflight UI",()=> {
    expect(panel).toContain("Game-Day Go-Live Preflight");
    expect(panel).toContain("Run Final Go-Live Preflight");
  });
});
