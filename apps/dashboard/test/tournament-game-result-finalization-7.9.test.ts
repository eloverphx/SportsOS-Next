import { describe, expect, it } from "vitest";
import fs from "node:fs";
import {
  buildFinalizedGameResult,
  resultLabel,
} from "../lib/tournament-game-result-finalization";

describe("Milestone 7.9 game completion / result finalization", () => {
  it("uses the real finishGame lifecycle command", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/game-operations/[gameId]/finalize/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain("/lifecycle");
    expect(route).toContain('command: "finishGame"');
    expect(route).toContain('method: "POST"');
  });

  it("builds an authoritative final result", () => {
    const result = buildFinalizedGameResult({
      gameId: "game-79",
      homeScore: 5,
      awayScore: 3,
      status: "FINAL",
      gamePhase: "FINAL",
      finalizedAt: new Date("2026-08-17T02:00:00.000Z"),
    });

    expect(result.homeScore).toBe(5);
    expect(result.awayScore).toBe(3);
    expect(resultLabel(result)).toBe("Home win");
  });

  it("supports away wins and ties", () => {
    expect(
      resultLabel(
        buildFinalizedGameResult({
          gameId: "away-win",
          homeScore: 2,
          awayScore: 4,
          status: "FINAL",
        }),
      ),
    ).toBe("Away win");

    expect(
      resultLabel(
        buildFinalizedGameResult({
          gameId: "tie",
          homeScore: 3,
          awayScore: 3,
          status: "FINAL",
        }),
      ),
    ).toBe("Tie");
  });

  it("rejects malformed authoritative scores", () => {
    expect(() =>
      buildFinalizedGameResult({
        gameId: "bad",
        homeScore: "5",
        awayScore: 3,
        status: "FINAL",
      }),
    ).toThrow("invalid scores");
  });
});
