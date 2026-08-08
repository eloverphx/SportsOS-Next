import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  applyGameEngineAction,
  type GameEngineState,
} from "../src/modules/games/engine.js";

const poolExecute = vi.fn();
const applyGameScoringAction = vi.fn();

vi.mock("../src/infrastructure/database.js", () => ({
  pool: {
    execute: poolExecute,
  },
}));

vi.mock("../src/modules/games/repository.js", () => ({
  applyGameScoringAction,
}));

const { processAutomaticLifecycleTransitions } = await import(
  "../src/modules/games/runtime-supervisor.js"
);

function state(
  overrides: Partial<GameEngineState> = {},
): GameEngineState {
  return {
    homeScore: 0,
    awayScore: 0,
    status: "LIVE",
    gamePhase: "REGULATION",
    period: 1,
    periodLengthMs: 900_000,
    clockRemainingMs: 900_000,
    clockRunning: false,
    clockStartedAt: null,
    regulationPeriods: 3,
    regulationPeriodLengthMs: 900_000,
    intermissionLengthMs: 600_000,
    intermissionRemainingMs: 0,
    intermissionRunning: false,
    intermissionStartedAt: null,
    overtimeEnabled: true,
    overtimeLengthMs: 300_000,
    ...overrides,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("game engine stress and reliability", () => {
  it("isolates state across 100 simultaneous logical games", () => {
    const games = Array.from({ length: 100 }, (_, index) =>
      state({
        homeScore: index,
        awayScore: 100 - index,
        period: (index % 3) + 1,
      }),
    );

    const results = games.map((game, index) =>
      applyGameEngineAction(game, {
        action: "adjustScore",
        side: index % 2 === 0 ? "home" : "away",
        amount: 1,
      }).state,
    );

    for (let index = 0; index < games.length; index += 1) {
      const original = games[index]!;
      const updated = results[index]!;

      if (index % 2 === 0) {
        expect(updated.homeScore).toBe(original.homeScore + 1);
        expect(updated.awayScore).toBe(original.awayScore);
      } else {
        expect(updated.homeScore).toBe(original.homeScore);
        expect(updated.awayScore).toBe(original.awayScore + 1);
      }

      expect(original.homeScore).toBe(index);
      expect(original.awayScore).toBe(100 - index);
    }
  });

  it("survives 10,000 rapid start/pause cycles without corrupting clock state", () => {
    let current = state({
      clockRemainingMs: 300_000,
      clockRunning: false,
    });

    for (let index = 0; index < 10_000; index += 1) {
      current = applyGameEngineAction(
        current,
        { action: "startClock" },
        new Date(1_000 + index),
      ).state;

      expect(current.clockRunning).toBe(true);
      expect(current.clockRemainingMs).toBe(300_000);

      current = applyGameEngineAction(current, {
        action: "pauseClock",
      }).state;

      expect(current.clockRunning).toBe(false);
      expect(current.clockStartedAt).toBeNull();
      expect(current.clockRemainingMs).toBe(300_000);
    }
  });

  it("clamps 20,000 clock corrections safely between zero and two hours", () => {
    let current = state({
      clockRemainingMs: 60_000,
    });

    for (let index = 0; index < 10_000; index += 1) {
      current = applyGameEngineAction(current, {
        action: "adjustClock",
        amountMs: 1_000_000,
      }).state;
    }

    expect(current.clockRemainingMs).toBe(7_200_000);

    for (let index = 0; index < 10_000; index += 1) {
      current = applyGameEngineAction(current, {
        action: "adjustClock",
        amountMs: -1_000_000,
      }).state;
    }

    expect(current.clockRemainingMs).toBe(0);
    expect(current.clockRunning).toBe(false);
  });

  it("keeps score changes inside the supported 0-999 range under heavy input", () => {
    let current = state();

    for (let index = 0; index < 5_000; index += 1) {
      current = applyGameEngineAction(current, {
        action: "adjustScore",
        side: "home",
        amount: 1,
      }).state;
    }

    expect(current.homeScore).toBe(999);

    for (let index = 0; index < 5_000; index += 1) {
      current = applyGameEngineAction(current, {
        action: "adjustScore",
        side: "home",
        amount: -1,
      }).state;
    }

    expect(current.homeScore).toBe(0);
  });

  it("processes 100 completed regulation periods in a single supervisor pass", async () => {
    const candidates = Array.from({ length: 100 }, (_, index) => ({
      id: index + 1,
      organization_id: (index % 5) + 1,
      period: index % 2 === 0 ? 1 : 2,
    }));

    poolExecute
      .mockResolvedValueOnce([candidates])
      .mockResolvedValueOnce([[]]);

    applyGameScoringAction.mockResolvedValue({
      game: {},
      applied: true,
    });

    await expect(processAutomaticLifecycleTransitions()).resolves.toEqual({
      intermissionsStarted: 100,
      periodsPrepared: 0,
    });

    expect(applyGameScoringAction).toHaveBeenCalledTimes(100);

    const commandIds = applyGameScoringAction.mock.calls.map(
      (call) => call[2],
    );

    expect(new Set(commandIds).size).toBe(100);
  });

  it("processes 100 expired intermissions independently", async () => {
    const candidates = Array.from({ length: 100 }, (_, index) => ({
      id: index + 101,
      organization_id: (index % 5) + 1,
      period: index % 2 === 0 ? 1 : 2,
    }));

    poolExecute
      .mockResolvedValueOnce([[]])
      .mockResolvedValueOnce([candidates]);

    applyGameScoringAction.mockResolvedValue({
      game: {},
      applied: true,
    });

    await expect(processAutomaticLifecycleTransitions()).resolves.toEqual({
      intermissionsStarted: 0,
      periodsPrepared: 100,
    });

    expect(applyGameScoringAction).toHaveBeenCalledTimes(100);
  });

  it("does not count replayed supervisor commands as fresh transitions", async () => {
    const candidates = Array.from({ length: 50 }, (_, index) => ({
      id: index + 1,
      organization_id: 1,
      period: 1,
    }));

    poolExecute
      .mockResolvedValueOnce([candidates])
      .mockResolvedValueOnce([[]]);

    applyGameScoringAction.mockResolvedValue(null);

    await expect(processAutomaticLifecycleTransitions()).resolves.toEqual({
      intermissionsStarted: 0,
      periodsPrepared: 0,
    });

    expect(applyGameScoringAction).toHaveBeenCalledTimes(50);
  });

  it("maintains configured regulation length after repeated manual clock corrections", () => {
    let current = state({
      regulationPeriodLengthMs: 900_000,
      periodLengthMs: 900_000,
      clockRemainingMs: 900_000,
    });

    for (let index = 0; index < 1_000; index += 1) {
      current = applyGameEngineAction(current, {
        action: "setClock",
        clockRemainingMs: (index % 600) * 1_000,
      }).state;
    }

    expect(current.regulationPeriodLengthMs).toBe(900_000);
    expect(current.periodLengthMs).toBe(900_000);
  });
});
