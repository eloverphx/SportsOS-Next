import type { ScoreAction } from "./schemas.js";
import type { GamePhase, GameStatus } from "./types.js";

export class GamePhaseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GamePhaseError";
  }
}

export interface GameEngineState {
  homeScore: number;
  awayScore: number;
  status: GameStatus;
  gamePhase: GamePhase;
  period: number;
  periodLengthMs: number;
  clockRemainingMs: number;
  clockRunning: boolean;
  clockStartedAt: Date | null;
  regulationPeriods: number;
  regulationPeriodLengthMs: number;
  intermissionLengthMs: number;
  intermissionRemainingMs: number;
  intermissionRunning: boolean;
  intermissionStartedAt: Date | null;
  overtimeEnabled: boolean;
  overtimeLengthMs: number;
}

export interface GameEngineTransition {
  state: GameEngineState;
  penaltyClockAdjustmentMs: number;
}

function copyDate(value: Date): Date {
  return new Date(value.getTime());
}

export function applyGameEngineAction(
  current: Readonly<GameEngineState>,
  action: ScoreAction,
  now = new Date(),
): GameEngineTransition {
  const state: GameEngineState = {
    ...current,
    clockStartedAt: current.clockStartedAt ? copyDate(current.clockStartedAt) : null,
    intermissionStartedAt: current.intermissionStartedAt
      ? copyDate(current.intermissionStartedAt)
      : null,
  };

  const previousClockRemainingMs = state.clockRemainingMs;

  switch (action.action) {
    case "adjustScore":
      if (action.side === "home") {
        state.homeScore = Math.max(0, Math.min(999, state.homeScore + action.amount));
      } else {
        state.awayScore = Math.max(0, Math.min(999, state.awayScore + action.amount));
      }
      break;

    case "setScore":
      state.homeScore = action.homeScore;
      state.awayScore = action.awayScore;
      break;

    case "startClock":
      if (state.status === "FINAL") {
        throw new GamePhaseError("A final game cannot be restarted");
      }
      if (state.gamePhase === "INTERMISSION") {
        throw new GamePhaseError(
          "Finish or skip intermission before starting the game clock",
        );
      }
      if (state.clockRemainingMs > 0) {
        state.clockRunning = true;
        state.clockStartedAt = copyDate(now);
        if (state.status === "SCHEDULED") state.status = "LIVE";
        if (state.gamePhase === "PREGAME") state.gamePhase = "REGULATION";
      }
      break;

    case "pauseClock":
      state.clockRunning = false;
      state.clockStartedAt = null;
      break;

    case "startIntermission":
      if (state.status === "FINAL") {
        throw new GamePhaseError("Intermission cannot start after the game is final");
      }
      if (state.clockRemainingMs > 0) {
        throw new GamePhaseError(
          "Intermission can start only when the game clock is at 0:00",
        );
      }
      state.clockRunning = false;
      state.clockStartedAt = null;
      if (state.intermissionRemainingMs <= 0) {
        state.intermissionRemainingMs = state.intermissionLengthMs;
      }
      state.intermissionRunning = state.intermissionRemainingMs > 0;
      state.intermissionStartedAt = state.intermissionRunning ? copyDate(now) : null;
      if (state.intermissionRemainingMs > 0) state.gamePhase = "INTERMISSION";
      break;

    case "pauseIntermission":
      state.intermissionRunning = false;
      state.intermissionStartedAt = null;
      break;

    case "resetIntermission":
      state.intermissionRemainingMs = state.intermissionLengthMs;
      state.intermissionRunning = false;
      state.intermissionStartedAt = null;
      break;

    case "setIntermission":
      state.intermissionLengthMs = action.intermissionLengthMs;
      state.intermissionRemainingMs = action.intermissionLengthMs;
      state.intermissionRunning = false;
      state.intermissionStartedAt = null;
      break;

    case "skipIntermission":
      state.intermissionRemainingMs = 0;
      state.intermissionRunning = false;
      state.intermissionStartedAt = null;
      state.gamePhase =
        state.period > state.regulationPeriods ? "OVERTIME" : "REGULATION";
      break;

    case "nextPeriod":
      state.clockRunning = false;
      state.clockStartedAt = null;

      if (state.status === "FINAL") {
        throw new GamePhaseError("A final game cannot advance to another period");
      }
      if (state.clockRemainingMs > 0) {
        throw new GamePhaseError(
          "The game clock must be at 0:00 before advancing periods",
        );
      }
      if (state.gamePhase === "INTERMISSION" && state.intermissionRemainingMs > 0) {
        throw new GamePhaseError(
          "Finish or skip intermission before advancing periods",
        );
      }
      if (state.period >= state.regulationPeriods) {
        throw new GamePhaseError(
          "Choose overtime or final after regulation has ended",
        );
      }

      state.period += 1;
      state.periodLengthMs = current.periodLengthMs;
      state.clockRemainingMs = state.periodLengthMs;
      state.intermissionRemainingMs = 0;
      state.intermissionRunning = false;
      state.intermissionStartedAt = null;
      state.gamePhase = "REGULATION";
      break;

    case "startOvertime":
      state.clockRunning = false;
      state.clockStartedAt = null;

      if (state.status === "FINAL") {
        throw new GamePhaseError("A final game cannot enter overtime");
      }
      if (!state.overtimeEnabled) {
        throw new GamePhaseError("Overtime is disabled for this game");
      }
      if (state.period < state.regulationPeriods) {
        throw new GamePhaseError("Regulation has not ended");
      }
      if (state.clockRemainingMs > 0) {
        throw new GamePhaseError("Regulation must reach 0:00 before overtime");
      }
      if (state.gamePhase === "INTERMISSION" && state.intermissionRemainingMs > 0) {
        throw new GamePhaseError(
          "Finish or skip intermission before starting overtime",
        );
      }

      state.period = Math.max(state.period + 1, state.regulationPeriods + 1);
      state.periodLengthMs = state.overtimeLengthMs;
      state.clockRemainingMs = state.overtimeLengthMs;
      state.clockRunning = false;
      state.clockStartedAt = null;
      state.status = "LIVE";
      state.intermissionRemainingMs = 0;
      state.intermissionRunning = false;
      state.intermissionStartedAt = null;
      state.gamePhase = "OVERTIME";
      break;

    case "finishGame":
      state.clockRunning = false;
      state.clockStartedAt = null;
      state.clockRemainingMs = 0;
      state.intermissionRemainingMs = 0;
      state.intermissionRunning = false;
      state.intermissionStartedAt = null;
      state.status = "FINAL";
      state.gamePhase = "FINAL";
      break;

    case "resetClock":
      state.periodLengthMs = action.periodLengthMs ?? state.periodLengthMs;
      state.clockRemainingMs = state.periodLengthMs;
      state.clockRunning = false;
      state.clockStartedAt = null;
      break;

    case "adjustClock":
      state.clockRemainingMs = Math.max(
        0,
        Math.min(7_200_000, state.clockRemainingMs + action.amountMs),
      );
      state.clockRunning = state.clockRunning && state.clockRemainingMs > 0;
      state.clockStartedAt = state.clockRunning ? copyDate(now) : null;
      break;

    case "setClock":
      state.clockRemainingMs = action.clockRemainingMs;
      state.periodLengthMs = action.clockRemainingMs;
      state.clockRunning = false;
      state.clockStartedAt = null;
      break;

    case "setPeriod":
      state.period = action.period;
      state.intermissionRemainingMs = 0;
      state.intermissionRunning = false;
      state.intermissionStartedAt = null;
      state.gamePhase =
        state.period > state.regulationPeriods ? "OVERTIME" : "REGULATION";
      state.clockStartedAt = state.clockRunning ? copyDate(now) : null;
      break;

    case "setStatus":
      state.status = action.status;

      if (state.status !== "LIVE") {
        state.clockRunning = false;
        state.clockStartedAt = null;
        state.intermissionRunning = false;
        state.intermissionStartedAt = null;
      }

      if (state.status === "FINAL") {
        state.clockRemainingMs = 0;
        state.intermissionRemainingMs = 0;
        state.gamePhase = "FINAL";
      } else if (state.status === "SCHEDULED") {
        state.gamePhase = "PREGAME";
      } else if (state.status === "LIVE" && state.gamePhase === "PREGAME") {
        state.gamePhase =
          state.period > state.regulationPeriods ? "OVERTIME" : "REGULATION";
      }
      break;
  }

  if (state.clockRemainingMs === 0) {
    state.clockRunning = false;
    state.clockStartedAt = null;
  }

  const penaltyClockAdjustmentMs =
    action.action === "adjustClock" ||
    action.action === "setClock" ||
    action.action === "resetClock"
      ? state.clockRemainingMs - previousClockRemainingMs
      : 0;

  return { state, penaltyClockAdjustmentMs };
}
