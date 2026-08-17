import { describe, expect, it } from "vitest";
import {
  seedBracket,
} from "../lib/tournament-bracket-seeding";

function row(
  rank: number,
  teamId: string,
  teamName: string,
) {
  return {
    teamId,
    teamName,
    gamesPlayed: 3,
    wins: 2,
    losses: 1,
    ties: 0,
    goalsFor: 10,
    goalsAgainst: 5,
    goalDifferential: 5,
    points: 4,
    rank,
  };
}

describe("Milestone 8.4 bracket seeding engine", () => {
  it("returns an empty bracket for no teams", () => {
    expect(seedBracket([])).toEqual({
      fieldSize: 0,
      bracketSize: 0,
      seeds: [],
      firstRound: [],
    });
  });

  it("assigns seeds by standings rank", () => {
    const result = seedBracket([
      row(2, "b", "Bears"),
      row(1, "a", "Lakers"),
      row(3, "c", "Eagles"),
    ]);

    expect(result.seeds.map((seed) => seed.teamId)).toEqual([
      "a",
      "b",
      "c",
    ]);

    expect(result.seeds.map((seed) => seed.seed)).toEqual([
      1,
      2,
      3,
    ]);
  });

  it("expands the field to the next power-of-two bracket", () => {
    const result = seedBracket([
      row(1, "a", "A"),
      row(2, "b", "B"),
      row(3, "c", "C"),
      row(4, "d", "D"),
      row(5, "e", "E"),
      row(6, "f", "F"),
    ]);

    expect(result.fieldSize).toBe(6);
    expect(result.bracketSize).toBe(8);
  });

  it("pairs highest against lowest available seed", () => {
    const result = seedBracket([
      row(1, "a", "A"),
      row(2, "b", "B"),
      row(3, "c", "C"),
      row(4, "d", "D"),
    ]);

    expect(result.firstRound[0]).toMatchObject({
      homeSeed: {
        seed: 1,
        teamId: "a",
      },
      awaySeed: {
        seed: 4,
        teamId: "d",
      },
      bye: false,
    });

    expect(result.firstRound[1]).toMatchObject({
      homeSeed: {
        seed: 2,
        teamId: "b",
      },
      awaySeed: {
        seed: 3,
        teamId: "c",
      },
      bye: false,
    });
  });

  it("marks unmatched high seeds as first-round byes", () => {
    const result = seedBracket([
      row(1, "a", "A"),
      row(2, "b", "B"),
      row(3, "c", "C"),
    ]);

    expect(result.bracketSize).toBe(4);

    expect(result.firstRound[0]).toMatchObject({
      homeSeed: {
        seed: 1,
        teamId: "a",
      },
      awaySeed: null,
      bye: true,
    });

    expect(result.firstRound[1]).toMatchObject({
      homeSeed: {
        seed: 2,
        teamId: "b",
      },
      awaySeed: {
        seed: 3,
        teamId: "c",
      },
      bye: false,
    });
  });

  it("rejects duplicate teams", () => {
    expect(() =>
      seedBracket([
        row(1, "a", "A"),
        row(2, "a", "A duplicate"),
      ]),
    ).toThrow("Duplicate team in standings");
  });
});
