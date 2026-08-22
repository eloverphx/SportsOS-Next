import { describe, expect, it } from "vitest";
import {
  SCOREBOARD_DEVICE_PROTOCOL_VERSION,
  buildScoreboardDeviceSnapshot,
  validateScoreboardDeviceCommand,
} from "../src/scoreboard-device-contract";

describe("Milestone 10.1 physical scoreboard device contract", () => {
  it("builds a versioned device snapshot", () => {
    const snapshot = buildScoreboardDeviceSnapshot({
      deviceId: "scoreboard-1",
      gameId: "game-1",
      connectionState: "ONLINE",
      homeScore: 3,
      awayScore: 2,
      period: 2,
      clock: {
        remainingMs: 125000,
        running: true,
      },
      hornActive: false,
      updatedAt: new Date(
        "2026-08-17T12:00:00.000Z",
      ),
    });

    expect(snapshot).toMatchObject({
      protocolVersion:
        SCOREBOARD_DEVICE_PROTOCOL_VERSION,
      deviceId: "scoreboard-1",
      gameId: "game-1",
      homeScore: 3,
      awayScore: 2,
      period: 2,
    });
  });

  it("accepts a valid score command", () => {
    const command = validateScoreboardDeviceCommand({
      protocolVersion:
        SCOREBOARD_DEVICE_PROTOCOL_VERSION,
      commandId: "cmd-1",
      type: "SET_SCORE",
      homeScore: 4,
      awayScore: 1,
    });

    expect(command.type).toBe("SET_SCORE");
  });

  it("accepts a valid clock command", () => {
    expect(
      validateScoreboardDeviceCommand({
        protocolVersion:
          SCOREBOARD_DEVICE_PROTOCOL_VERSION,
        commandId: "cmd-clock",
        type: "SET_CLOCK",
        remainingMs: 60000,
        running: true,
      }),
    ).toMatchObject({
      type: "SET_CLOCK",
      remainingMs: 60000,
      running: true,
    });
  });

  it("rejects negative scores", () => {
    expect(() =>
      validateScoreboardDeviceCommand({
        protocolVersion:
          SCOREBOARD_DEVICE_PROTOCOL_VERSION,
        commandId: "cmd-bad-score",
        type: "SET_SCORE",
        homeScore: -1,
        awayScore: 0,
      }),
    ).toThrow(
      "homeScore must be a non-negative integer.",
    );
  });

  it("rejects invalid periods", () => {
    expect(() =>
      validateScoreboardDeviceCommand({
        protocolVersion:
          SCOREBOARD_DEVICE_PROTOCOL_VERSION,
        commandId: "cmd-period",
        type: "SET_PERIOD",
        period: 0,
      }),
    ).toThrow(
      "period must be null or a positive integer.",
    );
  });

  it("supports full state synchronization", () => {
    const command = validateScoreboardDeviceCommand({
      protocolVersion:
        SCOREBOARD_DEVICE_PROTOCOL_VERSION,
      commandId: "cmd-sync",
      type: "SYNC_STATE",
      snapshot: {
        protocolVersion:
          SCOREBOARD_DEVICE_PROTOCOL_VERSION,
        deviceId: "scoreboard-1",
        gameId: "game-1",
        homeScore: 5,
        awayScore: 4,
        period: 3,
        clock: {
          remainingMs: 45000,
          running: false,
        },
        hornActive: false,
      },
    });

    expect(command.type).toBe("SYNC_STATE");
  });
});
