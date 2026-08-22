#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="11.10-firmware-diagnostics-hardware-closeout"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  echo "Expected: $EXPECTED_REAL" >&2
  echo "Received: $ROOT_REAL" >&2
  exit 1
fi

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/packages/core" \
  "$ROOT/firmware/esp32-scoreboard/include/ConnectivityWatchdog.h" \
  "$ROOT/firmware/esp32-scoreboard/include/ScoreboardRuntime.h" \
  "$ROOT/firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

FW_DIR="firmware/esp32-scoreboard"
DIAG_H="$FW_DIR/include/FirmwareDiagnostics.h"
DIAG_CPP="$FW_DIR/src/FirmwareDiagnostics.cpp"
CHECKLIST="$FW_DIR/HARDWARE-VALIDATION-CHECKLIST.md"
SIM="$FW_DIR/simulator/firmware-behavior-simulator.js"
SIM_TEST="$FW_DIR/simulator/test/firmware-diagnostics.test.js"
README="$FW_DIR/README.md"
TEST="packages/core/test/firmware-diagnostics-closeout-11.10.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$DIAG_H")" \
  "$BACKUP_DIR/$(dirname "$DIAG_CPP")" \
  "$BACKUP_DIR/$(dirname "$CHECKLIST")" \
  "$BACKUP_DIR/$(dirname "$SIM")" \
  "$BACKUP_DIR/$(dirname "$SIM_TEST")" \
  "$BACKUP_DIR/$(dirname "$README")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$DIAG_H")" \
  "$(dirname "$DIAG_CPP")" \
  "$(dirname "$SIM_TEST")" \
  "$(dirname "$TEST")"

for file in "$DIAG_H" "$DIAG_CPP" "$CHECKLIST" "$SIM" "$SIM_TEST" "$README" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$DIAG_H" <<'EOF'
#pragma once

#include <Arduino.h>

#include "ConnectivityWatchdog.h"
#include "ScoreboardProtocol.h"

namespace sportsos {

struct FirmwareDiagnosticSnapshot {
  uint32_t uptimeSeconds;
  int32_t wifiRssi;
  uint32_t freeHeapBytes;

  bool wifiConnected;
  bool mqttConnected;
  bool authoritativeStateStale;
  bool recoveryRequired;

  ConnectionState connectionState;
  ConnectivityHealth connectivityHealth;

  char deviceId[64];
  char gameId[64];
  bool hasGame;
};

class FirmwareDiagnostics {
 public:
  static FirmwareDiagnosticSnapshot build(
      const ScoreboardState& state,
      ConnectivityHealth health,
      bool wifiConnected,
      bool mqttConnected);

  static const char* connectionStateText(
      ConnectionState state);

  static const char* connectivityHealthText(
      ConnectivityHealth health);
};

}  // namespace sportsos
EOF

cat > "$DIAG_CPP" <<'EOF'
#include "FirmwareDiagnostics.h"

#include <WiFi.h>
#include <string.h>

namespace sportsos {

namespace {

void copyText(
    char* destination,
    size_t destinationSize,
    const char* source) {
  if (
      destination == nullptr ||
      destinationSize == 0
  ) {
    return;
  }

  if (source == nullptr) {
    destination[0] = '\0';
    return;
  }

  strncpy(
      destination,
      source,
      destinationSize - 1);

  destination[
      destinationSize - 1] = '\0';
}

}  // namespace

FirmwareDiagnosticSnapshot
FirmwareDiagnostics::build(
    const ScoreboardState& state,
    ConnectivityHealth health,
    bool wifiConnected,
    bool mqttConnected) {
  FirmwareDiagnosticSnapshot snapshot{};

  snapshot.uptimeSeconds =
      millis() / 1000UL;

  snapshot.wifiRssi =
      wifiConnected
          ? WiFi.RSSI()
          : 0;

  snapshot.freeHeapBytes =
      ESP.getFreeHeap();

  snapshot.wifiConnected =
      wifiConnected;

  snapshot.mqttConnected =
      mqttConnected;

  snapshot.authoritativeStateStale =
      health ==
      ConnectivityHealth::StaleAuthoritativeState;

  snapshot.recoveryRequired =
      health ==
      ConnectivityHealth::RecoveryRequired;

  snapshot.connectionState =
      state.connectionState;

  snapshot.connectivityHealth =
      health;

  copyText(
      snapshot.deviceId,
      sizeof(snapshot.deviceId),
      state.deviceId);

  snapshot.hasGame =
      state.hasGame;

  copyText(
      snapshot.gameId,
      sizeof(snapshot.gameId),
      state.hasGame
          ? state.gameId
          : "");

  return snapshot;
}

const char*
FirmwareDiagnostics::connectionStateText(
    ConnectionState state) {
  switch (state) {
    case ConnectionState::Offline:
      return "OFFLINE";
    case ConnectionState::Connecting:
      return "CONNECTING";
    case ConnectionState::Online:
      return "ONLINE";
    case ConnectionState::Degraded:
      return "DEGRADED";
    default:
      return "UNKNOWN";
  }
}

const char*
FirmwareDiagnostics::connectivityHealthText(
    ConnectivityHealth health) {
  switch (health) {
    case ConnectivityHealth::Healthy:
      return "HEALTHY";
    case ConnectivityHealth::WifiLost:
      return "WIFI_LOST";
    case ConnectivityHealth::MqttLost:
      return "MQTT_LOST";
    case ConnectivityHealth::StaleAuthoritativeState:
      return "STALE_AUTHORITATIVE_STATE";
    case ConnectivityHealth::RecoveryRequired:
      return "RECOVERY_REQUIRED";
    default:
      return "UNKNOWN";
  }
}

}  // namespace sportsos
EOF

