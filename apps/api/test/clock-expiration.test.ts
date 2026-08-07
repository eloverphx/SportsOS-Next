import { beforeEach, describe, expect, it, vi } from "vitest";

const poolExecute = vi.fn();
const connectionExecute = vi.fn();
const beginTransaction = vi.fn();
const commit = vi.fn();
const rollback = vi.fn();
const release = vi.fn();
const materializePenaltyClocks = vi.fn();
const emit = vi.fn();
const findGameById = vi.fn();

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

vi.mock("../src/infrastructure/realtime.js", () => ({
  realtime: () => ({
    emit,
    to: vi.fn(() => ({ emit })),
  }),
}));

vi.mock("../src/modules/penalties/repository.js", () => ({
  materializePenaltyClocks,
}));

vi.mock("../src/modules/games/repository.js", () => ({
  findGameById,
}));

const { hasExpired, materializeGameClockExpiration, processExpiredGameClocks } = await import(
  "../src/modules/games/clock-expiration.js"
);

function expiredRow(overrides: Record<string, unknown> = {}) {
  return {
    id: 77,
    organization_id: 8,
    clock_remaining_ms: 1_000,
    clock_running: 1,
    clock_started_at: new Date(Date.now() - 2_000),
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
  findGameById.mockResolvedValue({
    id: 77,
    organizationId: 8,
    period: 2,
  });
});

describe("clock expiration detection", () => {
  it("detects a running clock after its remaining duration elapses", () => {
    expect(hasExpired(true, 1_000, new Date(Date.now() - 2_000))).toBe(true);
  });

  it("does not expire a paused clock", () => {
    expect(hasExpired(false, 1_000, new Date(Date.now() - 2_000))).toBe(false);
  });
});

describe("clock expiration materialization", () => {
  it("persists game clock expiration and materializes penalties", async () => {
    connectionExecute
      .mockResolvedValueOnce([[expiredRow()]])
      .mockResolvedValueOnce([{ affectedRows: 1 }]);

    const result = await materializeGameClockExpiration(77);

    expect(result?.gameClockExpired).toBe(true);
    expect(materializePenaltyClocks).toHaveBeenCalledWith(expect.anything(), 77);
    expect(connectionExecute).toHaveBeenCalledWith(
      expect.stringContaining("clock_remaining_ms = 0"),
      [77],
    );
    expect(commit).toHaveBeenCalledOnce();
  });

  it("persists intermission expiration without touching penalty clocks", async () => {
    connectionExecute
      .mockResolvedValueOnce([
        [
          expiredRow({
            clock_remaining_ms: 0,
            clock_running: 0,
            clock_started_at: null,
            intermission_remaining_ms: 1_000,
            intermission_running: 1,
            intermission_started_at: new Date(Date.now() - 2_000),
          }),
        ],
      ])
      .mockResolvedValueOnce([{ affectedRows: 1 }]);

    const result = await materializeGameClockExpiration(77);

    expect(result?.intermissionExpired).toBe(true);
    expect(materializePenaltyClocks).not.toHaveBeenCalled();
    expect(connectionExecute).toHaveBeenCalledWith(
      expect.stringContaining("intermission_remaining_ms = 0"),
      [77],
    );
  });

  it("returns null when another worker has already materialized the clock", async () => {
    connectionExecute.mockResolvedValueOnce([
      [
        expiredRow({
          clock_remaining_ms: 0,
          clock_running: 0,
          clock_started_at: null,
        }),
      ],
    ]);

    await expect(materializeGameClockExpiration(77)).resolves.toBeNull();
    expect(rollback).toHaveBeenCalledOnce();
    expect(emit).not.toHaveBeenCalled();
  });
});

describe("expiration realtime events", () => {
  it("emits one horn and one update after a claimed game-clock expiration", async () => {
    poolExecute.mockResolvedValueOnce([[expiredRow()]]);
    connectionExecute
      .mockResolvedValueOnce([[expiredRow()]])
      .mockResolvedValueOnce([{ affectedRows: 1 }]);

    await expect(processExpiredGameClocks()).resolves.toBe(1);

    expect(emit).toHaveBeenCalledWith(
      "game:clock-expired",
      expect.objectContaining({ gameId: 77, organizationId: 8 }),
    );
    expect(emit).toHaveBeenCalledWith(
      "scoreboard:sound",
      expect.objectContaining({ gameId: 77, type: "HORN" }),
    );
    expect(emit).toHaveBeenCalledWith("game:updated", {
      id: 77,
      organizationId: 8,
    });
  });
});
