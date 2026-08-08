import { beforeEach, describe, expect, it } from "vitest";
import {
  clearEngineTransitionHistoryForTests,
  getEngineTransitionHistory,
  recordEngineTransition,
} from "../src/modules/games/telemetry.js";

beforeEach(() => {
  clearEngineTransitionHistoryForTests();
});

describe("operator lifecycle audit history", () => {
  it("records operator lifecycle actions with actor metadata", () => {
    recordEngineTransition({
      timestamp: "2026-08-08T15:30:00.000Z",
      source: "operator",
      gameId: 42,
      action: "startOvertime",
      outcome: "applied",
      actorUserId: 7,
      actorRole: "scorekeeper",
    });

    expect(getEngineTransitionHistory()).toEqual([
      expect.objectContaining({
        source: "operator",
        gameId: 42,
        action: "startOvertime",
        outcome: "applied",
        actorUserId: 7,
        actorRole: "scorekeeper",
      }),
    ]);
  });

  it("preserves replay visibility for duplicate operator commands", () => {
    recordEngineTransition({
      source: "operator",
      gameId: 42,
      action: "finishGame",
      outcome: "replayed",
      actorUserId: 7,
      actorRole: "scorekeeper",
    });

    expect(getEngineTransitionHistory()[0]?.outcome).toBe("replayed");
  });
});
