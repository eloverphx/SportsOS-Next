import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.2 ESP32 MQTT JSON codec", () => {
  it("declares command parsing and device serializers", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardMqttCodec.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "parseCommand",
    );
    expect(header).toContain(
      "encodeState",
    );
    expect(header).toContain(
      "encodeAcknowledgement",
    );
    expect(header).toContain(
      "encodePresence",
    );
    expect(header).toContain(
      "encodeTelemetry",
    );
  });

  it("maps every protocol command type", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardMqttCodec.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    for (const type of [
      "SET_GAME",
      "SET_SCORE",
      "SET_CLOCK",
      "SET_PERIOD",
      "HORN",
      "SYNC_STATE",
    ]) {
      expect(source).toContain(type);
    }
  });

  it("enforces protocol version and commandId", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardMqttCodec.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "Protocol version mismatch.",
    );
    expect(source).toContain(
      "commandId is required.",
    );
  });

  it("serializes the Milestone 10 telemetry contract", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardMqttCodec.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    for (const field of [
      "firmwareVersion",
      "ipAddress",
      "wifiRssi",
      "uptimeSeconds",
      "freeHeapBytes",
      "reportedAt",
    ]) {
      expect(source).toContain(
        `document["${field}"]`,
      );
    }
  });

  it("uses ArduinoJson through PlatformIO", () => {
    const platformio = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/platformio.ini",
        import.meta.url,
      ),
      "utf8",
    );

    expect(platformio).toContain(
      "bblanchon/ArduinoJson",
    );
    expect(platformio).toContain(
      "framework = arduino",
    );
  });
});
