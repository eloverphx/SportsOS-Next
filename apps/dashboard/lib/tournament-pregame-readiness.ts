import type { TournamentGameOperationsGame } from "./tournament-game-operations";

export type PregameReadinessState =
  | "PASS"
  | "WARNING"
  | "BLOCKED"
  | "UNKNOWN";

export type PregameReadinessSeverity = "required" | "recommended";

export type PregameReadinessCheck = {
  id:
    | "teams"
    | "rink"
    | "scheduledStart"
    | "teamCheckIn"
    | "rosterLock"
    | "officials"
    | "rosters"
    | "scoreboard"
    | "scoringOperator"
    | "stream";
  label: string;
  state: PregameReadinessState;
  severity: PregameReadinessSeverity;
  detail: string;
  source: "game" | "future-integration";
};

export type PregameReadinessSummary = {
  checks: PregameReadinessCheck[];
  actualReady: boolean;
  actualBlockingCount: number;
  warningCount: number;
  unknownCount: number;
  effectiveReady: boolean;
  testingOverrideApplied: boolean;
};

function derivedCheck(
  id: PregameReadinessCheck["id"],
  label: string,
  value: boolean,
  detailWhenReady: string,
  detailWhenBlocked: string,
): PregameReadinessCheck {
  return {
    id,
    label,
    state: value ? "PASS" : "BLOCKED",
    severity: "required",
    detail: value ? detailWhenReady : detailWhenBlocked,
    source: "game",
  };
}

function futureCheck(
  id: PregameReadinessCheck["id"],
  label: string,
  severity: PregameReadinessSeverity,
  detail: string,
): PregameReadinessCheck {
  return {
    id,
    label,
    state: "UNKNOWN",
    severity,
    detail,
    source: "future-integration",
  };
}

export function buildPregameReadinessChecks(
  game: TournamentGameOperationsGame,
  operationalState: {
    teamCheckInReady?: boolean;
    rosterLockReady?: boolean;
  
    officialsReady?: boolean;} = {},
): PregameReadinessCheck[] {
  return [
    derivedCheck(
      "teams",
      "Teams assigned",
      game.readiness.teamsAssigned,
      "Home and away teams are assigned.",
      "Both home and away teams must be assigned.",
    ),
    derivedCheck(
      "rink",
      "Rink assigned",
      game.readiness.rinkAssigned,
      "A rink is assigned.",
      "A rink must be assigned before normal game start.",
    ),
    derivedCheck(
      "scheduledStart",
      "Scheduled start",
      game.readiness.scheduledStartAssigned,
      "Scheduled start time is present.",
      "Scheduled start time is missing.",
    ),
    derivedCheck(
      "teamCheckIn",
      "Team check-in",
      operationalState.teamCheckInReady === true,
      "Both teams are checked in.",
      "Home and away teams must both be checked in before normal game start.",
    ),
    derivedCheck(
      "rosterLock",
      "Roster lock",
      operationalState.rosterLockReady === true,
      "Both team rosters are locked for game operations.",
      "Home and away rosters must both be locked before normal game start.",
    ),
    derivedCheck(
      "officials",
      "Officials assigned",
      operationalState.officialsReady === true,
      "Required officials are assigned.",
      "Two referees must be assigned before normal game start.",
    ),
    futureCheck(
      "rosters",
      "Rosters available",
      "required",
      "Roster availability will be connected to the roster-lock workflow in Milestone 7.4.",
    ),
    futureCheck(
      "scoreboard",
      "Scoreboard connection",
      "recommended",
      "Scoreboard readiness will use device connectivity when the operations bridge is connected.",
    ),
    futureCheck(
      "scoringOperator",
      "Scoring operator",
      "required",
      "Scoring-operator assignment is not yet part of the current game record.",
    ),
    futureCheck(
      "stream",
      "Stream availability",
      "recommended",
      "Stream readiness will be connected during broadcast integration.",
    ),
  ];
}

export function summarizePregameReadiness(
  checks: PregameReadinessCheck[],
  testingOverrideEnabled: boolean,
): PregameReadinessSummary {
  const actualBlockingCount = checks.filter(
    (check) => check.severity === "required" && check.state === "BLOCKED",
  ).length;

  const warningCount = checks.filter(
    (check) => check.state === "WARNING",
  ).length;

  const unknownCount = checks.filter(
    (check) => check.state === "UNKNOWN",
  ).length;

  /*
   * UNKNOWN checks are visible but do not block until their backing
   * integration exists. This prevents 7.2 from inventing readiness facts
   * that are not yet represented by authoritative server state.
   */
  const actualReady = actualBlockingCount === 0;

  return {
    checks,
    actualReady,
    actualBlockingCount,
    warningCount,
    unknownCount,
    effectiveReady: actualReady || testingOverrideEnabled,
    testingOverrideApplied: testingOverrideEnabled && !actualReady,
  };
}

export function buildPregameReadinessSummary(
  game: TournamentGameOperationsGame,
  testingOverrideEnabled: boolean,
  operationalState: {
    teamCheckInReady?: boolean;
  
    rosterLockReady?: boolean;
    officialsReady?: boolean;} = {},
): PregameReadinessSummary {
  return summarizePregameReadiness(
    buildPregameReadinessChecks(game, operationalState),
    testingOverrideEnabled,
  );
}
