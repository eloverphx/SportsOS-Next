import {
  SCOREBOARD_DEVICE_PROTOCOL_VERSION,
  type ScoreboardDeviceCommand,
} from "@sportsos/core";
import {
  ScoreboardDeviceGateway,
} from "./scoreboardDeviceGateway.js";

export type AuthoritativeGameSnapshot = {
  gameId: string;
  homeScore: number;
  awayScore: number;
  period: number | null;
  clock: {
    remainingMs: number;
    running: boolean;
  };
};

export function buildGameScoreboardSyncCommand(
  snapshot: AuthoritativeGameSnapshot,
  deviceId: string,
  commandId: string,
): ScoreboardDeviceCommand {
  if (!deviceId.trim()) {
    throw new Error("deviceId is required.");
  }

  if (!snapshot.gameId.trim()) {
    throw new Error("gameId is required.");
  }

  if (
    !Number.isInteger(snapshot.homeScore) ||
    snapshot.homeScore < 0
  ) {
    throw new Error(
      "homeScore must be a non-negative integer.",
    );
  }

  if (
    !Number.isInteger(snapshot.awayScore) ||
    snapshot.awayScore < 0
  ) {
    throw new Error(
      "awayScore must be a non-negative integer.",
    );
  }

  if (
    !Number.isFinite(snapshot.clock.remainingMs) ||
    snapshot.clock.remainingMs < 0
  ) {
    throw new Error(
      "remainingMs must be a non-negative number.",
    );
  }

  if (
    snapshot.period !== null &&
    (
      !Number.isInteger(snapshot.period) ||
      snapshot.period < 1
    )
  ) {
    throw new Error(
      "period must be null or a positive integer.",
    );
  }

  return {
    protocolVersion:
      SCOREBOARD_DEVICE_PROTOCOL_VERSION,
    commandId,
    type: "SYNC_STATE",
    snapshot: {
      protocolVersion:
        SCOREBOARD_DEVICE_PROTOCOL_VERSION,
      deviceId,
      gameId: snapshot.gameId,
      homeScore: snapshot.homeScore,
      awayScore: snapshot.awayScore,
      period: snapshot.period,
      clock: {
        remainingMs:
          snapshot.clock.remainingMs,
        running:
          snapshot.clock.running,
      },
      hornActive: false,
    },
  };
}

export class GameScoreboardSyncService {
  public constructor(
    private readonly gateway:
      ScoreboardDeviceGateway,
  ) {}

  public async sync(
    snapshot: AuthoritativeGameSnapshot,
    deviceId: string,
  ): Promise<string> {
    const commandId =
      `game-sync-${Date.now()}-${Math.random()
        .toString(16)
        .slice(2, 8)}`;

    const command =
      buildGameScoreboardSyncCommand(
        snapshot,
        deviceId,
        commandId,
      );

    await this.gateway.sendCommand(
      deviceId,
      command,
    );

    return commandId;
  }
}
