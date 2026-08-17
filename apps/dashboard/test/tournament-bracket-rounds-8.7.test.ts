import { describe, expect, it } from "vitest";
import {
  seedBracket,
} from "../lib/tournament-bracket-seeding";
import {
  buildTournamentBracketTree,
} from "../lib/tournament-bracket-rounds";

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

describe("Milestone 8.7 multi-round bracket construction", () => {
  it("builds all rounds for a four-team bracket", () => {
    const seeded = seedBracket([
      row(1, "a", "A"),
      row(2, "b", "B"),
      row(3, "c", "C"),
      row(4, "d", "D"),
    ]);

    const tree = buildTournamentBracketTree(
      seeded,
      [],
    );

    expect(tree.rounds).toHaveLength(2);
    expect(tree.rounds[0]?.name).toBe("Semifinals");
    expect(tree.rounds[1]?.name).toBe("Championship");
  });

  it("propagates finalized winners into the championship", () => {
    const seeded = seedBracket([
      row(1, "a", "A"),
      row(2, "b", "B"),
      row(3, "c", "C"),
      row(4, "d", "D"),
    ]);

    const firstRound = seeded.firstRound;

    const tree = buildTournamentBracketTree(
      seeded,
      [
        {
          matchupId: firstRound[0]?.id ?? "",
          homeScore: 5,
          awayScore: 1,
          status: "FINAL",
        },
        {
          matchupId: firstRound[1]?.id ?? "",
          homeScore: 2,
          awayScore: 3,
          status: "FINAL",
        },
      ],
    );

    expect(
      tree.rounds[1]?.matchups[0]?.homeSeed?.teamId,
    ).toBe("a");

    expect(
      tree.rounds[1]?.matchups[0]?.awaySeed?.teamId,
    ).toBe("c");
  });

  it("keeps unresolved next-round slots as TBD", () => {
    const seeded = seedBracket([
      row(1, "a", "A"),
      row(2, "b", "B"),
      row(3, "c", "C"),
      row(4, "d", "D"),
    ]);

    const tree = buildTournamentBracketTree(
      seeded,
      [],
    );

    expect(
      tree.rounds[1]?.matchups[0]?.homeSeed,
    ).toBeNull();

    expect(
      tree.rounds[1]?.matchups[0]?.awaySeed,
    ).toBeNull();
  });

  it("propagates byes through the next round", () => {
    const seeded = seedBracket([
      row(1, "a", "A"),
      row(2, "b", "B"),
      row(3, "c", "C"),
    ]);

    const tree = buildTournamentBracketTree(
      seeded,
      [],
    );

    expect(
      tree.rounds[1]?.matchups[0]?.homeSeed?.teamId,
    ).toBe("a");
  });

  it("resolves a champion once the final is complete", () => {
    const seeded = seedBracket([
      row(1, "a", "A"),
      row(2, "b", "B"),
    ]);

    const final = seeded.firstRound[0];

    if (!final) {
      throw new Error("Expected championship matchup.");
    }

    const tree = buildTournamentBracketTree(
      seeded,
      [
        {
          matchupId: final.id,
          homeScore: 4,
          awayScore: 2,
          status: "FINAL",
        },
      ],
    );

    expect(tree.rounds).toHaveLength(1);
    expect(tree.rounds[0]?.name).toBe("Championship");
    expect(tree.champion?.teamId).toBe("a");
  });

  it("returns an empty tree for an empty field", () => {
    const tree = buildTournamentBracketTree(
      seedBracket([]),
      [],
    );

    expect(tree).toEqual({
      fieldSize: 0,
      bracketSize: 0,
      rounds: [],
      champion: null,
    });
  });
});
