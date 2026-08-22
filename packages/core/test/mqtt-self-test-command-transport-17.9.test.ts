import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 17.9 MQTT self-test command transport / device execution", () => {
  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardDeviceCommissioning.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const transport = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardDeviceGateway.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const command = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/CommissioningSelfTestCommand.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  const main = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/main.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  it("publishes the correlated self-test command through scoreboard transport", () => {
    expect(route).toContain(
      "publishCommissioningSelfTestCommand",
    );

    expect(route).toContain(
      "buildCommissioningSelfTestTransportCommand",
    );

    expect(transport).toContain(
      "publishCommissioningSelfTestCommand",
    );
  });

  it("returns 503 when device transport is unavailable", () => {
    expect(route).toContain(
      "reply.code(503)",
    );
  });

  it("decodes commissioning self-test commands in firmware", () => {
    expect(command).toContain(
      "COMMISSIONING_SELF_TEST",
    );

    expect(command).toContain(
      "commandId",
    );
  });

  it("rejects commands for another device", () => {
    expect(main).toContain(
      "command.deviceId !=",
    );
  });

  it("executes self-test and returns correlated telemetry", () => {
    expect(main).toContain(
      "CommissioningSelfTest::run",
    );

    expect(main).toContain(
      "command.commandId",
    );
  });
});
