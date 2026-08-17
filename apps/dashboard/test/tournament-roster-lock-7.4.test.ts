import { describe, expect, it } from "vitest";
import {
  EMPTY_ROSTER_LOCK_STATE,
  areBothRostersLocked,
  canLockRoster,
  readRosterLockState,
  setRosterLocked,
  writeRosterLockState,
} from "../lib/tournament-roster-lock";

describe("Milestone 7.4 roster locking", () => {
  it("defaults both rosters to unlocked", () => {
    expect(
      readRosterLockState(
        { getItem: () => null },
        "game-74",
      ),
    ).toEqual(EMPTY_ROSTER_LOCK_STATE);
  });

  it("locks one roster without mutating the other side", () => {
    expect(
      setRosterLocked(
        { home: false, away: true },
        "home",
        true,
      ),
    ).toEqual({
      home: true,
      away: true,
    });
  });

  it("requires both rosters for full roster readiness", () => {
    expect(
      areBothRostersLocked({
        home: true,
        away: false,
      }),
    ).toBe(false);

    expect(
      areBothRostersLocked({
        home: true,
        away: true,
      }),
    ).toBe(true);
  });

  it("requires check-in before normal locking", () => {
    expect(canLockRoster(false, false)).toBe(false);
    expect(canLockRoster(true, false)).toBe(true);
  });

  it("allows the existing testing override to bypass the check-in gate", () => {
    expect(canLockRoster(false, true)).toBe(true);
  });

  it("persists and restores per-game roster locks", () => {
    let value: string | null = null;

    const storage = {
      getItem: () => value,
      setItem: (_key: string, nextValue: string) => {
        value = nextValue;
      },
    };

    writeRosterLockState(storage, "game-74", {
      home: true,
      away: false,
    });

    expect(readRosterLockState(storage, "game-74")).toEqual({
      home: true,
      away: false,
    });
  });

  it("fails closed for malformed persisted data", () => {
    expect(
      readRosterLockState(
        { getItem: () => "{broken-json" },
        "game-74",
      ),
    ).toEqual({
      home: false,
      away: false,
    });
  });
});
