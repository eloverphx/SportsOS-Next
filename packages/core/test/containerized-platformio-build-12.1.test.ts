import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.1 containerized PlatformIO toolchain", () => {
  it("defines a reproducible PlatformIO Docker image", () => {
    const dockerfile = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/Dockerfile.platformio",
        import.meta.url,
      ),
      "utf8",
    );

    expect(dockerfile).toContain(
      "pip install --no-cache-dir platformio",
    );

    expect(dockerfile).toContain(
      'ENTRYPOINT ["platformio"]',
    );
  });

  it("builds firmware without host PlatformIO", () => {
    const script = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/build-in-docker.sh",
        import.meta.url,
      ),
      "utf8",
    );

    expect(script).toContain(
      "docker build",
    );

    expect(script).toContain(
      "docker run --rm",
    );

    expect(script).toContain(
      "sportsos_platformio_core",
    );
  });

  it("retains the canonical-root safety guard", () => {
    const script = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/build-in-docker.sh",
        import.meta.url,
      ),
      "utf8",
    );

    expect(script).toContain(
      "/mnt/user/appdata/SportsOS-Next",
    );

    expect(script).toContain(
      "refusing to run outside canonical SportsOS-Next root",
    );
  });

  it("documents the compiled firmware binary path", () => {
    const readme = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/README.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(readme).toContain(
      ".pio/build/esp32dev/firmware.bin",
    );
  });
});
