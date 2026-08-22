import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.10 firmware diagnostics closeout", () => {
  it("defines a firmware diagnostic snapshot", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/FirmwareDiagnostics.h",
        import.meta.url,
      ),
      "utf8",
    );

    for (const field of [
      "uptimeSeconds",
      "wifiRssi",
      "freeHeapBytes",
      "wifiConnected",
      "mqttConnected",
      "authoritativeStateStale",
      "recoveryRequired",
      "connectionState",
      "connectivityHealth",
      "deviceId",
      "gameId",
    ]) {
      expect(header).toContain(field);
    }
  });

  it("maps diagnostic connection and health states to text", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareDiagnostics.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    for (const value of [
      "OFFLINE",
      "CONNECTING",
      "ONLINE",
      "DEGRADED",
      "WIFI_LOST",
      "MQTT_LOST",
      "STALE_AUTHORITATIVE_STATE",
      "RECOVERY_REQUIRED",
    ]) {
      expect(source).toContain(value);
    }
  });

  it("includes a real-hardware validation checklist", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/HARDWARE-VALIDATION-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(checklist).toContain(
      "Power and boot",
    );
    expect(checklist).toContain(
      "Authoritative synchronization",
    );
    expect(checklist).toContain(
      "Fault recovery",
    );
    expect(checklist).toContain(
      "Release gate",
    );
  });

  it("extends the host simulator with diagnostic behavior", () => {
    const simulator = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js",
        import.meta.url,
      ),
      "utf8",
    );

    expect(simulator).toContain(
      "buildDiagnosticSnapshot",
    );
    expect(simulator).toContain(
      "authoritativeStateStale",
    );
    expect(simulator).toContain(
      "recoveryRequired",
    );
  });

  it("documents PlatformIO and physical flashing as remaining hardware gates", () => {
    const readme = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/README.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(readme).toContain(
      "PlatformIO compilation and real ESP32 flashing",
    );
  });
});
