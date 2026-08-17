import { describe, expect, it } from "vitest";
import {
  buildPregameReadinessChecks,
  buildPregameReadinessSummary,
  summarizePregameReadiness,
  type PregameReadinessCheck,
} from "../lib/tournament-pregame-readiness";
import type { TournamentGameOperationsGame } from "../lib/tournament-game-operations";

function game(
  overrides: Partial<TournamentGameOperationsGame["readiness"]> = {},
): TournamentGameOperationsGame {
  return {
    id: "game-72",
    homeTeamName: "Lakers",
    awayTeamName: "Bears",
    venueName: "Arena",
    rinkName: "Rink A",
    scheduledStart: "2026-08-16T20:00:00Z",
    status: "SCHEDULED",
    scoringStatus: "NOT_STARTED",
    readiness: {
      teamsAssigned: true,
      rinkAssigned: true,
      scheduledStartAssigned: true,
      ...overrides,
    },
  };
}

describe("Milestone 7.2 pregame readiness", () => {
  it("derives authoritative checks from current game state", () => {
    const checks = buildPregameReadinessChecks(game());

    expect(checks.find((check) => check.id === "teams")?.state).toBe("PASS");
    expect(checks.find((check) => check.id === "rink")?.state).toBe("PASS");
    expect(
      checks.find((check) => check.id === "scheduledStart")?.state,
    ).toBe("PASS");
  });

  it("blocks on missing required current game data", () => {
    const summary = buildPregameReadinessSummary(
      game({
        teamsAssigned: false,
        rinkAssigned: false,
      }),
      false,
    );

    expect(summary.actualReady).toBe(false);
    expect(summary.actualBlockingCount).toBe(2);
    expect(summary.effectiveReady).toBe(false);
  });

  it("keeps future integrations visible without pretending they are ready", () => {
    const summary = buildPregameReadinessSummary(game(), false);

    expect(summary.unknownCount).toBe(4);
    expect(
      summary.checks.filter((check) => check.source === "future-integration"),
    ).toHaveLength(4);
    expect(summary.actualReady).toBe(true);
  });

  it("testing override changes only effective readiness", () => {
    const summary = buildPregameReadinessSummary(
      game({ rinkAssigned: false }),
      true,
    );

    expect(summary.actualReady).toBe(false);
    expect(summary.effectiveReady).toBe(true);
    expect(summary.testingOverrideApplied).toBe(true);
    expect(
      summary.checks.find((check) => check.id === "rink")?.state,
    ).toBe("BLOCKED");
  });

  it("required UNKNOWN integrations do not block before integration exists", () => {
    const checks: PregameReadinessCheck[] = [
      {
        id: "scoringOperator",
        label: "Scoring operator",
        state: "UNKNOWN",
        severity: "required",
        detail: "Not integrated yet.",
        source: "future-integration",
      },
    ];

    const summary = summarizePregameReadiness(checks, false);

    expect(summary.actualBlockingCount).toBe(0);
    expect(summary.unknownCount).toBe(1);
    expect(summary.actualReady).toBe(true);
  });
});


describe("Milestone 7.4 readiness integration", () => {
  it("accepts roster-lock operational readiness", () => {
    const summary = buildPregameReadinessSummary(
      game(),
      false,
      {
        teamCheckInReady: true,
        rosterLockReady: true,
      },
    );

    expect(
      summary.checks.find((check) => check.id === "teamCheckIn")?.state,
    ).toBe("PASS");

    expect(
      summary.checks.find((check) => check.id === "rosterLock")?.state,
    ).toBe("PASS");
  });
});


describe("Milestone 7.5 readiness integration", () => {
  it("accepts officials operational readiness", () => {
    const summary = buildPregameReadinessSummary(
      game(),
      false,
      {
        teamCheckInReady: true,
        rosterLockReady: true,
        officialsReady: true,
      },
    );

    expect(
      summary.checks.find((check) => check.id === "officials")?.state,
    ).toBe("PASS");
  });
});
