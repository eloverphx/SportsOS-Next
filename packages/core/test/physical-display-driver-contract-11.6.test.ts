import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.6 physical display/status driver contract", () => {
  it("defines a hardware-independent display frame", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardDisplayDriver.h",
        import.meta.url,
      ),
      "utf8",
    );

    for (const field of [
      "homeScore",
      "awayScore",
      "period",
      "remainingMs",
      "clockRunning",
      "hornActive",
      "health",
    ]) {
      expect(header).toContain(field);
    }
  });

  it("defines an abstract physical display driver", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardDisplayDriver.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "virtual bool begin() = 0",
    );
    expect(header).toContain(
      "virtual void render",
    );
    expect(header).toContain(
      "virtual void setHorn",
    );
    expect(header).toContain(
      "virtual void setStatusIndicator",
    );
  });

  it("maps connectivity watchdog state into operator-visible display health", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardDisplayController.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    for (const state of [
      "WifiLost",
      "MqttLost",
      "StaleAuthoritativeState",
      "RecoveryRequired",
    ]) {
      expect(source).toContain(state);
    }
  });

  it("includes a null driver for hardware-independent testing", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/NullScoreboardDisplayDriver.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "NullScoreboardDisplayDriver",
    );
    expect(header).toContain(
      "lastFrame",
    );
  });

  it("does not hardcode GPIO or a display chipset in the shared contract", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardDisplayDriver.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).not.toMatch(
      /\bGPIO\b|MAX7219|TM1637|HUB75|NeoPixel|WS2812/i,
    );
  });
});
