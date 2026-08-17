import { describe, expect, it } from "vitest";
import {
  EMPTY_TEAM_CHECK_IN,
  areBothTeamsCheckedIn,
  readTeamCheckIn,
  setTeamCheckedIn,
  writeTeamCheckIn,
} from "../lib/tournament-team-check-in";

describe("Milestone 7.3 team check-in", () => {
  it("defaults both teams to not checked in", () => {
    const storage = { getItem: () => null };

    expect(readTeamCheckIn(storage, "game-73")).toEqual(
      EMPTY_TEAM_CHECK_IN,
    );
  });

  it("updates one side without mutating the other", () => {
    expect(
      setTeamCheckedIn(
        { home: false, away: true },
        "home",
        true,
      ),
    ).toEqual({
      home: true,
      away: true,
    });
  });

  it("requires both teams for full check-in", () => {
    expect(
      areBothTeamsCheckedIn({
        home: true,
        away: false,
      }),
    ).toBe(false);

    expect(
      areBothTeamsCheckedIn({
        home: true,
        away: true,
      }),
    ).toBe(true);
  });

  it("persists and restores state", () => {
    let value: string | null = null;

    const storage = {
      getItem: () => value,
      setItem: (_key: string, nextValue: string) => {
        value = nextValue;
      },
    };

    writeTeamCheckIn(storage, "game-73", {
      home: true,
      away: false,
    });

    expect(readTeamCheckIn(storage, "game-73")).toEqual({
      home: true,
      away: false,
    });
  });

  it("fails closed for malformed persisted data", () => {
    expect(
      readTeamCheckIn(
        { getItem: () => "{broken-json" },
        "game-73",
      ),
    ).toEqual({
      home: false,
      away: false,
    });
  });
});
