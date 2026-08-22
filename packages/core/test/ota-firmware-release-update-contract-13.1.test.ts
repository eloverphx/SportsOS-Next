import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  SCOREBOARD_FIRMWARE_UPDATE_PROTOCOL_VERSION,
  isTerminalFirmwareUpdateStatus,
} from "../src/scoreboard-firmware-update-contract.js";

describe("Milestone 13.1 OTA firmware release contract", () => {
  it("defines protocol version 1", () => {
    expect(
      SCOREBOARD_FIRMWARE_UPDATE_PROTOCOL_VERSION,
    ).toBe(1);
  });

  it("defines stable beta and development channels", () => {
    const source = fs.readFileSync(
      new URL(
        "../src/scoreboard-firmware-update-contract.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain('"stable"');
    expect(source).toContain('"beta"');
    expect(source).toContain('"development"');
  });

  it("defines the complete update lifecycle", () => {
    const source = fs.readFileSync(
      new URL(
        "../src/scoreboard-firmware-update-contract.ts",
        import.meta.url,
      ),
      "utf8",
    );

    for (const state of [
      "IDLE",
      "AVAILABLE",
      "DOWNLOADING",
      "VERIFYING",
      "READY_TO_INSTALL",
      "INSTALLING",
      "REBOOTING",
      "SUCCEEDED",
      "FAILED",
    ]) {
      expect(source).toContain(state);
    }
  });

  it("treats succeeded and failed as terminal states", () => {
    expect(
      isTerminalFirmwareUpdateStatus(
        "SUCCEEDED",
      ),
    ).toBe(true);

    expect(
      isTerminalFirmwareUpdateStatus(
        "FAILED",
      ),
    ).toBe(true);

    expect(
      isTerminalFirmwareUpdateStatus(
        "INSTALLING",
      ),
    ).toBe(false);
  });

  it("requires SHA-256 validation in firmware contract", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareUpdateContract.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "offer.firmwareSha256",
    );

    expect(source).toContain(
      "!= 64",
    );
  });

  it("adds a release packaging script", () => {
    const releaseScript = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/create-ota-release.sh",
        import.meta.url,
      ),
      "utf8",
    );

    expect(releaseScript).toContain(
      "release.json",
    );

    expect(releaseScript).toContain(
      "sha256sum",
    );

    expect(releaseScript).toContain(
      "releases/ota",
    );
  });
});
