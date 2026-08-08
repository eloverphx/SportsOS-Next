import fs from "node:fs";
import { describe, expect, it } from "vitest";
import type {
  Game,
  PublicScoreboardGame,
  ScoreboardDevice,
  ScoreboardPenalty,
} from "@sportsos/core";

describe("dashboard shared models", () => {
  it("exports the public scoreboard response model", () => {
    const penalty = {} as ScoreboardPenalty;
    const scoreboard = {} as PublicScoreboardGame;
    const game = {} as Game;
    const device = {} as ScoreboardDevice;

    expect([penalty, scoreboard, game, device]).toHaveLength(4);
  });

  it("removes duplicated dashboard GameStatus and GamePhase unions from primary game pages", () => {
    const files = [
      "../../dashboard/app/games/[id]/scoreboard/page.tsx",
      "../../dashboard/app/games/[id]/overlay/page.tsx",
      "../../dashboard/app/scoreboards/[id]/control/page.tsx",
      "../../dashboard/app/scoreboards/page.tsx",
      "../../dashboard/app/games/page.tsx",
    ];

    for (const relative of files) {
      const source = fs.readFileSync(new URL(relative, import.meta.url), "utf8");
      expect(source).not.toContain(
        'type GameStatus = "SCHEDULED" | "LIVE" | "FINAL" | "POSTPONED" | "CANCELED"',
      );
      expect(source).not.toContain(
        'type GamePhase = "PREGAME" | "REGULATION" | "INTERMISSION" | "OVERTIME" | "FINAL"',
      );
    }
  });
});
