import {
  gameDayHardwarePreflightFreshness,
  latestGameDayHardwarePreflight,
  matchesCurrentAssignment,
} from "./gameDayHardwarePreflight.js";

export type GameStartPreflightDecision =
  | {
      allowed: true;
      gameId: string;
      preflightId: string;
      deviceId: string;
      expiresAt: string;
    }
  | {
      allowed: false;
      gameId: string;
      code:
        | "PREFLIGHT_REQUIRED"
        | "PREFLIGHT_FAILED"
        | "PREFLIGHT_EXPIRED"
        | "PREFLIGHT_ASSIGNMENT_CHANGED";
      message: string;
      preflightId: string | null;
      deviceId: string | null;
      expiresAt: string | null;
    };

export function evaluateGameStartPreflight(
  gameId: string,
  currentDeviceId: string | null = null,
): GameStartPreflightDecision {
  const preflight =
    latestGameDayHardwarePreflight(
      gameId,
    );

  const freshness =
    gameDayHardwarePreflightFreshness(
      preflight,
    );

  if (!preflight) {
    return {
      allowed: false,
      gameId,
      code:
        "PREFLIGHT_REQUIRED",
      message:
        "Run and pass a game-day hardware preflight before starting the game.",
      preflightId:
        null,
      deviceId:
        null,
      expiresAt:
        null,
    };
  }

  if (
    currentDeviceId &&
    !matchesCurrentAssignment(
      preflight,
      gameId,
      currentDeviceId,
    )
  ) {
    return {
      allowed: false,
      gameId,
      code:
        "PREFLIGHT_ASSIGNMENT_CHANGED",
      message:
        "The scoreboard assignment changed after the latest preflight. Run a new preflight for the currently assigned device.",
      preflightId:
        preflight.preflightId,
      deviceId:
        preflight.deviceId,
      expiresAt:
        freshness.expiresAt,
    };
  }

  if (
    preflight.status !==
      "PASS"
  ) {
    return {
      allowed: false,
      gameId,
      code:
        "PREFLIGHT_FAILED",
      message:
        "The latest game-day hardware preflight failed. Resolve the failed checks and rerun preflight.",
      preflightId:
        preflight.preflightId,
      deviceId:
        preflight.deviceId,
      expiresAt:
        freshness.expiresAt,
    };
  }

  if (
    !freshness.fresh ||
    !freshness.expiresAt
  ) {
    return {
      allowed: false,
      gameId,
      code:
        "PREFLIGHT_EXPIRED",
      message:
        "The latest passing game-day hardware preflight has expired. Rerun preflight.",
      preflightId:
        preflight.preflightId,
      deviceId:
        preflight.deviceId,
      expiresAt:
        freshness.expiresAt,
    };
  }

  return {
    allowed: true,
    gameId,
    preflightId:
      preflight.preflightId,
    deviceId:
      preflight.deviceId,
    expiresAt:
      freshness.expiresAt,
  };
}
