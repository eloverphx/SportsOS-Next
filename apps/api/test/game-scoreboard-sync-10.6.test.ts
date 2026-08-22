import { describe, expect, it } from "vitest";
import fs from "node:fs";
import {
  buildGameScoreboardSyncCommand,
} from "../src/services/gameScoreboardSync.js";

describe("Milestone 10.6 game-to-scoreboard synchronization", () => {
  it("builds a full SYNC_STATE command from authoritative game state", () => {
    const command =
      buildGameScoreboardSyncCommand(
        {
          gameId: "game-1",
          homeScore: 4,
          awayScore: 3,
          period: 2,
          clock: {
            remainingMs: 88500,
            running: true,
          },
        },
        "scoreboard-1",
        "cmd-sync-game",
      );

    expect(command).toEqual({
      protocolVersion: 1,
      commandId: "cmd-sync-game",
      type: "SYNC_STATE",
      snapshot: {
        protocolVersion: 1,
        deviceId: "scoreboard-1",
        gameId: "game-1",
        homeScore: 4,
        awayScore: 3,
        period: 2,
        clock: {
          remainingMs: 88500,
          running: true,
        },
        hornActive: false,
      },
    });
  });

  it("rejects invalid authoritative scores", () => {
    expect(() =>
      buildGameScoreboardSyncCommand(
        {
          gameId: "game-1",
          homeScore: -1,
          awayScore: 0,
          period: 1,
          clock: {
            remainingMs: 1000,
            running: false,
          },
        },
        "scoreboard-1",
        "cmd-invalid",
      ),
    ).toThrow(
      "homeScore must be a non-negative integer.",
    );
  });

  it("rejects invalid clock values", () => {
    expect(() =>
      buildGameScoreboardSyncCommand(
        {
          gameId: "game-1",
          homeScore: 0,
          awayScore: 0,
          period: 1,
          clock: {
            remainingMs: -1,
            running: false,
          },
        },
        "scoreboard-1",
        "cmd-invalid-clock",
      ),
    ).toThrow(
      "remainingMs must be a non-negative number.",
    );
  });

  it("exposes the sync-game API endpoint", () => {
    const route = fs.readFileSync(
      new URL(
        "../src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain(
      '"/scoreboard-devices/:deviceId/sync-game"',
    );
    expect(route).toContain(
      "GameScoreboardSyncService",
    );
    expect(route).toContain(
      "await syncService.sync",
    );
  });
});
