export type BroadcastOverlayTeam = {
  id: string;
  name: string;
  shortName: string | null;
  logoUrl: string | null;
  score: number;
};

export type BroadcastOverlayClock = {
  remainingMs: number;
  running: boolean;
};

export type BroadcastOverlayPowerPlay = {
  teamId: string;
  remainingMs: number;
} | null;

export type BroadcastOverlaySnapshot = {
  version: 1;
  generatedAt: string;
  gameId: string;
  status: string;
  phase: string | null;
  period: number | null;
  home: BroadcastOverlayTeam;
  away: BroadcastOverlayTeam;
  clock: BroadcastOverlayClock;
  powerPlay: BroadcastOverlayPowerPlay;
};

type UnknownRecord = Record<string, unknown>;

function record(value: unknown): UnknownRecord | null {
  return value && typeof value === "object"
    ? (value as UnknownRecord)
    : null;
}

function stringValue(
  value: unknown,
  fallback = "",
): string {
  return typeof value === "string" ? value : fallback;
}

function nullableString(
  value: unknown,
): string | null {
  return typeof value === "string" && value.trim()
    ? value
    : null;
}

function numberValue(
  value: unknown,
  fallback = 0,
): number {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : fallback;
}

function nullableNumber(
  value: unknown,
): number | null {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : null;
}

function booleanValue(
  value: unknown,
  fallback = false,
): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function teamSnapshot(
  teamValue: unknown,
  fallbackId: unknown,
  fallbackName: unknown,
  fallbackScore: unknown,
): BroadcastOverlayTeam {
  const team = record(teamValue);

  return {
    id:
      stringValue(team?.id) ||
      stringValue(fallbackId),
    name:
      stringValue(team?.name) ||
      stringValue(fallbackName) ||
      "Unknown",
    shortName:
      nullableString(team?.shortName) ??
      nullableString(team?.abbreviation),
    logoUrl:
      nullableString(team?.logoUrl) ??
      nullableString(team?.logo),
    score: numberValue(fallbackScore),
  };
}

export function normalizeBroadcastOverlaySnapshot(
  gameValue: unknown,
  generatedAt = new Date(),
): BroadcastOverlaySnapshot {
  const game = record(gameValue);

  if (!game) {
    throw new Error(
      "Broadcast overlay game payload must be an object.",
    );
  }

  const gameId = stringValue(game.id);

  if (!gameId) {
    throw new Error(
      "Broadcast overlay game payload is missing id.",
    );
  }

  const remainingMs =
    nullableNumber(game.remainingMs) ??
    nullableNumber(game.clockRemainingMs) ??
    nullableNumber(record(game.clock)?.remainingMs) ??
    0;

  const running =
    booleanValue(game.isClockRunning) ||
    booleanValue(game.clockRunning) ||
    booleanValue(record(game.clock)?.running);

  const powerPlayRecord =
    record(game.powerPlay) ??
    record(game.activePowerPlay);

  const powerPlayTeamId =
    stringValue(powerPlayRecord?.teamId);

  const powerPlayRemainingMs =
    nullableNumber(powerPlayRecord?.remainingMs);

  return {
    version: 1,
    generatedAt: generatedAt.toISOString(),
    gameId,
    status: stringValue(game.status, "UNKNOWN"),
    phase:
      nullableString(game.gamePhase) ??
      nullableString(game.phase),
    period:
      nullableNumber(game.period) ??
      nullableNumber(game.currentPeriod),
    home: teamSnapshot(
      game.homeTeam,
      game.homeTeamId,
      game.homeTeamName,
      game.homeScore,
    ),
    away: teamSnapshot(
      game.awayTeam,
      game.awayTeamId,
      game.awayTeamName,
      game.awayScore,
    ),
    clock: {
      remainingMs: Math.max(0, remainingMs),
      running,
    },
    powerPlay:
      powerPlayTeamId &&
      powerPlayRemainingMs !== null
        ? {
            teamId: powerPlayTeamId,
            remainingMs: Math.max(
              0,
              powerPlayRemainingMs,
            ),
          }
        : null,
  };
}
