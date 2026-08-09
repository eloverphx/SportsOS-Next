export type ServerScheduleGame = {
  readonly id: number;
  readonly homeTeamId: number | null;
  readonly awayTeamId: number | null;
  readonly homeTeamName: string;
  readonly awayTeamName: string;
  readonly scheduledStart: string;
  readonly venue: string | null;
  readonly status: string;
  readonly regulationPeriods: number;
  readonly regulationPeriodLengthMs: number;
  readonly intermissionLengthMs: number;
  readonly overtimeEnabled: boolean;
  readonly overtimeLengthMs: number;
};

export type ProposedScheduleGame = {
  readonly id: number;
  readonly homeTeamId: number | null;
  readonly awayTeamId: number | null;
  readonly homeTeamName: string;
  readonly awayTeamName: string;
  readonly scheduledStart: string;
  readonly venue: string | null;
  readonly status: string;
  readonly regulationPeriods: number;
  readonly regulationPeriodLengthMs: number;
  readonly intermissionLengthMs: number;
  readonly overtimeEnabled: boolean;
  readonly overtimeLengthMs: number;
};

export type ServerScheduleConflict = {
  readonly code:
    | "RINK_OVERLAP"
    | "TEAM_OVERLAP"
    | "TEAM_TURNAROUND"
    | "MISSING_RINK";
  readonly severity: "ERROR" | "WARNING";
  readonly gameId: number;
  readonly relatedGameId: number | null;
  readonly message: string;
};

const MINIMUM_TEAM_TURNAROUND_MS = 60 * 60_000;
const FALLBACK_GAME_DURATION_MS = 90 * 60_000;

function startMs(game: ServerScheduleGame | ProposedScheduleGame): number {
  return new Date(game.scheduledStart).getTime();
}

function durationMs(game: ServerScheduleGame | ProposedScheduleGame): number {
  if (
    Number.isFinite(game.regulationPeriods) &&
    Number.isFinite(game.regulationPeriodLengthMs) &&
    Number.isFinite(game.intermissionLengthMs) &&
    game.regulationPeriods > 0 &&
    game.regulationPeriodLengthMs > 0
  ) {
    return (
      game.regulationPeriods * game.regulationPeriodLengthMs +
      Math.max(0, game.regulationPeriods - 1) * game.intermissionLengthMs +
      (game.overtimeEnabled && game.overtimeLengthMs > 0 ? game.overtimeLengthMs : 0)
    );
  }

  return FALLBACK_GAME_DURATION_MS;
}

function endMs(game: ServerScheduleGame | ProposedScheduleGame): number {
  return startMs(game) + durationMs(game);
}

function overlaps(
  left: ServerScheduleGame | ProposedScheduleGame,
  right: ServerScheduleGame | ProposedScheduleGame,
): boolean {
  return startMs(left) < endMs(right) && startMs(right) < endMs(left);
}

function sharedTeamName(
  left: ServerScheduleGame | ProposedScheduleGame,
  right: ServerScheduleGame | ProposedScheduleGame,
): string | null {
  const pairs: Array<
    readonly [number | null, string, number | null, string]
  > = [
    [left.homeTeamId, left.homeTeamName, right.homeTeamId, right.homeTeamName],
    [left.homeTeamId, left.homeTeamName, right.awayTeamId, right.awayTeamName],
    [left.awayTeamId, left.awayTeamName, right.homeTeamId, right.homeTeamName],
    [left.awayTeamId, left.awayTeamName, right.awayTeamId, right.awayTeamName],
  ];

  for (const [leftId, leftName, rightId, rightName] of pairs) {
    if (leftId !== null && rightId !== null && leftId === rightId) return leftName;

    if (
      leftId === null &&
      rightId === null &&
      leftName.trim().toLowerCase() === rightName.trim().toLowerCase()
    ) {
      return leftName;
    }
  }

  return null;
}

export function detectServerScheduleConflicts(
  proposed: ProposedScheduleGame,
  existingGames: readonly ServerScheduleGame[],
): ServerScheduleConflict[] {
  if (proposed.status === "CANCELED" || proposed.status === "FINAL") return [];

  const conflicts: ServerScheduleConflict[] = [];

  if (!proposed.venue?.trim()) {
    conflicts.push({
      code: "MISSING_RINK",
      severity: "WARNING",
      gameId: proposed.id,
      relatedGameId: null,
      message: `${proposed.homeTeamName} vs ${proposed.awayTeamName} has no rink assignment.`,
    });
  }

  for (const other of existingGames) {
    if (
      other.id === proposed.id ||
      other.status === "CANCELED" ||
      other.status === "FINAL" ||
      !Number.isFinite(startMs(other))
    ) {
      continue;
    }

    if (
      proposed.venue?.trim() &&
      other.venue?.trim() &&
      proposed.venue.trim().toLowerCase() === other.venue.trim().toLowerCase() &&
      overlaps(proposed, other)
    ) {
      conflicts.push({
        code: "RINK_OVERLAP",
        severity: "ERROR",
        gameId: proposed.id,
        relatedGameId: other.id,
        message: `${proposed.venue} is double-booked for games #${proposed.id} and #${other.id}.`,
      });
    }

    const teamName = sharedTeamName(proposed, other);
    if (!teamName) continue;

    if (overlaps(proposed, other)) {
      conflicts.push({
        code: "TEAM_OVERLAP",
        severity: "ERROR",
        gameId: proposed.id,
        relatedGameId: other.id,
        message: `${teamName} is scheduled in overlapping games #${proposed.id} and #${other.id}.`,
      });
      continue;
    }

    const proposedFirst = startMs(proposed) <= startMs(other);
    const earlier = proposedFirst ? proposed : other;
    const later = proposedFirst ? other : proposed;
    const turnaroundMs = startMs(later) - endMs(earlier);

    if (turnaroundMs >= 0 && turnaroundMs < MINIMUM_TEAM_TURNAROUND_MS) {
      conflicts.push({
        code: "TEAM_TURNAROUND",
        severity: "WARNING",
        gameId: proposed.id,
        relatedGameId: other.id,
        message: `${teamName} has only ${Math.floor(
          turnaroundMs / 60_000,
        )} minutes between games #${earlier.id} and #${later.id}.`,
      });
    }
  }

  return conflicts.sort((left, right) => {
    if (left.severity !== right.severity) {
      return left.severity === "ERROR" ? -1 : 1;
    }
    return (left.relatedGameId ?? 0) - (right.relatedGameId ?? 0);
  });
}

export function hasHardScheduleConflicts(
  conflicts: readonly ServerScheduleConflict[],
): boolean {
  return conflicts.some((conflict) => conflict.severity === "ERROR");
}
