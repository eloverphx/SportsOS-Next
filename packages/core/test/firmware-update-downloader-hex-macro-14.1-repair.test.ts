import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("ESP32 FirmwareUpdateDownloader Arduino HEX macro repair", () => {
  const source = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/FirmwareUpdateDownloader.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  const marker =
    source.indexOf(
      "FirmwareUpdateDownloader::bytesToHex",
    );

  const block =
    source.slice(
      marker,
      source.indexOf(
        "\n}",
        marker,
      ) + 2,
    );

  it("does not declare HEX as an identifier", () => {
    expect(block).not.toMatch(
      /static const char\*\s+HEX\s*=/,
    );
  });

  it("uses a non-conflicting hexadecimal lookup table", () => {
    expect(block).toContain(
      "HEX_DIGITS",
    );

    expect(block).not.toContain(
      "HEX[",
    );
  });
});
