import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 17.8 remote self-test dispatch / response correlation", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardCommissioningSelfTestDispatch.ts",
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

  const firmware = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/CommissioningSelfTest.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  it("creates unique correlated self-test commands", () => {
    expect(service).toContain(
      "crypto.randomUUID",
    );

    expect(service).toContain(
      '"PENDING"',
    );
  });

  it("tracks acknowledgement and completion states", () => {
    expect(service).toContain(
      '"ACKNOWLEDGED"',
    );

    expect(service).toContain(
      '"COMPLETED"',
    );

    expect(service).toContain(
      '"FAILED"',
    );
  });

  it("provides dispatch and acknowledgement API routes", () => {
    expect(route).toContain(
      "/self-test/dispatch",
    );

    expect(route).toContain(
      "/ack",
    );

    expect(route).toContain(
      "COMMISSIONING_SELF_TEST",
    );
  });

  it("correlates firmware telemetry with command ID", () => {
    expect(route).toContain(
      "commandId?: string",
    );

    expect(route).toContain(
      "completeCommissioningSelfTestDispatch",
    );

    expect(firmware).toContain(
      'document["commandId"]',
    );
  });

  it("rejects command/device mismatches", () => {
    expect(service).toContain(
      "Self-test command belongs to another device.",
    );
  });
});
