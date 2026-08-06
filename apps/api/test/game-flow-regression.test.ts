import { beforeEach, describe, expect, it, vi } from "vitest";

const connectionExecute = vi.fn();
const beginTransaction = vi.fn();
const commit = vi.fn();
const rollback = vi.fn();
const release = vi.fn();
const poolExecute = vi.fn();

const materializePenaltyClocks = vi.fn();
const adjustActivePenaltyClocks = vi.fn();
const setPenaltyClockRunning = vi.fn();

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
  materializePenaltyClocks,
  adjustActivePenaltyClocks,
  setPenaltyClockRunning,
}));

const { applyGameScoringAction, createGame } = await import("../src/modules/games/repository.js");

const { scoreActionSchema } = await import("../src/modules/games/schemas.js");

type LockedRow = {
  id: number;
  home_score: number;
  away_score: number;
  status: "SCHEDULED" | "LIVE" | "FINAL";
  game_phase: "PREGAME" | "REGULATION" | "INTERMISSION" | "OVERTIME" | "FINAL";
  period: number;
  period_length_ms: number;
  clock_remaining_ms: number;
  clock_running: number;
  clock_started_at: Date | null;
  regulation_periods: number;
  regulation_period_length_ms: number;
  intermission_length_ms: number;
  overtime_enabled: number;
  overtime_length_ms: number;
  intermission_remaining_ms: number;
  intermission_running: number;
  intermission_started_at: Date | null;
};

function lockedRow(overrides: Partial<LockedRow> = {}): LockedRow {
  return {
    id: 77,
    home_score: 2,
    away_score: 1,
    status: "LIVE",
    game_phase: "REGULATION",
    period: 1,
    period_length_ms: 900_000,
    clock_remaining_ms: 0,
    clock_running: 0,
    clock_started_at: null,
    regulation_periods: 3,
    regulation_period_length_ms: 900_000,
    intermission_length_ms: 600_000,
    overtime_enabled: 1,
    overtime_length_ms: 300_000,
    intermission_remaining_ms: 0,
    intermission_running: 0,
    intermission_started_at: null,
    ...overrides,
  };
}

function prepareScoring(row: LockedRow): void {
  connectionExecute.mockImplementation(async (sql: string) => {
    if (sql.includes("FROM games") && sql.includes("FOR UPDATE")) {
      return [[row]];
    }

    return [{ affectedRows: 1 }];
  });

  poolExecute.mockResolvedValue([[]]);
}

function gameUpdateCall(): [string, unknown[]] {
  const call = connectionExecute.mock.calls.find(([sql]) =>
    String(sql).includes("UPDATE games SET"),
  );

  if (!call) throw new Error("Game update query was not executed");
  return [String(call[0]), call[1] as unknown[]];
}

function valueForColumn(sql: string, values: unknown[], column: string): unknown {
  const setClause = sql.split("SET")[1]?.split("WHERE")[0] ?? "";
  const columns = [...setClause.matchAll(/([a-z_]+)\s*=\s*\?/g)].map((match) => match[1]);
  const index = columns.indexOf(column);

  if (index < 0) throw new Error(`Column ${column} was not updated`);
  return values[index];
}

beforeEach(() => {
  vi.clearAllMocks();

  beginTransaction.mockResolvedValue(undefined);
  commit.mockResolvedValue(undefined);
  rollback.mockResolvedValue(undefined);
  release.mockReturnValue(undefined);

  materializePenaltyClocks.mockResolvedValue(undefined);
  adjustActivePenaltyClocks.mockResolvedValue(undefined);
  setPenaltyClockRunning.mockResolvedValue(undefined);
});

describe("game-flow scoring schema", () => {
  it("accepts setting a custom intermission length", () => {
    expect(
      scoreActionSchema.parse({
        action: "setIntermission",
        intermissionLengthMs: 150_000,
      }),
    ).toEqual({
      action: "setIntermission",
      intermissionLengthMs: 150_000,
    });
  });

  it("rejects an intermission longer than one hour", () => {
    expect(
      scoreActionSchema.safeParse({
        action: "setIntermission",
        intermissionLengthMs: 3_600_001,
      }).success,
    ).toBe(false);
  });
});

