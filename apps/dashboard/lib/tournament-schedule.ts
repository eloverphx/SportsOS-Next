export type ScheduleGame = {
  readonly id: number;
  readonly homeTeamId?: number | null;
  readonly awayTeamId?: number | null;
  readonly homeTeamName: string;
  readonly awayTeamName: string;
  readonly scheduledStart: string;
  readonly venue: string | null;
  readonly status: "SCHEDULED" | "LIVE" | "FINAL" | "POSTPONED" | "CANCELED";
  readonly regulationPeriods?: number;
  readonly regulationPeriodLengthMs?: number;
  readonly intermissionLengthMs?: number;
  readonly overtimeEnabled?: boolean;
  readonly overtimeLengthMs?: number;
};

export type ScheduleConflictCode =
  | "RINK_OVERLAP"
  | "TEAM_OVERLAP"
  | "TEAM_TURNAROUND"
  | "MISSING_RINK";

export type ScheduleConflict = {
  readonly code: ScheduleConflictCode;
  readonly severity: "ERROR" | "WARNING";
  readonly gameId: number;
  readonly relatedGameId: number | null;
  readonly message: string;
};

export type ScheduleRules = {
  readonly minimumTeamTurnaroundMs: number;
  readonly fallbackGameDurationMs: number;
};

export const DEFAULT_SCHEDULE_RULES: ScheduleRules = {
  minimumTeamTurnaroundMs: 60 * 60_000,
  fallbackGameDurationMs: 90 * 60_000,
};

function gameDurationMs(
  game: ScheduleGame,
  rules: ScheduleRules = DEFAULT_SCHEDULE_RULES,
): number {
  const periods = game.regulationPeriods;
  const periodLength = game.regulationPeriodLengthMs;
  const intermissionLength = game.intermissionLengthMs;

  if (
    Number.isFinite(periods) &&
    Number.isFinite(periodLength) &&
    Number.isFinite(intermissionLength) &&
    (periods ?? 0) > 0 &&
    (periodLength ?? 0) > 0
  ) {
    const regulation = (periods ?? 0) * (periodLength ?? 0);
    const intermissions = Math.max(0, (periods ?? 1) - 1) * (intermissionLength ?? 0);
    const overtime =
      game.overtimeEnabled && (game.overtimeLengthMs ?? 0) > 0
        ? game.overtimeLengthMs ?? 0
        : 0;

    return regulation + intermissions + overtime;
  }

  return rules.fallbackGameDurationMs;
}

function startMs(game: ScheduleGame): number {
  return new Date(game.scheduledStart).getTime();
}

function endMs(game: ScheduleGame, rules: ScheduleRules): number {
  return startMs(game) + gameDurationMs(game, rules);
}

function sameTeam(left: ScheduleGame, right: ScheduleGame): string | null {
  const pairs: Array<
    readonly [number | null | undefined, string, number | null | undefined, string]
  > = [
    [left.homeTeamId, left.homeTeamName, right.homeTeamId, right.homeTeamName],
    [left.homeTeamId, left.homeTeamName, right.awayTeamId, right.awayTeamName],
    [left.awayTeamId, left.awayTeamName, right.homeTeamId, right.homeTeamName],
    [left.awayTeamId, left.awayTeamName, right.awayTeamId, right.awayTeamName],
  ];

  for (const [leftId, leftName, rightId, rightName] of pairs) {
    if (leftId != null && rightId != null && leftId === rightId) return leftName;
    if (
      leftId == null &&
      rightId == null &&
      leftName.trim().toLowerCase() === rightName.trim().toLowerCase()
    ) {
      return leftName;
    }
  }

  return null;
}

function overlaps(
  left: ScheduleGame,
  right: ScheduleGame,
  rules: ScheduleRules,
): boolean {
  return startMs(left) < endMs(right, rules) && startMs(right) < endMs(left, rules);
}

export function detectScheduleConflicts(
  sourceGames: readonly ScheduleGame[],
  rules: ScheduleRules = DEFAULT_SCHEDULE_RULES,
): ScheduleConflict[] {
  const games = sourceGames.filter(
    (game) =>
      game.status !== "CANCELED" &&
      game.status !== "FINAL" &&
      Number.isFinite(startMs(game)),
  );

  const conflicts: ScheduleConflict[] = [];

  for (const game of games) {
    if (!game.venue?.trim()) {
      conflicts.push({
        code: "MISSING_RINK",
        severity: "WARNING",
        gameId: game.id,
        relatedGameId: null,
        message: `${game.homeTeamName} vs ${game.awayTeamName} has no rink assignment.`,
      });
    }
  }

  for (let index = 0; index < games.length; index += 1) {
    const left = games[index];
    if (!left) continue;

    for (let otherIndex = index + 1; otherIndex < games.length; otherIndex += 1) {
      const right = games[otherIndex];
      if (!right) continue;

      if (
        left.venue?.trim() &&
        right.venue?.trim() &&
        left.venue.trim().toLowerCase() === right.venue.trim().toLowerCase() &&
        overlaps(left, right, rules)
      ) {
        conflicts.push({
          code: "RINK_OVERLAP",
          severity: "ERROR",
          gameId: left.id,
          relatedGameId: right.id,
          message: `${left.venue} is double-booked for games #${left.id} and #${right.id}.`,
        });
      }

      const sharedTeam = sameTeam(left, right);
      if (!sharedTeam) continue;

      if (overlaps(left, right, rules)) {
        conflicts.push({
          code: "TEAM_OVERLAP",
          severity: "ERROR",
          gameId: left.id,
          relatedGameId: right.id,
          message: `${sharedTeam} is scheduled in overlapping games #${left.id} and #${right.id}.`,
        });
        continue;
      }

      const earlier = startMs(left) <= startMs(right) ? left : right;
      const later = earlier === left ? right : left;
      const turnaround = startMs(later) - endMs(earlier, rules);

      if (turnaround >= 0 && turnaround < rules.minimumTeamTurnaroundMs) {
        conflicts.push({
          code: "TEAM_TURNAROUND",
          severity: "WARNING",
          gameId: earlier.id,
          relatedGameId: later.id,
          message: `${sharedTeam} has only ${Math.floor(
            turnaround / 60_000,
          )} minutes between games #${earlier.id} and #${later.id}.`,
        });
      }
    }
  }

  return conflicts.sort((left, right) => {
    if (left.severity !== right.severity) return left.severity === "ERROR" ? -1 : 1;
    if (left.gameId !== right.gameId) return left.gameId - right.gameId;
    return (left.relatedGameId ?? 0) - (right.relatedGameId ?? 0);
  });
}
