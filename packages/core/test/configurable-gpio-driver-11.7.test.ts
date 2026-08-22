import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.7 configurable GPIO driver", () => {
  it("defines configurable active-high/active-low outputs", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/GpioScoreboardDisplayDriver.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "DigitalOutputConfig",
    );
    expect(header).toContain(
      "activeHigh",
    );
    expect(header).toContain(
      "enabled",
    );
  });

  it("supports horn and all hardware health indicators", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/GpioScoreboardDisplayDriver.h",
        import.meta.url,
      ),
      "utf8",
    );

    for (const field of [
      "horn",
      "statusNormal",
      "statusWifiLost",
      "statusMqttLost",
      "statusStale",
      "statusRecovery",
    ]) {
      expect(header).toContain(field);
    }
  });

  it("initializes physical outputs to an inactive state", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/GpioScoreboardDisplayDriver.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "configureOutput",
    );
    expect(source).toContain(
      "writeOutput",
    );
    expect(source).toContain(
      "clear();",
    );
  });

  it("rejects classic ESP32 input-only GPIO 34 through 39", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/GpioScoreboardDisplayDriver.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "pin <= 33",
    );
  });

  it("keeps the concrete driver limited to low-voltage GPIO signaling", () => {
    const readme = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/README.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(readme).toContain(
      "low-voltage ESP32 GPIO signaling",
    );
  });
});
