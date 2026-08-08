import fs from "node:fs";
import { describe, expect, it } from "vitest";
import {
  gamePhases,
  gameStatuses,
  scoreboardDeviceStatuses,
  type Game,
  type GameEvent,
  type ScoreboardDevice,
} from "@sportsos/core";

describe("shared contracts foundation", () => {
  it("exports authoritative game and device enums", () => {
    expect(gameStatuses).toEqual(["SCHEDULED", "LIVE", "FINAL", "POSTPONED", "CANCELED"]);

    expect(gamePhases).toEqual(["PREGAME", "REGULATION", "INTERMISSION", "OVERTIME", "FINAL"]);

    expect(scoreboardDeviceStatuses).toEqual(["OFFLINE", "ONLINE"]);
  });

  it("keeps API feature type modules as core re-exports", () => {
    const gameTypes = fs.readFileSync(
      new URL("../src/modules/games/types.ts", import.meta.url),
      "utf8",
    );
    const eventTypes = fs.readFileSync(
      new URL("../src/modules/game-events/types.ts", import.meta.url),
      "utf8",
    );
    const deviceTypes = fs.readFileSync(
      new URL("../src/modules/scoreboard-devices/types.ts", import.meta.url),
      "utf8",
    );

    expect(gameTypes).toContain('from "@sportsos/core"');
    expect(eventTypes).toContain('from "@sportsos/core"');
    expect(deviceTypes).toContain('from "@sportsos/core"');
  });

  it("makes the primary wire DTOs consumable from core", () => {
    const game = {} as Game;
    const event = {} as GameEvent;
    const device = {} as ScoreboardDevice;

    expect([game, event, device]).toHaveLength(3);
  });
});
