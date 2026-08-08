import { describe, expect, it } from "vitest";
import {
  applyGameEngineAction,
  GamePhaseError,
  type GameEngineState,
} from "../src/modules/games/engine.js";

function state(overrides: Partial<GameEngineState> = {}): GameEngineState {
  return {
    homeScore: 0,
    awayScore: 0,
    status: "SCHEDULED",
    gamePhase: "PREGAME",
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

describe("authoritative game engine", () => {
  it("starts a scheduled game in regulation", () => {
    const now = new Date("2026-08-08T13:00:00.000Z");
    const result = applyGameEngineAction(state(), { action: "startClock" }, now);

    expect(result.state.status).toBe("LIVE");
    expect(result.state.gamePhase).toBe("REGULATION");
    expect(result.state.clockRunning).toBe(true);
    expect(result.state.clockStartedAt).toEqual(now);
  });

  it("runs regulation period handoff through intermission", () => {
    const ended = state({
      status: "LIVE",
      gamePhase: "REGULATION",
      period: 1,
      clockRemainingMs: 0,
    });

    const intermission = applyGameEngineAction(ended, {
      action: "startIntermission",
    }).state;

    expect(intermission.gamePhase).toBe("INTERMISSION");
    expect(intermission.intermissionRemainingMs).toBe(600_000);
    expect(intermission.intermissionRunning).toBe(true);

    const completed = {
      ...intermission,
      intermissionRemainingMs: 0,
      intermissionRunning: false,
      intermissionStartedAt: null,
    };

    const periodTwo = applyGameEngineAction(completed, {
      action: "nextPeriod",
    }).state;

    expect(periodTwo.period).toBe(2);
    expect(periodTwo.gamePhase).toBe("REGULATION");
    expect(periodTwo.clockRemainingMs).toBe(900_000);
    expect(periodTwo.clockRunning).toBe(false);
  });

  it("requires an explicit overtime or final decision after regulation", () => {
    const endedRegulation = state({
      status: "LIVE",
      gamePhase: "REGULATION",
      period: 3,
      clockRemainingMs: 0,
    });

    expect(() =>
      applyGameEngineAction(endedRegulation, { action: "nextPeriod" }),
    ).toThrow("Choose overtime or final after regulation has ended");
  });

  it("enters configured overtime after regulation", () => {
    const endedRegulation = state({
      status: "LIVE",
      gamePhase: "REGULATION",
      period: 3,
      clockRemainingMs: 0,
      overtimeLengthMs: 240_000,
    });

    const overtime = applyGameEngineAction(endedRegulation, {
      action: "startOvertime",
    }).state;

    expect(overtime.status).toBe("LIVE");
    expect(overtime.gamePhase).toBe("OVERTIME");
    expect(overtime.period).toBe(4);
    expect(overtime.periodLengthMs).toBe(240_000);
    expect(overtime.clockRemainingMs).toBe(240_000);
    expect(overtime.clockRunning).toBe(false);
  });

  it("finishes a game and stops every game timer", () => {
    const final = applyGameEngineAction(
      state({
        status: "LIVE",
        gamePhase: "OVERTIME",
        period: 4,
        clockRemainingMs: 100_000,
        clockRunning: true,
        clockStartedAt: new Date(),
        intermissionRemainingMs: 50_000,
        intermissionRunning: true,
        intermissionStartedAt: new Date(),
      }),
      { action: "finishGame" },
    ).state;

    expect(final.status).toBe("FINAL");
    expect(final.gamePhase).toBe("FINAL");
    expect(final.clockRemainingMs).toBe(0);
    expect(final.clockRunning).toBe(false);
    expect(final.intermissionRemainingMs).toBe(0);
    expect(final.intermissionRunning).toBe(false);
  });

  it("rejects clock start during intermission", () => {
    expect(() =>
      applyGameEngineAction(
        state({
          status: "LIVE",
          gamePhase: "INTERMISSION",
          intermissionRemainingMs: 120_000,
        }),
        { action: "startClock" },
      ),
    ).toThrow(GamePhaseError);
  });

  it("returns penalty-clock delta for manual game-clock corrections", () => {
    const result = applyGameEngineAction(
      state({
        status: "LIVE",
        gamePhase: "REGULATION",
        clockRemainingMs: 300_000,
      }),
      { action: "adjustClock", amountMs: 30_000 },
    );

    expect(result.state.clockRemainingMs).toBe(330_000);
    expect(result.penaltyClockAdjustmentMs).toBe(30_000);
  });

  it("does not mutate its input state", () => {
    const original = state();
    const before = structuredClone(original);

    applyGameEngineAction(original, { action: "startClock" });

    expect(original).toEqual(before);
  });
});
