import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.5 ESP32 OTA download / integrity verification", () => {
  it("defines a firmware update downloader", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/FirmwareUpdateDownloader.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "FirmwareUpdateDownloader",
    );

    expect(header).toContain(
      "FirmwareDownloadResult",
    );
  });

  it("streams firmware into the ESP32 Update partition", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareUpdateDownloader.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "Update.begin",
    );

    expect(source).toContain(
      "Update.write",
    );

    expect(source).toContain(
      "Update.abort",
    );
  });

  it("calculates SHA-256 while downloading", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareUpdateDownloader.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "mbedtls_sha256_update_ret",
    );

    expect(source).toContain(
      "mbedtls_sha256_finish_ret",
    );

    expect(source).toContain(
      "equalsIgnoreCase",
    );
  });

  it("verifies total firmware size", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareUpdateDownloader.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "offer.firmwareSizeBytes",
    );

    expect(source).toContain(
      "SizeMismatch",
    );
  });

  it("finalizes the OTA partition only after SHA verification", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareUpdateDownloader.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    const shaCheck =
      source.indexOf(
        "equalsIgnoreCase",
      );

    const finalize =
      source.indexOf(
        "Update.end(true)",
      );

    expect(shaCheck).toBeGreaterThan(
      -1,
    );

    expect(finalize).toBeGreaterThan(
      shaCheck,
    );
  });

  it("exposes staging through FirmwareUpdateClient", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareUpdateClient.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "stageAvailableUpdate",
    );

    expect(source).toContain(
      "downloadAndStage",
    );
  });

  it("adds host simulator download-integrity behavior", () => {
    const simulator = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js",
        import.meta.url,
      ),
      "utf8",
    );

    expect(simulator).toContain(
      "verifyFirmwareDownload",
    );

    expect(simulator).toContain(
      "SHA256_MISMATCH",
    );

    expect(simulator).toContain(
      "READY_TO_INSTALL",
    );
  });
});
