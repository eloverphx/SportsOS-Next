import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.4 device OTA update check / offer binding", () => {
  it("adds a verified-device OTA offer endpoint", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareReleases.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/device-offer",
    );

    expect(routes).toContain(
      "isVerifiedDevice",
    );

    expect(routes).toContain(
      "Verified scoreboard device required.",
    );
  });

  it("returns a device-bound firmware artifact URL", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareReleases.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "artifactUrl",
    );

    expect(routes).toContain(
      "deviceId=",
    );
  });

  it("defines an ESP32 firmware update check client", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/FirmwareUpdateClient.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "FirmwareUpdateClient",
    );

    expect(header).toContain(
      "FirmwareUpdateCheckState",
    );
  });

  it("validates offers before marking an update available", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareUpdateClient.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "FirmwareUpdateContract::validateOffer",
    );

    expect(source).toContain(
      "UpdateAvailable",
    );
  });

  it("checks for updates only after enrollment verification", () => {
    const main = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/main.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(main).toContain(
      "firmwareUpdateClient->loop",
    );

    expect(main).toContain(
      "enrollmentClient->isVerified()",
    );
  });

  it("adds host simulator coverage for OTA offers", () => {
    const simulator = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js",
        import.meta.url,
      ),
      "utf8",
    );

    expect(simulator).toContain(
      "evaluateFirmwareUpdateOffer",
    );

    expect(simulator).toContain(
      "BLOCKED_UNVERIFIED",
    );

    expect(simulator).toContain(
      "UPDATE_AVAILABLE",
    );
  });
});
