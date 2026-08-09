import { describe, expect, it } from "vitest";
import {
  detectServerScheduleConflicts,
  hasHardScheduleConflicts,
  type ProposedScheduleGame,
  type ServerScheduleGame,
} from "../src/modules/games/schedule-conflicts.js";

function scheduled(
  overrides: Partial<ServerScheduleGame> = {},
): ServerScheduleGame {
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

function proposed(
  overrides: Partial<ProposedScheduleGame> = {},
): ProposedScheduleGame {
  return {
    ...scheduled(),
    id: 99,
    homeTeamId: 30,
    awayTeamId: 40,
    homeTeamName: "Storm",
    awayTeamName: "Bears",
    ...overrides,
  };
}

describe("server-side tournament schedule enforcement", () => {
  it("identifies same-rink overlap as a hard conflict", () => {
    const conflicts = detectServerScheduleConflicts(
      proposed({
        scheduledStart: "2026-08-09T08:30:00-05:00",
        venue: "Rink 1",
      }),
      [scheduled()],
    );

    expect(conflicts).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          code: "RINK_OVERLAP",
          severity: "ERROR",
        }),
      ]),
    );
    expect(hasHardScheduleConflicts(conflicts)).toBe(true);
  });

  it("identifies same-team overlap as a hard conflict", () => {
    const conflicts = detectServerScheduleConflicts(
      proposed({
        homeTeamId: 10,
        homeTeamName: "Lakers",
        venue: "Rink 2",
        scheduledStart: "2026-08-09T08:30:00-05:00",
      }),
      [scheduled()],
    );

    expect(conflicts.some((conflict) => conflict.code === "TEAM_OVERLAP")).toBe(true);
    expect(hasHardScheduleConflicts(conflicts)).toBe(true);
  });

  it("keeps missing rink and short turnaround as warnings", () => {
    const missing = detectServerScheduleConflicts(
      proposed({ venue: null }),
      [],
    );

    expect(missing).toEqual([
      expect.objectContaining({
        code: "MISSING_RINK",
        severity: "WARNING",
      }),
    ]);
    expect(hasHardScheduleConflicts(missing)).toBe(false);

    const turnaround = detectServerScheduleConflicts(
      proposed({
        homeTeamId: 10,
        homeTeamName: "Lakers",
        venue: "Rink 2",
        scheduledStart: "2026-08-09T10:00:00-05:00",
      }),
      [scheduled()],
    );

    expect(turnaround.some((conflict) => conflict.code === "TEAM_TURNAROUND")).toBe(
      true,
    );
    expect(hasHardScheduleConflicts(turnaround)).toBe(false);
  });
});
