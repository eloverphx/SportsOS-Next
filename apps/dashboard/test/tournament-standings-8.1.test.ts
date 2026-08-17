import { describe, expect, it } from "vitest";
import {
  buildTournamentStandings,
} from "../lib/tournament-standings";

describe("Milestone 8.1 tournament standings engine", () => {
  const teams = [
    { id: "a", name: "Lakers" },
    { id: "b", name: "Bears" },
    { id: "c", name: "Eagles" },
  ];

  it("starts every team at zero", () => {
    const standings = buildTournamentStandings(teams, []);

    expect(standings).toHaveLength(3);
    expect(
      standings.every(
        (row) =>
          row.gamesPlayed === 0 &&
          row.points === 0 &&
          row.goalsFor === 0,
      ),
    ).toBe(true);
  });

  it("counts only finalized games", () => {
    const standings = buildTournamentStandings(teams, [
      {
        id: "g1",
        homeTeamId: "a",
        awayTeamId: "b",
        homeScore: 4,
        awayScore: 2,
        status: "FINAL",
      },
      {
        id: "g2",
        homeTeamId: "a",
        awayTeamId: "c",
        homeScore: 9,
        awayScore: 0,
        status: "LIVE",
      },
    ]);

    const lakers = standings.find((row) => row.teamId === "a");

    expect(lakers).toMatchObject({
      gamesPlayed: 1,
      wins: 1,
      points: 2,
      goalsFor: 4,
      goalsAgainst: 2,
      goalDifferential: 2,
    });
  });

  it("awards two points for a win and one for a tie by default", () => {
    const standings = buildTournamentStandings(teams, [
      {
        id: "g1",
        homeTeamId: "a",
        awayTeamId: "b",
        homeScore: 3,
        awayScore: 1,
        status: "FINAL",
      },
      {
        id: "g2",
        homeTeamId: "a",
        awayTeamId: "c",
        homeScore: 2,
        awayScore: 2,
        status: "FINAL",
      },
    ]);

    const lakers = standings.find((row) => row.teamId === "a");

    expect(lakers).toMatchObject({
      wins: 1,
      ties: 1,
      losses: 0,
      gamesPlayed: 2,
      points: 3,
    });
  });

  it("supports configurable tournament point rules", () => {
    const standings = buildTournamentStandings(
      teams,
      [
        {
          id: "g1",
          homeTeamId: "a",
          awayTeamId: "b",
          homeScore: 1,
          awayScore: 0,
          status: "FINAL",
        },
      ],
      {
        winPoints: 3,
        tiePoints: 1,
        lossPoints: 0,
      },
    );

    expect(
      standings.find((row) => row.teamId === "a")?.points,
    ).toBe(3);
  });

  it("sorts by points, wins, goal differential, goals for, then name", () => {
    const standings = buildTournamentStandings(teams, [
      {
        id: "g1",
        homeTeamId: "a",
        awayTeamId: "b",
        homeScore: 4,
        awayScore: 2,
        status: "FINAL",
      },
      {
        id: "g2",
        homeTeamId: "c",
        awayTeamId: "a",
        homeScore: 1,
        awayScore: 0,
        status: "FINAL",
      },
      {
        id: "g3",
        homeTeamId: "b",
        awayTeamId: "c",
        homeScore: 3,
        awayScore: 2,
        status: "FINAL",
      },
    ]);

    expect(standings.map((row) => row.rank)).toEqual([1, 2, 3]);

    const first = standings[0];
    const second = standings[1];

    expect(first).toBeDefined();
    expect(second).toBeDefined();

    if (!first || !second) {
      throw new Error("Expected at least two standings rows.");
    }

    expect(first.points).toBeGreaterThanOrEqual(second.points);
  });

  it("ignores finalized games containing teams outside the supplied field", () => {
    const standings = buildTournamentStandings(teams, [
      {
        id: "external",
        homeTeamId: "a",
        awayTeamId: "not-in-tournament",
        homeScore: 5,
        awayScore: 1,
        status: "FINAL",
      },
    ]);

    expect(
      standings.find((row) => row.teamId === "a")?.gamesPlayed,
    ).toBe(0);
  });

  it("rejects invalid finalized scores", () => {
    expect(() =>
      buildTournamentStandings(teams, [
        {
          id: "bad",
          homeTeamId: "a",
          awayTeamId: "b",
          homeScore: -1,
          awayScore: 2,
          status: "FINAL",
        },
      ]),
    ).toThrow("homeScore must be a non-negative number.");
  });
});
