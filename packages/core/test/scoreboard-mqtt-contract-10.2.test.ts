import { describe, expect, it } from "vitest";
import {
  SCOREBOARD_DEVICE_PROTOCOL_VERSION,
} from "../src/scoreboard-device-contract.js";
import {
  SCOREBOARD_MQTT_ROOT,
  buildScoreboardMqttAcknowledgement,
  buildScoreboardMqttCommandEnvelope,
  buildScoreboardMqttPresence,
  buildScoreboardMqttPublications,
  buildScoreboardMqttTelemetry,
  scoreboardMqttTopics,
} from "../src/scoreboard-mqtt-contract.js";

describe("Milestone 10.2 MQTT device transport contract", () => {
  it("builds stable per-device MQTT topics", () => {
    expect(
      scoreboardMqttTopics("scoreboard-1"),
    ).toEqual({
      command:
        `${SCOREBOARD_MQTT_ROOT}/scoreboard-1/command`,
      acknowledgement:
        `${SCOREBOARD_MQTT_ROOT}/scoreboard-1/ack`,
      state:
        `${SCOREBOARD_MQTT_ROOT}/scoreboard-1/state`,
      telemetry:
        `${SCOREBOARD_MQTT_ROOT}/scoreboard-1/telemetry`,
      presence:
        `${SCOREBOARD_MQTT_ROOT}/scoreboard-1/presence`,
    });
  });

  it("rejects unsafe device ids for MQTT topics", () => {
    expect(() =>
      scoreboardMqttTopics("scoreboard/1"),
    ).toThrow(
      "deviceId contains unsupported MQTT topic characters.",
    );
  });

  it("wraps commands in a transport envelope", () => {
    const envelope =
      buildScoreboardMqttCommandEnvelope(
        "scoreboard-1",
        {
          protocolVersion:
            SCOREBOARD_DEVICE_PROTOCOL_VERSION,
          commandId: "cmd-1",
          type: "HORN",
          active: true,
        },
        new Date("2026-08-17T20:00:00.000Z"),
      );

    expect(envelope).toMatchObject({
      deviceId: "scoreboard-1",
      sentAt: "2026-08-17T20:00:00.000Z",
      command: {
        commandId: "cmd-1",
        type: "HORN",
      },
    });
  });

  it("builds command acknowledgements", () => {
    expect(
      buildScoreboardMqttAcknowledgement({
        deviceId: "scoreboard-1",
        commandId: "cmd-1",
        status: "APPLIED",
        message: null,
        acknowledgedAt: new Date(
          "2026-08-17T20:00:01.000Z",
        ),
      }),
    ).toMatchObject({
      deviceId: "scoreboard-1",
      commandId: "cmd-1",
      status: "APPLIED",
    });
  });

  it("builds presence and telemetry payloads", () => {
    expect(
      buildScoreboardMqttPresence(
        "scoreboard-1",
        true,
        new Date("2026-08-17T20:00:02.000Z"),
      ),
    ).toEqual({
      deviceId: "scoreboard-1",
      online: true,
      reportedAt: "2026-08-17T20:00:02.000Z",
    });

    expect(
      buildScoreboardMqttTelemetry({
        deviceId: "scoreboard-1",
        firmwareVersion: "1.0.0",
        ipAddress: "192.168.5.50",
        wifiRssi: -55,
        uptimeSeconds: 3600,
        freeHeapBytes: 120000,
        reportedAt: new Date(
          "2026-08-17T20:00:03.000Z",
        ),
      }),
    ).toMatchObject({
      firmwareVersion: "1.0.0",
      wifiRssi: -55,
      uptimeSeconds: 3600,
    });
  });

  it("uses retained state/presence and ephemeral command/telemetry", () => {
    const command =
      buildScoreboardMqttCommandEnvelope(
        "scoreboard-1",
        {
          protocolVersion:
            SCOREBOARD_DEVICE_PROTOCOL_VERSION,
          commandId: "cmd-2",
          type: "SET_SCORE",
          homeScore: 2,
          awayScore: 1,
        },
      );

    const presence =
      buildScoreboardMqttPresence(
        "scoreboard-1",
        true,
      );

    const publications =
      buildScoreboardMqttPublications({
        deviceId: "scoreboard-1",
        command,
        presence,
      });

    expect(publications).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          topicKind: "command",
          qos: 1,
          retain: false,
        }),
        expect.objectContaining({
          topicKind: "presence",
          qos: 1,
          retain: true,
        }),
      ]),
    );
  });
});