describe("game creation clock initialization", () => {
  it("initializes the active period and clock from the configured period length", async () => {
    poolExecute.mockResolvedValueOnce([{ insertId: 44 }]).mockResolvedValueOnce([[]]);

    await expect(
      createGame({
        organizationId: 1,
        seasonId: 2,
        homeTeamId: null,
        homeExternalName: "Home",
        awayTeamId: null,
        awayExternalName: "Away",
        scheduledStart: "2026-08-04T20:00:00.000Z",
        timezone: "America/Chicago",
        venue: null,
        status: "SCHEDULED",
        homeScore: 0,
        awayScore: 0,
        regulationPeriods: 3,
        regulationPeriodLengthMs: 720_000,
        intermissionLengthMs: 300_000,
        overtimeEnabled: true,
        overtimeLengthMs: 240_000,
        notes: null,
      }),
    ).rejects.toThrow("Game could not be read after creation");

    const [sql, params] = poolExecute.mock.calls[0] as [string, unknown[]];

    expect(sql).toContain("period_length_ms");
    expect(sql).toContain("clock_remaining_ms");

    const columns = sql
      .slice(sql.indexOf("(") + 1, sql.indexOf(")"))
      .split(",")
      .map((value) => value.trim());

    expect(params[columns.indexOf("period_length_ms")]).toBe(720_000);
    expect(params[columns.indexOf("clock_remaining_ms")]).toBe(720_000);
  });
});

describe("intermission and penalty clock flow", () => {
  it("persists a custom intermission length and current countdown", async () => {
    prepareScoring(lockedRow());

    await applyGameScoringAction(77, {
      action: "setIntermission",
      intermissionLengthMs: 150_000,
    });

    const [sql, values] = gameUpdateCall();

    expect(valueForColumn(sql, values, "intermission_length_ms")).toBe(150_000);
    expect(valueForColumn(sql, values, "intermission_remaining_ms")).toBe(150_000);
    expect(valueForColumn(sql, values, "intermission_running")).toBe(false);
  });

  it("starts intermission with the configured length and pauses penalties", async () => {
    prepareScoring(
      lockedRow({
        intermission_length_ms: 420_000,
        intermission_remaining_ms: 0,
      }),
    );

    await applyGameScoringAction(77, {
      action: "startIntermission",
    });

    const [sql, values] = gameUpdateCall();

    expect(valueForColumn(sql, values, "clock_running")).toBe(false);
    expect(valueForColumn(sql, values, "intermission_remaining_ms")).toBe(420_000);
    expect(valueForColumn(sql, values, "intermission_running")).toBe(true);

    expect(setPenaltyClockRunning).toHaveBeenCalledWith(expect.anything(), 77, false);
  });

  it("keeps penalties paused after advancing to the next period", async () => {
    prepareScoring(
      lockedRow({
        period: 1,
        period_length_ms: 720_000,
        intermission_remaining_ms: 0,
      }),
    );

    await applyGameScoringAction(77, {
      action: "nextPeriod",
    });

    const [sql, values] = gameUpdateCall();

    expect(valueForColumn(sql, values, "period")).toBe(2);
    expect(valueForColumn(sql, values, "period_length_ms")).toBe(720_000);
    expect(valueForColumn(sql, values, "clock_remaining_ms")).toBe(720_000);
    expect(valueForColumn(sql, values, "clock_running")).toBe(false);

    expect(setPenaltyClockRunning).toHaveBeenCalledWith(expect.anything(), 77, false);
  });

  it("resumes penalties only when the game clock starts", async () => {
    prepareScoring(
      lockedRow({
        clock_remaining_ms: 720_000,
        intermission_remaining_ms: 0,
        intermission_running: 0,
      }),
    );

    await applyGameScoringAction(77, {
      action: "startClock",
    });

    expect(setPenaltyClockRunning).toHaveBeenCalledWith(expect.anything(), 77, true);
  });

  it("does not allow the game clock to start during intermission", async () => {
    prepareScoring(
      lockedRow({
        game_phase: "INTERMISSION",
        clock_remaining_ms: 720_000,
        intermission_remaining_ms: 300_000,
        intermission_running: 1,
        intermission_started_at: new Date(),
      }),
    );

    await expect(
      applyGameScoringAction(77, {
        action: "startClock",
      }),
    ).rejects.toThrow("Finish or skip intermission before starting the game clock");

    expect(rollback).toHaveBeenCalled();
    expect(setPenaltyClockRunning).not.toHaveBeenCalled();
  });

  it("uses the configured overtime length and leaves penalties paused", async () => {
    prepareScoring(
      lockedRow({
        period: 3,
        regulation_periods: 3,
        overtime_length_ms: 240_000,
      }),
    );

    await applyGameScoringAction(77, {
      action: "startOvertime",
    });

    const [sql, values] = gameUpdateCall();

    expect(valueForColumn(sql, values, "period")).toBe(4);
    expect(valueForColumn(sql, values, "period_length_ms")).toBe(240_000);
    expect(valueForColumn(sql, values, "clock_remaining_ms")).toBe(240_000);
    expect(valueForColumn(sql, values, "clock_running")).toBe(false);

    expect(setPenaltyClockRunning).toHaveBeenCalledWith(expect.anything(), 77, false);
  });

  it("stops all clocks when the game is marked final", async () => {
    prepareScoring(
      lockedRow({
        clock_remaining_ms: 120_000,
        clock_running: 1,
        clock_started_at: new Date(),
      }),
    );

    await applyGameScoringAction(77, {
      action: "finishGame",
    });

    const [sql, values] = gameUpdateCall();

    expect(valueForColumn(sql, values, "status")).toBe("FINAL");
    expect(valueForColumn(sql, values, "clock_remaining_ms")).toBe(0);
    expect(valueForColumn(sql, values, "clock_running")).toBe(false);

    expect(setPenaltyClockRunning).toHaveBeenCalledWith(expect.anything(), 77, false);
  });
});

