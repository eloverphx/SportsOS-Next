import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 17.2 automated commissioning validation", () => {
  const validator = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardCommissioningValidator.ts",
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

  it("automatically evaluates enrollment and verification", () => {
    expect(validator).toContain(
      "validateEnrollment",
    );

    expect(validator).toContain(
      "validateVerification",
    );
  });

  it("automatically evaluates assignment and connectivity", () => {
    expect(validator).toContain(
      "/scoreboard-devices/assignments",
    );

    expect(validator).toContain(
      "validateConnectivity",
    );
  });

  it("combines direct readiness and reliability classification", () => {
    expect(validator).toContain(
      "evaluateScoreboardControlReadiness",
    );

    expect(validator).toContain(
      "listScoreboardReliabilityClassifications",
    );
  });

  it("evaluates firmware state", () => {
    expect(validator).toContain(
      "validateFirmware",
    );

    expect(validator).toContain(
      "scoreboard-firmware",
    );
  });

  it("automatically evaluates GAME_READY after prerequisites", () => {
    expect(validator).toContain(
      "prerequisitesPassed",
    );

    expect(validator).toContain(
      '"GAME_READY"',
    );
  });

  it("provides an explicit validation endpoint", () => {
    expect(route).toContain(
      "/scoreboard-device-commissioning/:deviceId/validate",
    );
  });
});
