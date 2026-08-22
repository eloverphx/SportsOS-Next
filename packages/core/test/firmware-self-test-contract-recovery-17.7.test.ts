import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 17.7 firmware self-test contract recovery", () => {
  const header = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/include/CommissioningSelfTest.h",
      import.meta.url,
    ),
    "utf8",
  );

  const implementation = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/CommissioningSelfTest.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  it("restores the firmware commissioning self-test contract", () => {
    expect(header).toContain(
      "CommissioningSelfTestTelemetry",
    );

    expect(header).toContain(
      "CommissioningSelfTest",
    );
  });

  it("reports all commissioning checks", () => {
    for (const field of [
      "controllerPassed",
      "displayPassed",
      "inputPassed",
      "connectivityPassed",
      "firmwareRuntimePassed",
    ]) {
      expect(header).toContain(
        field,
      );
    }
  });

  it("serializes device telemetry as JSON", () => {
    expect(implementation).toContain(
      'document["deviceId"]',
    );

    expect(implementation).toContain(
      "serializeJson",
    );
  });

  it("keeps the self-test separate from game state", () => {
    expect(implementation).toContain(
      "non-game-state-changing",
    );
  });
});