describe("server-side game phase validation", () => {
  it("rejects intermission before the game clock reaches zero", async () => {
    prepareScoring(
      lockedRow({
        clock_remaining_ms: 60_000,
      }),
    );

    await expect(
      applyGameScoringAction(77, {
        action: "startIntermission",
      }),
    ).rejects.toThrow("Intermission can start only when the game clock is at 0:00");

    expect(rollback).toHaveBeenCalled();
  });

  it("rejects intermission after the game is final", async () => {
    prepareScoring(
      lockedRow({
        status: "FINAL",
      }),
    );

    await expect(
      applyGameScoringAction(77, {
        action: "startIntermission",
      }),
    ).rejects.toThrow("Intermission cannot start after the game is final");
  });

  it("requires intermission to finish or be skipped before the next period", async () => {
    prepareScoring(
      lockedRow({
        game_phase: "INTERMISSION",
        intermission_remaining_ms: 120_000,
        intermission_running: 0,
      }),
    );

    await expect(
      applyGameScoringAction(77, {
        action: "nextPeriod",
      }),
    ).rejects.toThrow("Finish or skip intermission before advancing periods");
  });

  it("requires regulation to reach zero before overtime", async () => {
    prepareScoring(
      lockedRow({
        period: 3,
        regulation_periods: 3,
        clock_remaining_ms: 30_000,
      }),
    );

    await expect(
      applyGameScoringAction(77, {
        action: "startOvertime",
      }),
    ).rejects.toThrow("Regulation must reach 0:00 before overtime");
  });

  it("requires intermission to finish or be skipped before overtime", async () => {
    prepareScoring(
      lockedRow({
        game_phase: "INTERMISSION",
        period: 3,
        regulation_periods: 3,
        intermission_remaining_ms: 90_000,
      }),
    );

    await expect(
      applyGameScoringAction(77, {
        action: "startOvertime",
      }),
    ).rejects.toThrow("Finish or skip intermission before starting overtime");
  });

  it("clears intermission state when the game is marked final", async () => {
    prepareScoring(
      lockedRow({
        intermission_remaining_ms: 90_000,
        intermission_running: 1,
        intermission_started_at: new Date(),
      }),
    );

    await applyGameScoringAction(77, {
      action: "finishGame",
    });

    const [sql, values] = gameUpdateCall();

    expect(valueForColumn(sql, values, "intermission_remaining_ms")).toBe(0);
    expect(valueForColumn(sql, values, "intermission_running")).toBe(false);
    expect(valueForColumn(sql, values, "intermission_started_at")).toBeNull();
  });

  it("clears stale intermission state after a manual period correction", async () => {
    prepareScoring(
      lockedRow({
        intermission_remaining_ms: 90_000,
        intermission_running: 0,
      }),
    );

    await applyGameScoringAction(77, {
      action: "setPeriod",
      period: 2,
    });

    const [sql, values] = gameUpdateCall();

    expect(valueForColumn(sql, values, "period")).toBe(2);
    expect(valueForColumn(sql, values, "intermission_remaining_ms")).toBe(0);
    expect(valueForColumn(sql, values, "intermission_running")).toBe(false);
  });
});

