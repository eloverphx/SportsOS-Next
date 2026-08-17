import { describe, expect, it } from "vitest";
import {
  advanceBracketRound,
} from "../lib/tournament-bracket-advancement";
import type {
  BracketMatchup,
  BracketSeed,
} from "../lib/tournament-bracket-seeding";

function seed(
  seedNumber: number,
  teamId: string,
  teamName: string,
): BracketSeed {
  return {
    seed: seedNumber,
    teamId,
    teamName,
  };
}

function matchup(
  id: string,
  slot: number,
  homeSeed: BracketSeed | null,
  awaySeed: BracketSeed | null,
  bye = false,
): BracketMatchup {
  return {
    id,
    round: 1,
    slot,
    homeSeed,
    awaySeed,
    bye,
  };
}

describe("Milestone 8.6 bracket advancement / winner propagation", () => {
  it("advances a finalized home winner", () => {
    const round = [
      matchup(
        "m1",
        1,
        seed(1, "a", "A"),
        seed(4, "d", "D"),
      ),
      matchup(
        "m2",
        2,
        seed(2, "b", "B"),
        seed(3, "c", "C"),
      ),
    ];

    const result = advanceBracketRound(round, [
      {
        matchupId: "m1",
        homeScore: 5,
        awayScore: 2,
        status: "FINAL",
      },
      {
        matchupId: "m2",
        homeScore: 1,
        awayScore: 4,
        status: "FINAL",
      },
    ]);

    expect(result.resolvedRound[0]?.winner?.teamId).toBe("a");
    expect(result.resolvedRound[1]?.winner?.teamId).toBe("c");

    expect(result.nextRound[0]).toMatchObject({
      round: 2,
      slot: 1,
      homeSeed: {
        teamId: "a",
      },
      awaySeed: {
        teamId: "c",
      },
    });
  });

  it("automatically advances a bye", () => {
    const round = [
      matchup(
        "m1",
        1,
        seed(1, "a", "A"),
        null,
        true,
      ),
      matchup(
        "m2",
        2,
        seed(2, "b", "B"),
        seed(3, "c", "C"),
      ),
    ];

    const result = advanceBracketRound(round, [
      {
        matchupId: "m2",
        homeScore: 2,
        awayScore: 1,
        status: "FINAL",
      },
    ]);

    expect(result.resolvedRound[0]?.winner?.teamId).toBe("a");

    expect(result.nextRound[0]).toMatchObject({
      homeSeed: {
        teamId: "a",
      },
      awaySeed: {
        teamId: "b",
      },
    });
  });

  it("does not advance an unfinished matchup", () => {
    const round = [
      matchup(
        "m1",
        1,
        seed(1, "a", "A"),
        seed(4, "d", "D"),
      ),
      matchup(
        "m2",
        2,
        seed(2, "b", "B"),
        seed(3, "c", "C"),
      ),
    ];

    const result = advanceBracketRound(round, [
      {
        matchupId: "m1",
        homeScore: 3,
        awayScore: 2,
        status: "LIVE",
      },
    ]);

    expect(result.resolvedRound[0]?.winner).toBeNull();
    expect(result.nextRound[0]?.homeSeed).toBeNull();
  });

  it("does not choose a winner for a tied final", () => {
    const round = [
      matchup(
        "m1",
        1,
        seed(1, "a", "A"),
        seed(4, "d", "D"),
      ),
    ];

    const result = advanceBracketRound(round, [
      {
        matchupId: "m1",
        homeScore: 2,
        awayScore: 2,
        status: "FINAL",
      },
    ]);

    expect(result.resolvedRound[0]?.winner).toBeNull();
  });

  it("rejects invalid finalized scores", () => {
    expect(() =>
      advanceBracketRound(
        [
          matchup(
            "m1",
            1,
            seed(1, "a", "A"),
            seed(4, "d", "D"),
          ),
        ],
        [
          {
            matchupId: "m1",
            homeScore: Number.NaN,
            awayScore: 2,
            status: "FINAL",
          },
        ],
      ),
    ).toThrow("Invalid score for matchup m1.");
  });

  it("returns no next round when resolving a championship matchup", () => {
    const result = advanceBracketRound(
      [
        matchup(
          "championship",
          1,
          seed(1, "a", "A"),
          seed(2, "b", "B"),
        ),
      ],
      [
        {
          matchupId: "championship",
          homeScore: 4,
          awayScore: 3,
          status: "FINAL",
        },
      ],
    );

    expect(result.nextRound).toEqual([]);
    expect(result.resolvedRound[0]?.winner?.teamId).toBe("a");
  });
});
