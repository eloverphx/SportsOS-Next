import { describe, expect, it } from "vitest";
import {
  GameLifecycleError,
  resolveLifecycleAction,
} from "../src/modules/games/lifecycle.js";

function game(
  overrides: Partial<{
    status: "SCHEDULED" | "LIVE" | "FINAL" | "POSTPONED" | "CANCELED";
    gamePhase: "PREGAME" | "REGULATION" | "INTERMISSION" | "OVERTIME" | "FINAL";
    period: number;
    regulationPeriods: number;
    clockRemainingMs: number;
  }> = {},
) {
  return {
    status: "LIVE" as const,
    gamePhase: "REGULATION" as const,
    period: 1,
    regulationPeriods: 3,
    clockRemainingMs: 0,
    ...overrides,
  };
}

describe("game lifecycle command resolution", () => {
  it("starts a pregame through the authoritative clock action", () => {
    expect(
      resolveLifecycleAction(
        game({
          status: "SCHEDULED",
          gamePhase: "PREGAME",
          clockRemainingMs: 900_000,
        }),
        "startGame",
      ),
    ).toEqual({ action: "startClock" });
  });

  it("ends an early regulation period by beginning intermission", () => {
    expect(resolveLifecycleAction(game({ period: 1 }), "endPeriod")).toEqual({
      action: "startIntermission",
    });
  });

  it("leaves final regulation at zero for explicit overtime or final", () => {
    expect(
      resolveLifecycleAction(
        game({ period: 3, regulationPeriods: 3 }),
        "endPeriod",
      ),
    ).toEqual({ action: "pauseClock" });
  });

  it("rejects ending a period while time remains", () => {
    expect(() =>
      resolveLifecycleAction(game({ clockRemainingMs: 15_000 }), "endPeriod"),
    ).toThrow("The game clock must be at 0:00 before ending the period");
  });

  it("maps next-period, overtime, and finish commands", () => {
    expect(resolveLifecycleAction(game(), "startNextPeriod")).toEqual({
      action: "nextPeriod",
    });
    expect(resolveLifecycleAction(game({ period: 3 }), "startOvertime")).toEqual({
      action: "startOvertime",
    });
    expect(resolveLifecycleAction(game(), "finishGame")).toEqual({
      action: "finishGame",
    });
  });

  it("rejects lifecycle changes after final", () => {
    expect(() =>
      resolveLifecycleAction(
        game({ status: "FINAL", gamePhase: "FINAL" }),
        "startGame",
      ),
    ).toThrow(GameLifecycleError);
  });
});
