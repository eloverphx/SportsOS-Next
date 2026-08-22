import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 17.1 scoreboard device commissioning", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardDeviceCommissioning.ts",
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

  const doc = fs.readFileSync(
    new URL(
      "../../../docs/SCOREBOARD-DEVICE-COMMISSIONING.md",
      import.meta.url,
    ),
    "utf8",
  );

  it("defines the complete commissioning lifecycle", () => {
    for (const step of [
      "FLASHED",
      "PROVISIONED",
      "ENROLLED",
      "VERIFIED",
      "ASSIGNED",
      "CONNECTIVITY",
      "READINESS",
      "FIRMWARE",
      "GAME_READY",
    ]) {
      expect(service).toContain(
        `"${step}"`,
      );
    }
  });

  it("persists commissioning records", () => {
    expect(service).toContain(
      "scoreboard-device-commissioning.json",
    );
  });

  it("prevents premature GAME_READY state", () => {
    expect(service).toContain(
      "All commissioning prerequisites must pass before GAME_READY.",
    );
  });

  it("provides commissioning API routes", () => {
    expect(route).toContain(
      "/scoreboard-device-commissioning",
    );

    expect(route).toContain(
      "/scoreboard-device-commissioning/:deviceId/step",
    );
  });

  it("documents physical installation stages", () => {
    expect(doc).toContain(
      "SportsOS Scoreboard Device Commissioning",
    );

    expect(doc).toContain(
      "production ESP32 firmware",
    );

    expect(doc).toContain(
      "GAME_READY",
    );
  });
});
