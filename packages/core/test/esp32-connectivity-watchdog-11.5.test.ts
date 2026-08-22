import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.5 ESP32 connectivity watchdog", () => {
  it("defines connectivity health states", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ConnectivityWatchdog.h",
        import.meta.url,
      ),
      "utf8",
    );

    for (const state of [
      "Healthy",
      "WifiLost",
      "MqttLost",
      "StaleAuthoritativeState",
      "RecoveryRequired",
    ]) {
      expect(header).toContain(state);
    }
  });

  it("tracks authoritative state freshness", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ConnectivityWatchdog.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "lastAuthoritativeStateMs_",
    );
    expect(source).toContain(
      "config_.staleStateMs",
    );
    expect(source).toContain(
      "StaleAuthoritativeState",
    );
  });

  it("escalates prolonged connectivity loss to recovery", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ConnectivityWatchdog.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "config_.recoveryEscalationMs",
    );
    expect(source).toContain(
      "ConnectivityHealth::RecoveryRequired",
    );
  });

  it("integrates watchdog evaluation into ScoreboardRuntime", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardRuntime.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "watchdog_.evaluate",
    );
    expect(source).toContain(
      "watchdog_.noteSuccessfulWifiConnect",
    );
    expect(source).toContain(
      "watchdog_.noteSuccessfulMqttConnect",
    );
    expect(source).toContain(
      "watchdog_.noteAuthoritativeState",
    );
  });

  it("exposes stale and recovery state without inventing game state", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardRuntime.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "bool displayStateIsStale() const;",
    );
    expect(header).toContain(
      "bool recoveryRequired() const;",
    );
  });
});
