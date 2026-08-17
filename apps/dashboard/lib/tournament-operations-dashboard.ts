export type TournamentOperationsStage =
  | "PREGAME"
  | "AUTHORIZED"
  | "LIVE"
  | "FINAL";

export type TournamentOperationsSummaryInput = {
  actualReady: boolean;
  effectiveReady: boolean;
  homeCheckedIn: boolean;
  awayCheckedIn: boolean;
  homeRosterLocked: boolean;
  awayRosterLocked: boolean;
  officialsReady: boolean;
  startAuthorized: boolean;
  liveStarted: boolean;
  finalized: boolean;
};

export type TournamentOperationsSummary = {
  stage: TournamentOperationsStage;
  completedSteps: number;
  totalSteps: number;
  completionPercent: number;
  blockers: string[];
};

export function buildTournamentOperationsSummary(
  input: TournamentOperationsSummaryInput,
): TournamentOperationsSummary {
  const steps = [
    input.homeCheckedIn,
    input.awayCheckedIn,
    input.homeRosterLocked,
    input.awayRosterLocked,
    input.officialsReady,
    input.startAuthorized,
    input.liveStarted,
    input.finalized,
  ];

  const completedSteps = steps.filter(Boolean).length;
  const totalSteps = steps.length;
  const completionPercent = Math.round(
    (completedSteps / totalSteps) * 100,
  );

  const blockers: string[] = [];

  if (!input.homeCheckedIn) blockers.push("Home team not checked in");
  if (!input.awayCheckedIn) blockers.push("Away team not checked in");
  if (!input.homeRosterLocked) blockers.push("Home roster not locked");
  if (!input.awayRosterLocked) blockers.push("Away roster not locked");
  if (!input.officialsReady) blockers.push("Required officials not assigned");

  if (!input.effectiveReady) {
    blockers.push("Pregame readiness is blocked");
  }

  if (input.finalized) {
    return {
      stage: "FINAL",
      completedSteps,
      totalSteps,
      completionPercent,
      blockers: [],
    };
  }

  if (input.liveStarted) {
    return {
      stage: "LIVE",
      completedSteps,
      totalSteps,
      completionPercent,
      blockers: [],
    };
  }

  if (input.startAuthorized) {
    return {
      stage: "AUTHORIZED",
      completedSteps,
      totalSteps,
      completionPercent,
      blockers,
    };
  }

  return {
    stage: "PREGAME",
    completedSteps,
    totalSteps,
    completionPercent,
    blockers,
  };
}
