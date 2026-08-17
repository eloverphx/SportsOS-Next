import { describe, expect, it } from "vitest";
import {
  EMPTY_OFFICIALS_ASSIGNMENT,
  hasCompleteOfficialsCrew,
  hasRequiredOfficials,
  normalizeOfficialName,
  readOfficialsAssignment,
  writeOfficialsAssignment,
} from "../lib/tournament-officials-assignment";

describe("Milestone 7.5 officials assignment", () => {
  it("normalizes official names", () => {
    expect(normalizeOfficialName("  Alex   Smith  ")).toBe("Alex Smith");
  });

  it("defaults to an empty assignment", () => {
    expect(
      readOfficialsAssignment(
        { getItem: () => null },
        "game-75",
      ),
    ).toEqual(EMPTY_OFFICIALS_ASSIGNMENT);
  });

  it("requires two referees for required readiness", () => {
    expect(
      hasRequiredOfficials({
        referee1: "Ref One",
        referee2: "",
        linesman1: "",
        linesman2: "",
      }),
    ).toBe(false);

    expect(
      hasRequiredOfficials({
        referee1: "Ref One",
        referee2: "Ref Two",
        linesman1: "",
        linesman2: "",
      }),
    ).toBe(true);
  });

  it("distinguishes required officials from a complete crew", () => {
    const assignment = {
      referee1: "Ref One",
      referee2: "Ref Two",
      linesman1: "",
      linesman2: "",
    };

    expect(hasRequiredOfficials(assignment)).toBe(true);
    expect(hasCompleteOfficialsCrew(assignment)).toBe(false);
  });

  it("persists and restores assignments", () => {
    let value: string | null = null;

    const storage = {
      getItem: () => value,
      setItem: (_key: string, nextValue: string) => {
        value = nextValue;
      },
    };

    writeOfficialsAssignment(storage, "game-75", {
      referee1: " Ref One ",
      referee2: "Ref   Two",
      linesman1: "Line One",
      linesman2: "Line Two",
    });

    expect(readOfficialsAssignment(storage, "game-75")).toEqual({
      referee1: "Ref One",
      referee2: "Ref Two",
      linesman1: "Line One",
      linesman2: "Line Two",
    });
  });

  it("fails closed for malformed persisted data", () => {
    expect(
      readOfficialsAssignment(
        { getItem: () => "{bad-json" },
        "game-75",
      ),
    ).toEqual({
      referee1: "",
      referee2: "",
      linesman1: "",
      linesman2: "",
    });
  });
});
