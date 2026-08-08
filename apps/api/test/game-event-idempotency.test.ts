const enqueueRealtimeEvent = vi.fn();

vi.mock("../src/infrastructure/realtime-outbox.js", () => ({
  enqueueRealtimeEvent,
}));

import { beforeEach, describe, expect, it, vi } from "vitest";

const poolExecute = vi.fn();
const connectionExecute = vi.fn();
const beginTransaction = vi.fn();
const commit = vi.fn();
const rollback = vi.fn();
const release = vi.fn();
const createPenaltyClock = vi.fn();
const clearEarliestEligibleMinorOnGoal = vi.fn();
const clearPenaltyForVoidedEvent = vi.fn();

vi.mock("../src/infrastructure/database.js", () => ({
  pool: {
    execute: poolExecute,
    getConnection: vi.fn(async () => ({
      execute: connectionExecute,
      beginTransaction,
      commit,
      rollback,
      release,
    })),
  },
}));

vi.mock("../src/modules/penalties/repository.js", () => ({
  createPenaltyClock,
  clearEarliestEligibleMinorOnGoal,
  clearPenaltyForVoidedEvent,
}));

const { createGameEvent, voidGameEvent } = await import("../src/modules/game-events/repository.js");

const input = {
  type: "GOAL",
  side: "home",
  playerId: null,
  assist1PlayerId: null,
  assist2PlayerId: null,
  notes: null,
} as const;

const eventRow = {
  id: 101,
  game_id: 77,
  organization_id: 8,
  type: "GOAL",
  side: "home",
  period: 2,
  clock_remaining_ms: 123_000,
  player_id: null,
  player_first_name: null,
  player_last_name: null,
  player_preferred_name: null,
  player_jersey_number: null,
  assist1_player_id: null,
  assist1_first_name: null,
  assist1_last_name: null,
  assist1_preferred_name: null,
  assist2_player_id: null,
  assist2_first_name: null,
  assist2_last_name: null,
  assist2_preferred_name: null,
  penalty_code: null,
  penalty_minutes: null,
  notes: null,
  voided_at: null,
  created_at: new Date(),
};

const lockedGame = {
  id: 77,
  organization_id: 8,
  home_team_id: null,
  away_team_id: null,
  home_score: 2,
  away_score: 1,
  period: 2,
  clock_remaining_ms: 123_000,
  clock_running: 0,
  clock_started_at: null,
};

beforeEach(() => {
  vi.clearAllMocks();
  beginTransaction.mockResolvedValue(undefined);
  commit.mockResolvedValue(undefined);
  rollback.mockResolvedValue(undefined);
  release.mockReturnValue(undefined);
  createPenaltyClock.mockResolvedValue(undefined);
  clearEarliestEligibleMinorOnGoal.mockResolvedValue(undefined);
  clearPenaltyForVoidedEvent.mockResolvedValue(undefined);
});

describe("game event idempotency", () => {
  it("records a new create-event actionId and its result event", async () => {
    connectionExecute.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT * FROM games") && sql.includes("FOR UPDATE")) {
        return [[lockedGame]];
      }
      if (sql.includes("FROM game_action_requests")) return [[]];
      if (sql.includes("INSERT INTO game_events")) return [{ insertId: 101 }];
      if (sql.includes("FROM game_events ge") && sql.includes("WHERE ge.id = ? LIMIT 1")) {
        return [[eventRow]];
      }
      return [{ affectedRows: 1 }];
    });

    poolExecute.mockResolvedValue([[eventRow]]);

    const result = await createGameEvent(77, input, "1", "event-action-0001");

    expect(result.replayed).toBe(false);
    expect(result.event.id).toBe(101);
    expect(
      connectionExecute.mock.calls.some(([sql]) =>
        String(sql).includes("INSERT INTO game_action_requests"),
      ),
    ).toBe(true);
    expect(
      connectionExecute.mock.calls.some(([sql]) =>
        String(sql).includes("UPDATE game_action_requests"),
      ),
    ).toBe(true);
  });

  it("returns the original event without scoring it twice", async () => {
    connectionExecute.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT * FROM games") && sql.includes("FOR UPDATE")) {
        return [[{ ...lockedGame, home_score: 3 }]];
      }
      if (sql.includes("FROM game_action_requests")) {
        return [
          [
            {
              action_payload: JSON.stringify({
                operation: "createEvent",
                input,
                resultEventId: 101,
              }),
            },
          ],
        ];
      }
      return [{ affectedRows: 1 }];
    });

    poolExecute.mockResolvedValue([[eventRow]]);

    const result = await createGameEvent(77, input, "1", "event-action-0001");

    expect(result.replayed).toBe(true);
    expect(result.homeScore).toBe(3);
    expect(
      connectionExecute.mock.calls.some(([sql]) =>
        String(sql).includes("UPDATE games SET home_score"),
      ),
    ).toBe(false);
    expect(clearEarliestEligibleMinorOnGoal).not.toHaveBeenCalled();
  });

  it("makes repeated voids safe no-ops", async () => {
    connectionExecute.mockImplementation(async (sql: string) => {
      if (sql.includes("FROM game_events") && sql.includes("FOR UPDATE")) {
        return [[{ ...eventRow, voided_at: new Date() }]];
      }
      if (sql.includes("home_score, away_score")) {
        return [[{ home_score: 2, away_score: 1 }]];
      }
      return [{ affectedRows: 1 }];
    });

    poolExecute.mockResolvedValue([[{ ...eventRow, voided_at: new Date() }]]);

    const result = await voidGameEvent(77, 101, "1");

    expect(result.replayed).toBe(true);
    expect(
      connectionExecute.mock.calls.some(([sql]) =>
        String(sql).includes("UPDATE game_events SET voided_at"),
      ),
    ).toBe(false);
    expect(clearPenaltyForVoidedEvent).not.toHaveBeenCalled();
  });
});
