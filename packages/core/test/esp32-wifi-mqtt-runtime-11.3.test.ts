import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.3 ESP32 Wi-Fi / MQTT runtime", () => {
  it("defines all Milestone 10 MQTT topics", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardRuntime.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    for (const suffix of [
      "command",
      "ack",
      "state",
      "telemetry",
      "presence",
    ]) {
      expect(source).toContain(
        `"${suffix}"`,
      );
    }

    expect(source).toContain(
      "sportsos/scoreboards/%s/%s",
    );
  });

  it("implements Wi-Fi and MQTT reconnect loops", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardRuntime.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "maintainWifi",
    );
    expect(source).toContain(
      "maintainMqtt",
    );
    expect(source).toContain(
      "WiFi.begin",
    );
    expect(source).toContain(
      "connectMqtt",
    );
  });

  it("publishes retained presence and state", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardRuntime.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "presenceTopic_",
    );
    expect(source).toContain(
      "stateTopic_",
    );
    expect(source).toContain(
      "publishPresence",
    );
    expect(source).toContain(
      "publishState",
    );
    expect(source).toMatch(
      /mqttClient_\.publish\([\s\S]*stateTopic_[\s\S]*true\)/,
    );
  });

  it("publishes ACCEPTED before applying a valid command", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardRuntime.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    const accepted =
      source.indexOf(
        "CommandStatus::Accepted",
      );

    const apply =
      source.indexOf(
        "protocol_.apply",
      );

    expect(accepted).toBeGreaterThan(
      -1,
    );
    expect(apply).toBeGreaterThan(
      accepted,
    );
  });

  it("uses PubSubClient through PlatformIO", () => {
    const platformio =
      fs.readFileSync(
        new URL(
          "../../../firmware/esp32-scoreboard/platformio.ini",
          import.meta.url,
        ),
        "utf8",
      );

    expect(platformio).toContain(
      "knolleary/PubSubClient",
    );
  });

  it("does not commit real Wi-Fi credentials", () => {
    const main = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/main.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(main).toContain(
      '#define SPORTSOS_WIFI_SSID ""',
    );
    expect(main).toContain(
      '#define SPORTSOS_WIFI_PASSWORD ""',
    );
  });
});