cat > "$CHECKLIST" <<'EOF'
# SportsOS ESP32 Hardware Validation Checklist

Use this checklist before declaring a physical scoreboard device production-ready.

## 1. Power and boot

- ESP32 powers on reliably.
- Device does not enter a reboot loop.
- Serial boot output is readable.
- Provisioning AP appears when configuration is missing.
- Stored configuration survives power loss.

## 2. Local provisioning

- Setup AP name begins with `SportsOS-Scoreboard-`.
- Device ID can be saved.
- Wi-Fi SSID/password can be saved.
- MQTT host/port can be saved.
- Optional MQTT credentials can be saved.
- Stored passwords are not displayed back in the setup form.
- Reset clears local configuration.

## 3. Wi-Fi

- Device joins the configured local network.
- RSSI is visible through telemetry.
- Temporary Wi-Fi loss enters degraded/failsafe behavior.
- Wi-Fi recovery reconnects without manual restart.

## 4. MQTT

- Device subscribes to its command topic.
- Presence publishes online retained.
- MQTT last-will publishes offline retained.
- State publishes retained.
- Telemetry publishes non-retained.
- Acknowledgements publish for accepted/applied/rejected commands.
- MQTT reconnect restores command subscription.

## 5. Authoritative synchronization

- `SET_GAME` updates game assignment.
- `SET_SCORE` updates both scores.
- `SET_PERIOD` updates period.
- `SET_CLOCK` updates remaining time and running state.
- `HORN` toggles horn state.
- `SYNC_STATE` fully re-anchors device state.
- Reconnect causes the server to reconcile the device to current authoritative state.
- The device never invents score or period state while offline.

## 6. Clock behavior

- Running clock projects locally.
- Paused clock remains fixed.
- Clock stops at zero.
- Fresh server state re-anchors local clock projection.
- Stale-authoritative-state indication appears after the configured threshold.

## 7. Physical outputs

- Configured GPIO outputs initialize inactive.
- Horn output is inactive at boot.
- Status indicators match health state.
- Numeric display shows home score correctly.
- Numeric display shows away score correctly.
- Numeric display shows period correctly.
- Numeric display shows clock minutes/seconds correctly.

## 8. Fault recovery

- Wi-Fi loss is detected.
- MQTT loss is detected.
- Stale authoritative state is detected.
- Prolonged outage escalates to recovery-required.
- Restored connectivity clears the fault after authoritative state returns.

## 9. SportsOS integration

- Device appears on `/scoreboards/operations`.
- Device presence is ONLINE.
- Telemetry is visible.
- Game assignment is visible.
- Reconcile Now succeeds.
- Last acknowledgement is visible.
- Simulator and physical hardware produce equivalent state behavior.

## 10. Release gate

Do not mark physical firmware production-ready until:

- repository typecheck is green
- repository tests are green
- firmware behavior simulator tests are green
- actual firmware compiles with PlatformIO
- the target ESP32 board flashes successfully
- the physical checklist above passes on real hardware
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js";

let text =
  fs.readFileSync(file, "utf8");

