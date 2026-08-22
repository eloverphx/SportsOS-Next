import type {
  AuthoritativeGameSnapshot,
} from "./gameScoreboardSync.js";
import {
  AutomaticGameScoreboardSync,
} from "./automaticGameScoreboardSync.js";
import type {
  ScoreboardDeviceRecoveryService,
} from "./scoreboardDeviceRecovery.js";

let automaticSync:
  AutomaticGameScoreboardSync | null = null;

let recoveryService:
  ScoreboardDeviceRecoveryService | null = null;

export function bindAutomaticGameScoreboardSync(
  service: AutomaticGameScoreboardSync,
): void {
  automaticSync = service;
}

export function bindScoreboardDeviceRecovery(
  service: ScoreboardDeviceRecoveryService,
): void {
  recoveryService = service;
}

export function normalizeAuthoritativeGameUpdate(
  payload: unknown,
): AuthoritativeGameSnapshot | null {
  if (
    !payload ||
    typeof payload !== "object"
  ) {
    return null;
  }

  const record =
    payload as Record<string, unknown>;

  const nested =
    record.game &&
    typeof record.game === "object"
      ? record.game as Record<string, unknown>
      : record;

  const gameId =
    typeof nested.gameId === "string"
      ? nested.gameId
      : typeof nested.id === "string"
        ? nested.id
        : typeof record.gameId === "string"
          ? record.gameId
          : null;

  const homeScore =
    typeof nested.homeScore === "number"
      ? nested.homeScore
      : typeof record.homeScore === "number"
        ? record.homeScore
        : null;

  const awayScore =
    typeof nested.awayScore === "number"
      ? nested.awayScore
      : typeof record.awayScore === "number"
        ? record.awayScore
        : null;

  const period =
    nested.period === null
      ? null
      : typeof nested.period === "number"
        ? nested.period
        : record.period === null
          ? null
          : typeof record.period === "number"
            ? record.period
            : null;

  const clockObject =
    nested.clock &&
    typeof nested.clock === "object"
      ? nested.clock as Record<string, unknown>
      : record.clock &&
          typeof record.clock === "object"
        ? record.clock as Record<string, unknown>
        : null;

  const remainingMs =
    typeof nested.remainingMs === "number"
      ? nested.remainingMs
      : typeof nested.clockRemainingMs === "number"
        ? nested.clockRemainingMs
        : clockObject &&
            typeof clockObject.remainingMs === "number"
          ? clockObject.remainingMs
          : typeof record.remainingMs === "number"
            ? record.remainingMs
            : null;

  const running =
    typeof nested.isClockRunning === "boolean"
      ? nested.isClockRunning
      : typeof nested.clockRunning === "boolean"
        ? nested.clockRunning
        : clockObject &&
            typeof clockObject.running === "boolean"
          ? clockObject.running
          : typeof record.clockRunning === "boolean"
            ? record.clockRunning
            : null;

  if (
    !gameId ||
    homeScore === null ||
    awayScore === null ||
    remainingMs === null ||
    running === null
  ) {
    return null;
  }

  return {
    gameId,
    homeScore,
    awayScore,
    period,
    clock: {
      remainingMs,
      running,
    },
  };
}

export async function notifyAutomaticScoreboardGameUpdate(
  payload: unknown,
): Promise<void> {
  if (!automaticSync) {
    return;
  }

  const snapshot =
    normalizeAuthoritativeGameUpdate(
      payload,
    );

  if (!snapshot) {
    return;
  }

  recoveryService
    ?.rememberAuthoritativeSnapshot(
      snapshot,
    );

  await automaticSync
    .handleAuthoritativeSnapshot(
      snapshot,
    );
}
