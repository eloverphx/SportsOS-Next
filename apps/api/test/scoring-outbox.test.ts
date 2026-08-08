import { beforeEach, describe, expect, it, vi } from "vitest";

const enqueueRealtimeEvent = vi.fn();
const materializePenaltyClocks = vi.fn();
const adjustActivePenaltyClocks = vi.fn();
const setPenaltyClockRunning = vi.fn();
const connectionExecute = vi.fn();
const beginTransaction = vi.fn();
const commit = vi.fn();
const rollback = vi.fn();
const release = vi.fn();
const poolExecute = vi.fn();

vi.mock("../src/infrastructure/realtime-outbox.js", () => ({
  enqueueRealtimeEvent,
}));

vi.mock("../src/modules/penalties/repository.js", () => ({
  materializePenaltyClocks,
  adjustActivePenaltyClocks,
  setPenaltyClockRunning,
}));

vi.mock("../src/infrastructure/database.js", () => ({
  pool: {
    getConnection: vi.fn(async () => ({
      execute: connectionExecute,
      beginTransaction,
      commit,
      rollback,
      release,
    })),
    execute: poolExecute,
  },
}));

const { applyGameScoringAction } = await import("../src/modules/games/repository.js");

describe("scoring realtime outbox", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    materializePenaltyClocks.mockResolvedValue(undefined);
    adjustActivePenaltyClocks.mockResolvedValue(undefined);
    setPenaltyClockRunning.mockResolvedValue(undefined);

    connectionExecute
      .mockResolvedValueOnce([
        [
          {
            id: 42,
            organization_id: 8,
            home_score: 1,
            away_score: 2,
            status: "LIVE",
            game_phase: "REGULATION",
            period: 2,
            period_length_ms: 1_200_000,
            clock_remaining_ms: 600_000,
            clock_running: 0,
            clock_started_at: null,
            regulation_periods: 3,
            regulation_period_length_ms: 1_200_000,
            intermission_length_ms: 900_000,
            overtime_enabled: 1,
            overtime_length_ms: 300_000,
            intermission_remaining_ms: 0,
            intermission_running: 0,
            intermission_started_at: null,
          },
        ],
      ])
      .mockResolvedValue([{ affectedRows: 1 }]);

    poolExecute.mockResolvedValueOnce([
      [
        {
          id: 42,
          organization_id: 8,
          organization_name: "Example",
          season_id: 1,
          season_name: "Season",
          home_team_id: 10,
          home_external_name: null,
          home_team_name: "Home",
          home_team_short_name: "HOME",
          home_team_primary_color: "#000000",
          home_team_secondary_color: "#ffffff",
          home_team_logo_asset_id: null,
          away_team_id: 11,
          away_external_name: null,
          away_team_name: "Away",
          away_team_short_name: "AWAY",
          away_team_primary_color: "#000000",
          away_team_secondary_color: "#ffffff",
          away_team_logo_asset_id: null,
          scheduled_start: new Date(),
          timezone: "America/Chicago",
          venue: null,
          status: "LIVE",
          game_phase: "REGULATION",
          home_score: 2,
          away_score: 2,
          period: 2,
          period_length_ms: 1_200_000,
          clock_remaining_ms: 600_000,
          clock_running: 0,
          clock_started_at: null,
          regulation_periods: 3,
          regulation_period_length_ms: 1_200_000,
          intermission_length_ms: 900_000,
          overtime_enabled: 1,
          overtime_length_ms: 300_000,
          intermission_remaining_ms: 0,
          intermission_running: 0,
          intermission_started_at: null,
          notes: null,
          created_at: new Date(),
          updated_at: new Date(),
        },
      ],
    ]);
  });

  it("queues scoring, update, and workspace invalidation before commit", async () => {
    await applyGameScoringAction(42, { action: "adjustScore", side: "home", amount: 1 });

    expect(enqueueRealtimeEvent).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        room: "game:42",
        event: "game:scored",
        payload: expect.objectContaining({
          gameId: 42,
          organizationId: 8,
          homeScore: 2,
          awayScore: 2,
        }),
      }),
    );

    expect(enqueueRealtimeEvent).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        room: "game:42",
        event: "game:updated",
      }),
    );

    expect(enqueueRealtimeEvent).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        event: "games:changed",
        payload: expect.objectContaining({ reason: "scored", id: 42 }),
      }),
    );

    expect(commit).toHaveBeenCalledTimes(1);
  });
});
