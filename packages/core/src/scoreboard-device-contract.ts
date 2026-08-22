export const SCOREBOARD_DEVICE_PROTOCOL_VERSION = 1 as const;

export type ScoreboardDeviceConnectionState =
  | "OFFLINE"
  | "CONNECTING"
  | "ONLINE"
  | "DEGRADED";

export type ScoreboardDeviceClockState = {
  remainingMs: number;
  running: boolean;
};

export type ScoreboardDeviceSnapshot = {
  protocolVersion: typeof SCOREBOARD_DEVICE_PROTOCOL_VERSION;
  deviceId: string;
  gameId: string | null;
  connectionState: ScoreboardDeviceConnectionState;
  homeScore: number;
  awayScore: number;
  period: number | null;
  clock: ScoreboardDeviceClockState;
  hornActive: boolean;
  updatedAt: string;
};

export type ScoreboardDeviceCommand =
  | {
      protocolVersion: typeof SCOREBOARD_DEVICE_PROTOCOL_VERSION;
      commandId: string;
      type: "SET_GAME";
      gameId: string | null;
    }
  | {
      protocolVersion: typeof SCOREBOARD_DEVICE_PROTOCOL_VERSION;
      commandId: string;
      type: "SET_SCORE";
      homeScore: number;
      awayScore: number;
    }
  | {
      protocolVersion: typeof SCOREBOARD_DEVICE_PROTOCOL_VERSION;
      commandId: string;
      type: "SET_CLOCK";
      remainingMs: number;
      running: boolean;
    }
  | {
      protocolVersion: typeof SCOREBOARD_DEVICE_PROTOCOL_VERSION;
      commandId: string;
      type: "SET_PERIOD";
      period: number | null;
    }
  | {
      protocolVersion: typeof SCOREBOARD_DEVICE_PROTOCOL_VERSION;
      commandId: string;
      type: "HORN";
      active: boolean;
    }
  | {
      protocolVersion: typeof SCOREBOARD_DEVICE_PROTOCOL_VERSION;
      commandId: string;
      type: "SYNC_STATE";
      snapshot: Omit<
        ScoreboardDeviceSnapshot,
        "connectionState" | "updatedAt"
      >;
    };

function assertNonNegativeInteger(
  value: number,
  label: string,
): void {
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`${label} must be a non-negative integer.`);
  }
}

export function validateScoreboardDeviceCommand(
  command: ScoreboardDeviceCommand,
): ScoreboardDeviceCommand {
  if (
    command.protocolVersion !==
    SCOREBOARD_DEVICE_PROTOCOL_VERSION
  ) {
    throw new Error(
      "Unsupported scoreboard device protocol version.",
    );
  }

  if (!command.commandId.trim()) {
    throw new Error("scoreboard commandId is required.");
  }

  switch (command.type) {
    case "SET_GAME":
      return command;

    case "SET_SCORE":
      assertNonNegativeInteger(command.homeScore, "homeScore");
      assertNonNegativeInteger(command.awayScore, "awayScore");
      return command;

    case "SET_CLOCK":
      if (
        !Number.isFinite(command.remainingMs) ||
        command.remainingMs < 0
      ) {
        throw new Error(
          "remainingMs must be a non-negative number.",
        );
      }
      return command;

    case "SET_PERIOD":
      if (
        command.period !== null &&
        (!Number.isInteger(command.period) || command.period < 1)
      ) {
        throw new Error(
          "period must be null or a positive integer.",
        );
      }
      return command;

    case "HORN":
      return command;

    case "SYNC_STATE":
      assertNonNegativeInteger(
        command.snapshot.homeScore,
        "homeScore",
      );
      assertNonNegativeInteger(
        command.snapshot.awayScore,
        "awayScore",
      );

      if (
        !Number.isFinite(command.snapshot.clock.remainingMs) ||
        command.snapshot.clock.remainingMs < 0
      ) {
        throw new Error(
          "remainingMs must be a non-negative number.",
        );
      }

      return command;
  }
}

export function buildScoreboardDeviceSnapshot(
  input: Omit<
    ScoreboardDeviceSnapshot,
    "protocolVersion" | "updatedAt"
  > & {
    updatedAt?: Date;
  },
): ScoreboardDeviceSnapshot {
  assertNonNegativeInteger(input.homeScore, "homeScore");
  assertNonNegativeInteger(input.awayScore, "awayScore");

  if (
    !Number.isFinite(input.clock.remainingMs) ||
    input.clock.remainingMs < 0
  ) {
    throw new Error(
      "remainingMs must be a non-negative number.",
    );
  }

  if (
    input.period !== null &&
    (!Number.isInteger(input.period) || input.period < 1)
  ) {
    throw new Error(
      "period must be null or a positive integer.",
    );
  }

  return {
    protocolVersion:
      SCOREBOARD_DEVICE_PROTOCOL_VERSION,
    deviceId: input.deviceId,
    gameId: input.gameId,
    connectionState: input.connectionState,
    homeScore: input.homeScore,
    awayScore: input.awayScore,
    period: input.period,
    clock: input.clock,
    hornActive: input.hornActive,
    updatedAt: (
      input.updatedAt ?? new Date()
    ).toISOString(),
  };
}
