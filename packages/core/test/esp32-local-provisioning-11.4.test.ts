import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.4 ESP32 local provisioning", () => {
  it("stores configuration with ESP32 Preferences", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ProvisioningManager.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "#include <Preferences.h>",
    );
    expect(header).toContain(
      "PersistedRuntimeConfig",
    );
  });

  it("provides local save status and reset routes", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ProvisioningManager.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    for (const route of [
      '"/save"',
      '"/status"',
      '"/reset"',
    ]) {
      expect(source).toContain(
        route,
      );
    }
  });

  it("creates a unique SportsOS local access point", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ProvisioningManager.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "SportsOS-Scoreboard-",
    );
    expect(source).toContain(
      "ESP.getEfuseMac",
    );
    expect(source).toContain(
      "WiFi.softAP",
    );
  });

  it("does not echo stored passwords into the setup form", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ProvisioningManager.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "type='password' value=''",
    );
    expect(source).toContain(
      "Preserve existing secrets",
    );
  });

  it("boots the runtime from persisted configuration", () => {
    const main = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/main.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(main).toContain(
      "ProvisioningManager provisioning",
    );
    expect(main).toContain(
      "provisioning.hasValidConfig",
    );
    expect(main).toContain(
      "new ScoreboardRuntime",
    );
  });
});
