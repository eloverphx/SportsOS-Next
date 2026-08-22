import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.2 core OTA public export repair", () => {
  it("exports the OTA firmware contract from the core index", () => {
    const index = fs.readFileSync(
      new URL(
        "../src/index.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(index).toContain(
      'export * from "./scoreboard-firmware-update-contract.js";',
    );
  });

  it("publishes declaration entrypoint from the core package", () => {
    const pkg = JSON.parse(
      fs.readFileSync(
        new URL(
          "../package.json",
          import.meta.url,
        ),
        "utf8",
      ),
    );

    expect(pkg.types).toBe(
      "./dist/index.d.ts",
    );
  });

  it("keeps OTA contract source present", () => {
    const source = fs.readFileSync(
      new URL(
        "../src/scoreboard-firmware-update-contract.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "FirmwareReleaseChannel",
    );
    expect(source).toContain(
      "FirmwareReleaseTarget",
    );
    expect(source).toContain(
      "ScoreboardFirmwareRelease",
    );
  });
});
