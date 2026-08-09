import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  DEFAULT_SCHEDULE_RULES,
  detectScheduleConflicts,
  type ScheduleGame,
} from "../../dashboard/lib/tournament-schedule";

function game(overrides: Partial<ScheduleGame> = {}): ScheduleGame {
  return {
    id: 1,
    homeTeamId: 10,
    awayTeamId: 20,
    homeTeamName: "Lakers",
    awayTeamName: "Hornets",
    scheduledStart: "2026-08-09T08:00:00-05:00",
    venue: "Rink 1",
    status: "SCHEDULED",
    regulationPeriods: 3,
    regulationPeriodLengthMs: 20 * 60_000,
    intermissionLengthMs: 10 * 60_000,
    overtimeEnabled: false,
    overtimeLengthMs: 0,
    ...overrides,
  };
}

describe("Tournament schedule conflict engine", () => {
  it("flags overlapping games on the same rink", () => {
    const conflicts = detectScheduleConflicts([
      game(),
      game({
        id: 2,
        homeTeamId: 30,
        awayTeamId: 40,
        homeTeamName: "Storm",
        awayTeamName: "Bears",
        scheduledStart: "2026-08-09T08:45:00-05:00",
      }),
    ]);

    expect(conflicts.some((conflict) => conflict.code === "RINK_OVERLAP")).toBe(true);
  });

  it("flags a team scheduled in overlapping games", () => {
    const conflicts = detectScheduleConflicts([
      game(),
      game({
        id: 2,
        homeTeamId: 10,
        awayTeamId: 40,
        homeTeamName: "Lakers",
        awayTeamName: "Bears",
        venue: "Rink 2",
        scheduledStart: "2026-08-09T08:30:00-05:00",
      }),
    ]);

    expect(conflicts.some((conflict) => conflict.code === "TEAM_OVERLAP")).toBe(true);
  });

  it("flags insufficient turnaround without treating it as overlap", () => {
    const conflicts = detectScheduleConflicts([
      game({
        regulationPeriods: undefined,
        regulationPeriodLengthMs: undefined,
        intermissionLengthMs: undefined,
      }),
      game({
        id: 2,
        homeTeamId: 10,
        awayTeamId: 40,
        homeTeamName: "Lakers",
        awayTeamName: "Bears",
        venue: "Rink 2",
        scheduledStart: "2026-08-09T10:00:00-05:00",
        regulationPeriods: undefined,
        regulationPeriodLengthMs: undefined,
        intermissionLengthMs: undefined,
      }),
    ]);

    expect(DEFAULT_SCHEDULE_RULES.fallbackGameDurationMs).toBe(90 * 60_000);
    expect(conflicts.some((conflict) => conflict.code === "TEAM_OVERLAP")).toBe(false);
    expect(conflicts.some((conflict) => conflict.code === "TEAM_TURNAROUND")).toBe(true);
  });

  it("flags games missing a rink assignment", () => {
    const conflicts = detectScheduleConflicts([game({ venue: null })]);

    expect(conflicts).toMatchObject([
      {
        code: "MISSING_RINK",
        severity: "WARNING",
        gameId: 1,
      },
    ]);
  });
});

describe("Tournament Director 6.3 UI contract", () => {
  const page = readFileSync(
    new URL("../../dashboard/app/tournament-director/page.tsx", import.meta.url),
    "utf8",
  );

  it("mounts schedule conflict validation in Tournament Director", () => {
    expect(page).toContain("TournamentScheduleConflicts");
    expect(page).toContain("<TournamentScheduleConflicts games={games} />");
  });
});
