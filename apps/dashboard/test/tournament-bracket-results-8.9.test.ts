import { describe, expect, it } from "vitest";
import {
  deriveBracketResultsFromGames,
} from "../lib/tournament-bracket-results";
import type {
  BracketMatchup,
} from "../lib/tournament-bracket-seeding";

const matchup: BracketMatchup = {
  id: "round-1-slot-1",
  round: 1,
  slot: 1,
  homeSeed: {
    seed: 1,
    teamId: "a",
    teamName: "Lakers",
  },
  awaySeed: {
    seed: 4,
    teamId: "d",
    teamName: "Wolves",
  },
  bye: false,
};

describe("Milestone 8.9 bracket result integration / persistence", () => {
  it("derives bracket results from finalized authoritative games", () => {
    const results = deriveBracketResultsFromGames(
      [matchup],
      [
        {
          id: "game-1",
          homeTeamId: "a",
          awayTeamId: "d",
          homeScore: 5,
          awayScore: 2,
          status: "FINAL",
        },
      ],
    );

    expect(results).toEqual([
      {
        matchupId: "round-1-slot-1",
        homeScore: 5,
        awayScore: 2,
        status: "FINAL",
      },
    ]);
  });

  it("normalizes score orientation when API home/away is reversed", () => {
    const results = deriveBracketResultsFromGames(
      [matchup],
      [
        {
          id: "game-2",
          homeTeamId: "d",
          awayTeamId: "a",
          homeScore: 1,
          awayScore: 4,
          status: "FINAL",
        },
      ],
    );

    expect(results[0]).toMatchObject({
      homeScore: 4,
      awayScore: 1,
    });
  });

  it("ignores unfinished games", () => {
    expect(
      deriveBracketResultsFromGames(
        [matchup],
        [
          {
            id: "game-live",
            homeTeamId: "a",
            awayTeamId: "d",
            homeScore: 3,
            awayScore: 2,
            status: "LIVE",
          },
        ],
      ),
    ).toEqual([]);
  });

  it("ignores unrelated games", () => {
    expect(
      deriveBracketResultsFromGames(
        [matchup],
        [
          {
            id: "other",
            homeTeamId: "a",
            awayTeamId: "b",
            homeScore: 3,
            awayScore: 0,
            status: "FINAL",
          },
        ],
      ),
    ).toEqual([]);
  });

  it("does not create a result for a bye", () => {
    expect(
      deriveBracketResultsFromGames(
        [
          {
            ...matchup,
            awaySeed: null,
            bye: true,
          },
        ],
        [],
      ),
    ).toEqual([]);
  });

  it("rejects ambiguous duplicate finalized games", () => {
    expect(() =>
      deriveBracketResultsFromGames(
        [matchup],
        [
          {
            id: "game-1",
            homeTeamId: "a",
            awayTeamId: "d",
            homeScore: 2,
            awayScore: 1,
            status: "FINAL",
          },
          {
            id: "game-2",
            homeTeamId: "a",
            awayTeamId: "d",
            homeScore: 4,
            awayScore: 3,
            status: "FINAL",
          },
        ],
      ),
    ).toThrow(
      "Multiple finalized games match bracket matchup",
    );
  });
});
