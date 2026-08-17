import { describe, expect, it } from "vitest";
import {
  extractTournamentGame,
  extractTournamentGameList,
  normalizeTournamentGame,
  readinessCount,
} from "../lib/tournament-game-operations";

describe("Milestone 7.1 tournament game operations normalization", () => {
  it("normalizes a scheduled tournament game", () => {
    const game = normalizeTournamentGame({
      id: "game-701",
      homeTeam: { name: "Lakers" },
      awayTeam: { name: "Bears" },
      venue: { name: "Community Arena" },
      rink: { name: "Rink 1" },
      scheduledStart: "2026-08-11T18:00:00.000Z",
      status: "SCHEDULED",
    });

    expect(game).toEqual({
      id: "game-701",
      homeTeamName: "Lakers",
      awayTeamName: "Bears",
      venueName: "Community Arena",
      rinkName: "Rink 1",
      scheduledStart: "2026-08-11T18:00:00.000Z",
      status: "SCHEDULED",
      scoringStatus: "NOT_STARTED",
      readiness: {
        teamsAssigned: true,
        rinkAssigned: true,
        scheduledStartAssigned: true,
      },
    });
  });

  it("marks missing operational context as not ready", () => {
    const game = normalizeTournamentGame({
      gameId: 42,
      homeTeamName: "Lakers",
      status: "pregame",
    });

    expect(game).not.toBeNull();
    expect(game?.readiness).toEqual({
      teamsAssigned: false,
      rinkAssigned: false,
      scheduledStartAssigned: false,
    });
    expect(game ? readinessCount(game) : null).toEqual({
      passed: 0,
      total: 3,
    });
  });

  it("extracts list payloads and excludes canceled games", () => {
    const games = extractTournamentGameList({
      success: true,
      data: {
        games: [
          {
            id: "scheduled-1",
            homeTeamName: "A",
            awayTeamName: "B",
            rinkName: "1",
            scheduledStart: "2026-08-11T18:00:00Z",
            status: "SCHEDULED",
          },
          {
            id: "canceled-1",
            homeTeamName: "C",
            awayTeamName: "D",
            rinkName: "2",
            scheduledStart: "2026-08-11T19:00:00Z",
            status: "CANCELED",
          },
        ],
      },
    });

    expect(games.map((game) => game.id)).toEqual(["scheduled-1"]);
  });

  it("extracts a detail payload", () => {
    const game = extractTournamentGame({
      success: true,
      data: {
        game: {
          id: "game-detail-1",
          home_team: { displayName: "Home" },
          away_team: { displayName: "Away" },
          rink_name: "North",
          scheduled_at: "2026-08-11T20:00:00Z",
          status: "READY",
          scoring_status: "ARMED",
        },
      },
    });

    expect(game?.id).toBe("game-detail-1");
    expect(game?.homeTeamName).toBe("Home");
    expect(game?.awayTeamName).toBe("Away");
    expect(game?.status).toBe("READY");
    expect(game?.scoringStatus).toBe("ARMED");
  });
});

describe("Milestone 7.1.1 testing override", () => {
  it("recognizes local testing hosts", async () => {
    const { isLocalTestingHost } = await import("../lib/testing-override");

    expect(isLocalTestingHost("localhost")).toBe(true);
    expect(isLocalTestingHost("127.0.0.1")).toBe(true);
    expect(isLocalTestingHost("192.168.5.3")).toBe(true);
    expect(isLocalTestingHost("10.0.0.25")).toBe(true);
    expect(isLocalTestingHost("172.16.1.10")).toBe(true);
    expect(isLocalTestingHost("172.31.255.1")).toBe(true);
    expect(isLocalTestingHost("172.32.0.1")).toBe(false);
    expect(isLocalTestingHost("sports.example.com")).toBe(false);
  });

  it("persists testing override state without mutating game data", async () => {
    const {
      readTestingOverride,
      writeTestingOverride,
      SPORTSOS_TEST_OVERRIDE_STORAGE_KEY,
    } = await import("../lib/testing-override");

    const values = new Map<string, string>();
    const storage = {
      getItem(key: string) {
        return values.get(key) ?? null;
      },
      setItem(key: string, value: string) {
        values.set(key, value);
      },
      removeItem(key: string) {
        values.delete(key);
      },
    };

    expect(readTestingOverride(storage)).toBe(false);

    writeTestingOverride(storage, true);
    expect(values.get(SPORTSOS_TEST_OVERRIDE_STORAGE_KEY)).toBe("enabled");
    expect(readTestingOverride(storage)).toBe(true);

    writeTestingOverride(storage, false);
    expect(readTestingOverride(storage)).toBe(false);
  });

  it("bypasses readiness only when testing override is enabled", async () => {
    const { effectiveReadiness } = await import("../lib/testing-override");

    expect(effectiveReadiness(false, false)).toBe(false);
    expect(effectiveReadiness(true, false)).toBe(true);
    expect(effectiveReadiness(false, true)).toBe(true);
    expect(effectiveReadiness(true, true)).toBe(true);
  });
});
