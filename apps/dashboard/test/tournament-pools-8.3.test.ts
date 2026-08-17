import { describe, expect, it } from "vitest";
import {
  buildTournamentPoolStandings,
  deriveDefaultPools,
} from "../lib/tournament-pools";

describe("Milestone 8.3 tournament pools / divisions", () => {
  const teams = [
    { id: "a", name: "Lakers" },
    { id: "b", name: "Bears" },
    { id: "c", name: "Eagles" },
    { id: "d", name: "Wolves" },
  ];

  it("derives a default all-teams pool", () => {
    expect(deriveDefaultPools(teams)).toEqual([
      {
        id: "all",
        name: "All Teams",
        teamIds: ["a", "b", "c", "d"],
      },
    ]);
  });

  it("builds standings independently per pool", () => {
    const pools = [
      {
        id: "pool-a",
        name: "Pool A",
        teamIds: ["a", "b"],
      },
      {
        id: "pool-b",
        name: "Pool B",
        teamIds: ["c", "d"],
      },
    ];

    const games = [
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
        homeTeamId: "c",
        awayTeamId: "d",
        homeScore: 2,
        awayScore: 4,
        status: "FINAL",
      },
      {
        id: "cross",
        homeTeamId: "a",
        awayTeamId: "c",
        homeScore: 9,
        awayScore: 0,
        status: "FINAL",
      },
    ];

    const result = buildTournamentPoolStandings(
      pools,
      teams,
      games,
    );

    expect(result).toHaveLength(2);
    expect(result[0]?.standings[0]?.teamId).toBe("a");
    expect(result[1]?.standings[0]?.teamId).toBe("d");

    expect(
      result[0]?.standings.find(
        (row) => row.teamId === "a",
      )?.gamesPlayed,
    ).toBe(1);
  });

  it("ignores unknown team ids inside a pool", () => {
    const result = buildTournamentPoolStandings(
      [
        {
          id: "pool-a",
          name: "Pool A",
          teamIds: ["a", "missing"],
        },
      ],
      teams,
      [],
    );

    expect(result[0]?.standings).toHaveLength(1);
    expect(result[0]?.standings[0]?.teamId).toBe("a");
  });
});
