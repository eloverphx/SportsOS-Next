import { describe, expect, it } from "vitest";
import {
  SCOREBOARD_DEVICE_PROTOCOL_VERSION,
  SCOREBOARD_MQTT_ROOT,
  buildScoreboardMqttCommandEnvelope,
  scoreboardMqttTopics,
  validateScoreboardDeviceCommand,
  type ScoreboardDeviceCommand,
  type ScoreboardDeviceSnapshot,
  type ScoreboardMqttAcknowledgement,
  type ScoreboardMqttPresence,
  type ScoreboardMqttTelemetry,
} from "../src/index.js";

describe("Milestone 10.4 core public scoreboard exports", () => {
  it("exports the physical scoreboard protocol", () => {
    expect(SCOREBOARD_DEVICE_PROTOCOL_VERSION).toBe(1);

    const command: ScoreboardDeviceCommand = {
      protocolVersion: 1,
      commandId: "cmd-public",
      type: "SET_SCORE",
      homeScore: 1,
      awayScore: 0,
    };

    expect(
      validateScoreboardDeviceCommand(command),
    ).toEqual(command);
  });

  it("exports the MQTT transport contract", () => {
    expect(SCOREBOARD_MQTT_ROOT).toBe(
      "sportsos/scoreboards",
    );

    expect(
      scoreboardMqttTopics("scoreboard-1").command,
    ).toBe(
      "sportsos/scoreboards/scoreboard-1/command",
    );

    expect(
      buildScoreboardMqttCommandEnvelope(
        "scoreboard-1",
        {
          protocolVersion: 1,
          commandId: "cmd-mqtt-public",
          type: "HORN",
          active: true,
        },
      ).deviceId,
    ).toBe("scoreboard-1");
  });

  it("exports all gateway-facing scoreboard types", () => {
    const snapshot: ScoreboardDeviceSnapshot = {
      protocolVersion: 1,
      deviceId: "scoreboard-1",
      gameId: null,
      connectionState: "ONLINE",
      homeScore: 0,
      awayScore: 0,
      period: null,
      clock: {
        remainingMs: 0,
        running: false,
      },
      hornActive: false,
      updatedAt: new Date(0).toISOString(),
    };

    const ack: ScoreboardMqttAcknowledgement = {
      deviceId: "scoreboard-1",
      commandId: "cmd-1",
      status: "APPLIED",
      message: null,
      acknowledgedAt: new Date(0).toISOString(),
    };

    const presence: ScoreboardMqttPresence = {
      deviceId: "scoreboard-1",
      online: true,
      reportedAt: new Date(0).toISOString(),
    };

    const telemetry: ScoreboardMqttTelemetry = {
      deviceId: "scoreboard-1",
      firmwareVersion: null,
      ipAddress: null,
      wifiRssi: null,
      uptimeSeconds: 0,
      freeHeapBytes: null,
      reportedAt: new Date(0).toISOString(),
    };

    expect(snapshot.deviceId).toBe("scoreboard-1");
    expect(ack.status).toBe("APPLIED");
    expect(presence.online).toBe(true);
    expect(telemetry.uptimeSeconds).toBe(0);
  });
});