describe("persistent game phase transitions", () => {
  it("enters intermission when the intermission starts", async () => {
    prepareScoring(lockedRow());

    await applyGameScoringAction(77, { action: "startIntermission" });

    const [sql, values] = gameUpdateCall();
    expect(valueForColumn(sql, values, "game_phase")).toBe("INTERMISSION");
  });

  it("keeps the intermission phase while paused", async () => {
    prepareScoring(
      lockedRow({
        game_phase: "INTERMISSION",
        intermission_remaining_ms: 120_000,
        intermission_running: 1,
        intermission_started_at: new Date(),
      }),
    );

    await applyGameScoringAction(77, { action: "pauseIntermission" });

    const [sql, values] = gameUpdateCall();
    expect(valueForColumn(sql, values, "game_phase")).toBe("INTERMISSION");
    expect(valueForColumn(sql, values, "intermission_running")).toBe(false);
  });

  it("returns to regulation after intermission is skipped", async () => {
    prepareScoring(
      lockedRow({
        game_phase: "INTERMISSION",
        intermission_remaining_ms: 120_000,
      }),
    );

    await applyGameScoringAction(77, { action: "skipIntermission" });

    const [sql, values] = gameUpdateCall();
    expect(valueForColumn(sql, values, "game_phase")).toBe("REGULATION");
  });

  it("enters overtime through the overtime transition", async () => {
    prepareScoring(
      lockedRow({
        game_phase: "REGULATION",
        period: 3,
        regulation_periods: 3,
      }),
    );

    await applyGameScoringAction(77, { action: "startOvertime" });

    const [sql, values] = gameUpdateCall();
    expect(valueForColumn(sql, values, "game_phase")).toBe("OVERTIME");
  });

  it("enters final and clears both clocks", async () => {
    prepareScoring(
      lockedRow({
        game_phase: "INTERMISSION",
        intermission_remaining_ms: 90_000,
      }),
    );

    await applyGameScoringAction(77, { action: "finishGame" });

    const [sql, values] = gameUpdateCall();
    expect(valueForColumn(sql, values, "game_phase")).toBe("FINAL");
    expect(valueForColumn(sql, values, "clock_remaining_ms")).toBe(0);
    expect(valueForColumn(sql, values, "intermission_remaining_ms")).toBe(0);
  });
});

describe("completed intermission handoff", () => {
  it("allows the next period after a running intermission expires", async () => {
    prepareScoring(
      lockedRow({
        game_phase: "INTERMISSION",
        period: 1,
        intermission_remaining_ms: 1_000,
        intermission_running: 1,
        intermission_started_at: new Date(Date.now() - 2_000),
      }),
    );

    await applyGameScoringAction(77, { action: "nextPeriod" });

    const [sql, values] = gameUpdateCall();
    expect(valueForColumn(sql, values, "period")).toBe(2);
    expect(valueForColumn(sql, values, "game_phase")).toBe("REGULATION");
    expect(valueForColumn(sql, values, "intermission_remaining_ms")).toBe(0);
  });

  it("still blocks the next period while paused intermission time remains", async () => {
    prepareScoring(
      lockedRow({
        game_phase: "INTERMISSION",
        intermission_remaining_ms: 120_000,
        intermission_running: 0,
      }),
    );

    await expect(applyGameScoringAction(77, { action: "nextPeriod" })).rejects.toThrow(
      "Finish or skip intermission before advancing periods",
    );
  });

  it("allows overtime after the final regulation intermission expires", async () => {
    prepareScoring(
      lockedRow({
        game_phase: "INTERMISSION",
        period: 3,
        regulation_periods: 3,
        intermission_remaining_ms: 1_000,
        intermission_running: 1,
        intermission_started_at: new Date(Date.now() - 2_000),
      }),
    );

    await applyGameScoringAction(77, { action: "startOvertime" });

    const [sql, values] = gameUpdateCall();
    expect(valueForColumn(sql, values, "period")).toBe(4);
    expect(valueForColumn(sql, values, "game_phase")).toBe("OVERTIME");
    expect(valueForColumn(sql, values, "intermission_remaining_ms")).toBe(0);
  });

  it("keeps the game clock blocked after intermission expires until advancement", async () => {
    prepareScoring(
      lockedRow({
        game_phase: "INTERMISSION",
        clock_remaining_ms: 720_000,
        intermission_remaining_ms: 1_000,
        intermission_running: 1,
        intermission_started_at: new Date(Date.now() - 2_000),
      }),
    );

    await expect(applyGameScoringAction(77, { action: "startClock" })).rejects.toThrow(
      "Finish or skip intermission before starting the game clock",
    );
  });
});
