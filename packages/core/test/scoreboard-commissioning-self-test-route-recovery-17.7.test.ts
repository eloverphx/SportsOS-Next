import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 17.7 self-test route recovery", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardCommissioningSelfTest.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardDeviceCommissioning.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("restores the self-test service", () => {
    expect(service).toContain(
      "createCommissioningSelfTestResult",
    );

    expect(service).toContain(
      "latestCommissioningSelfTest",
    );
  });

  it("restores installer self-test routes", () => {
    expect(route).toContain(
      "/scoreboard-device-commissioning/:deviceId/self-test",
    );

    expect(route).toContain(
      'source:\n            "INSTALLER"',
    );
  });

  it("restores firmware telemetry route", () => {
    expect(route).toContain(
      "/scoreboard-device-commissioning/:deviceId/self-test/telemetry",
    );

    expect(route).toContain(
      'source:\n            "FIRMWARE"',
    );

    expect(route).toContain(
      "acknowledged",
    );
  });

  it("preserves route/device identity validation", () => {
    expect(route).toContain(
      "Telemetry device ID does not match route device ID.",
    );
  });
});
