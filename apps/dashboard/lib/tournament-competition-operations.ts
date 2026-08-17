export type TournamentCompetitionStage =
  | "NOT_STARTED"
  | "POOL_PLAY"
  | "BRACKET_READY"
  | "BRACKET_ACTIVE"
  | "COMPLETE";

export type TournamentCompetitionOperationsInput = {
  totalTeams: number;
  finalizedGames: number;
  scheduledGames: number;
  seededTeams: number;
  resolvedBracketMatchups: number;
  totalBracketMatchups: number;
  championResolved: boolean;
};

export type TournamentCompetitionOperationsSummary = {
  stage: TournamentCompetitionStage;
  progressPercent: number;
  alerts: string[];
};

export function buildTournamentCompetitionOperationsSummary(
  input: TournamentCompetitionOperationsInput,
): TournamentCompetitionOperationsSummary {
  const alerts: string[] = [];

  if (input.totalTeams === 0) {
    alerts.push("No tournament teams are available.");
  }

  if (input.scheduledGames === 0) {
    alerts.push("No tournament games are scheduled.");
  }

  if (
    input.seededTeams > 0 &&
    input.seededTeams < input.totalTeams
  ) {
    alerts.push("Bracket seeding is incomplete.");
  }

  if (
    input.totalBracketMatchups > 0 &&
    input.resolvedBracketMatchups <
      input.totalBracketMatchups &&
    input.finalizedGames > 0
  ) {
    alerts.push("Bracket progression is still active.");
  }

  let stage: TournamentCompetitionStage =
    "NOT_STARTED";

  if (input.championResolved) {
    stage = "COMPLETE";
  } else if (
    input.totalBracketMatchups > 0 &&
    input.resolvedBracketMatchups > 0
  ) {
    stage = "BRACKET_ACTIVE";
  } else if (
    input.seededTeams > 0 &&
    input.seededTeams === input.totalTeams
  ) {
    stage = "BRACKET_READY";
  } else if (input.finalizedGames > 0) {
    stage = "POOL_PLAY";
  }

  const gameProgress =
    input.scheduledGames > 0
      ? Math.min(
          1,
          input.finalizedGames / input.scheduledGames,
        )
      : 0;

  const bracketProgress =
    input.totalBracketMatchups > 0
      ? Math.min(
          1,
          input.resolvedBracketMatchups /
            input.totalBracketMatchups,
        )
      : 0;

  const progressPercent = input.championResolved
    ? 100
    : Math.round(
        Math.max(gameProgress, bracketProgress) * 100,
      );

  return {
    stage,
    progressPercent,
    alerts,
  };
}
