import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.2 ESP32 flash packaging", () => {
  it("defines a Docker-based flash workflow", () => {
    const script = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/flash-with-docker.sh",
        import.meta.url,
      ),
      "utf8",
    );

    expect(script).toContain(
      "--target upload",
    );

    expect(script).toContain(
      "--upload-port",
    );

    expect(script).toContain(
      "--device=",
    );
  });

  it("requires an explicit serial device", () => {
    const script = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/flash-with-docker.sh",
        import.meta.url,
      ),
      "utf8",
    );

    expect(script).toContain(
      "/dev/ttyUSB0",
    );

    expect(script).toContain(
      "serial device does not exist",
    );
  });

  it("documents the standard ESP32 flash offsets", () => {
    const manifest = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/FLASH-MANIFEST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(manifest).toContain(
      "0x1000",
    );

    expect(manifest).toContain(
      "0x8000",
    );

    expect(manifest).toContain(
      "0x10000",
    );
  });

  it("documents SHA-256 integrity checks", () => {
    const manifest = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/FLASH-MANIFEST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(manifest).toContain(
      "SHA256SUMS.txt",
    );
  });
});