if (!text.includes("function buildDiagnosticSnapshot")) {
  const exportAnchor =
    "module.exports = {";

  if (!text.includes(exportAnchor)) {
    throw new Error(
      "Simulator module export anchor missing.",
    );
  }

  const helper = `
function buildDiagnosticSnapshot({
  uptimeSeconds = 0,
  wifiRssi = 0,
  freeHeapBytes = 0,
  wifiConnected = false,
  mqttConnected = false,
  connectionState = "OFFLINE",
  connectivityHealth = "HEALTHY",
  deviceId = "",
  gameId = null,
}) {
  return {
    uptimeSeconds:
      clampNonNegativeInteger(uptimeSeconds),
    wifiRssi:
      Number.isFinite(wifiRssi)
        ? Math.trunc(wifiRssi)
        : 0,
    freeHeapBytes:
      clampNonNegativeInteger(freeHeapBytes),
    wifiConnected:
      Boolean(wifiConnected),
    mqttConnected:
      Boolean(mqttConnected),
    authoritativeStateStale:
      connectivityHealth ===
      "STALE_AUTHORITATIVE_STATE",
    recoveryRequired:
      connectivityHealth ===
      "RECOVERY_REQUIRED",
    connectionState,
    connectivityHealth,
    deviceId,
    gameId:
      gameId || null,
  };
}

`;

  text =
    text.replace(
      exportAnchor,
      helper + exportAnchor,
    );

  text =
    text.replace(
      "  tickFrame,\n};",
      "  tickFrame,\n  buildDiagnosticSnapshot,\n};",
    );
}

fs.writeFileSync(file, text);
NODE

cat > "$SIM_TEST" <<'EOF'
"use strict";

const test =
  require("node:test");

const assert =
  require("node:assert/strict");

const {
  buildDiagnosticSnapshot,
} = require(
  "../firmware-behavior-simulator.js",
);

test(
  "11.10 marks stale authoritative state",
  () => {
    const snapshot =
      buildDiagnosticSnapshot({
        uptimeSeconds: 120,
        wifiRssi: -61,
        freeHeapBytes: 180000,
        wifiConnected: true,
        mqttConnected: true,
        connectionState: "ONLINE",
        connectivityHealth:
          "STALE_AUTHORITATIVE_STATE",
        deviceId:
          "scoreboard-sim-1",
        gameId:
          "game-1",
      });

    assert.equal(
      snapshot.authoritativeStateStale,
      true,
    );

    assert.equal(
      snapshot.recoveryRequired,
      false,
    );
  },
);

test(
  "11.10 marks recovery-required fault state",
  () => {
    const snapshot =
      buildDiagnosticSnapshot({
        wifiConnected: false,
        mqttConnected: false,
        connectionState: "DEGRADED",
        connectivityHealth:
          "RECOVERY_REQUIRED",
        deviceId:
          "scoreboard-sim-1",
      });

    assert.equal(
      snapshot.recoveryRequired,
      true,
    );

    assert.equal(
      snapshot.wifiConnected,
      false,
    );

    assert.equal(
      snapshot.mqttConnected,
      false,
    );
  },
);
EOF

cat >> "$README" <<'EOF'

## Milestone 11.10 — Firmware diagnostics / hardware closeout

The firmware now exposes a common diagnostic snapshot containing:

- uptime
- Wi-Fi RSSI
- free heap
- Wi-Fi connectivity
- MQTT connectivity
- authoritative-state staleness
- recovery-required state
- protocol connection state
- connectivity watchdog health
- device ID
- current game assignment

A physical hardware validation checklist is included in `HARDWARE-VALIDATION-CHECKLIST.md`.

### Milestone 11 closeout status

Repository-side firmware architecture is now complete through:

- protocol state machine
- MQTT JSON codec
- Wi-Fi/MQTT runtime
- local provisioning
- connectivity watchdog
- display abstraction
- GPIO outputs
- hardware profiles
- numeric display layer
- seven-segment backend
- host-side behavior simulator
- firmware diagnostics

PlatformIO compilation and real ESP32 flashing remain the final hardware-specific validation steps.
EOF

cat > "$TEST" <<'EOF'
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
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 11.10 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - FirmwareDiagnostics"
echo "  - connection / watchdog diagnostic snapshot"
echo "  - Wi-Fi RSSI / heap / uptime diagnostics"
echo "  - stale / recovery fault reporting"
echo "  - hardware validation checklist"
echo "  - simulator diagnostic coverage"
echo "  - Milestone 11.10 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run repository validation:"
echo "  npm run typecheck && npm test"
echo
echo "Run firmware simulator validation:"
echo "  node --test firmware/esp32-scoreboard/simulator/test/*.test.js"
echo
echo "Milestone 11 closeout:"
echo "  If both commands are green, repository-side firmware is complete."
echo "  PlatformIO compilation + real ESP32 flashing remain the physical hardware gate."
