import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.6 main runtime integration repair", () => {
  const main = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/main.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  it("loads boot health at startup", () => {
    expect(main).toContain(
      "bootHealth.begin()",
    );
  });

  it("confirms a pending OTA boot after authoritative runtime starts", () => {
    expect(main).toContain(
      "bootHealth.requiresValidation()",
    );

    expect(main).toContain(
      "bootHealth.confirmHealthy()",
    );
  });

  it("evaluates OTA install policy from loop()", () => {
    expect(main).toContain(
      "FirmwareInstallPolicy::evaluate",
    );

    expect(main).toContain(
      "FirmwareInstallDecision::ReadyToInstall",
    );
  });

  it("marks pending validation before reboot", () => {
    const pending =
      main.indexOf(
        "bootHealth.markPendingValidation()",
      );

    const restart =
      main.indexOf(
        "ESP.restart()",
      );

    expect(pending).toBeGreaterThan(-1);
    expect(restart).toBeGreaterThan(pending);
  });
});
