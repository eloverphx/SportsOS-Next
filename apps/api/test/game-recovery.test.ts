import { beforeEach, describe, expect, it, vi } from "vitest";

const poolExecute = vi.fn();
const connectionExecute = vi.fn();
const beginTransaction = vi.fn();
const commit = vi.fn();
const rollback = vi.fn();
const release = vi.fn();
const materializePenaltyClocks = vi.fn();
const enqueueRealtimeEvent = vi.fn();

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

vi.mock("../src/infrastructure/realtime-outbox.js", () => ({
  enqueueRealtimeEvent,
}));

vi.mock("../src/modules/penalties/repository.js", () => ({
  materializePenaltyClocks,
}));

const { recoverGameClocksOnStartup } = await import(
  "../src/modules/games/clock-expiration.js"
);

function candidate(id: number, overrides: Record<string, unknown> = {}) {
  return {
    id,
    organization_id: 8,
    clock_remaining_ms: 1_000,
    clock_running: 1,
    clock_started_at: new Date(0),
    intermission_remaining_ms: 0,
    intermission_running: 0,
    intermission_started_at: null,
    ...overrides,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  beginTransaction.mockResolvedValue(undefined);
  commit.mockResolvedValue(undefined);
  rollback.mockResolvedValue(undefined);
  release.mockReturnValue(undefined);
  materializePenaltyClocks.mockResolvedValue(undefined);
  enqueueRealtimeEvent.mockResolvedValue(undefined);
});

describe("startup game-clock recovery", () => {
  it("recovers multiple expired games independently", async () => {
    const rows = [candidate(11), candidate(12)];

    poolExecute.mockResolvedValueOnce([rows]);

    let lock = 0;
    connectionExecute.mockImplementation(async (sql: string) => {
      if (sql.includes("FROM games") && sql.includes("FOR UPDATE")) {
        return [[rows[lock++]]];
      }
      return [{ affectedRows: 1 }];
    });

    await expect(recoverGameClocksOnStartup(5_000)).resolves.toBe(2);

    expect(materializePenaltyClocks).toHaveBeenCalledTimes(2);
    expect(commit).toHaveBeenCalledTimes(2);
    expect(enqueueRealtimeEvent).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        room: "game:11",
        event: "game:clock-expired",
      }),
    );
    expect(enqueueRealtimeEvent).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        room: "game:12",
        event: "game:clock-expired",
      }),
    );
  });

  it("recovers expired intermission without touching penalties", async () => {
    const row = candidate(21, {
      clock_remaining_ms: 0,
      clock_running: 0,
      clock_started_at: null,
      intermission_remaining_ms: 1_000,
      intermission_running: 1,
      intermission_started_at: new Date(0),
    });

    poolExecute.mockResolvedValueOnce([[row]]);
    connectionExecute.mockImplementation(async (sql: string) => {
      if (sql.includes("FROM games") && sql.includes("FOR UPDATE")) {
        return [[row]];
      }
      return [{ affectedRows: 1 }];
    });

    await expect(recoverGameClocksOnStartup(5_000)).resolves.toBe(1);
    expect(materializePenaltyClocks).not.toHaveBeenCalled();
    expect(enqueueRealtimeEvent).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        room: "game:21",
        event: "game:intermission-expired",
      }),
    );
  });

  it("leaves still-running clocks timestamp-based", async () => {
    const row = candidate(31, {
      clock_remaining_ms: 60_000,
      clock_started_at: new Date(4_000),
    });

    poolExecute.mockResolvedValueOnce([[row]]);

    await expect(recoverGameClocksOnStartup(5_000)).resolves.toBe(0);
    expect(connectionExecute).not.toHaveBeenCalled();
    expect(commit).not.toHaveBeenCalled();
  });
});
