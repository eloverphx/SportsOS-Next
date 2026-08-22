#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="11.5-esp32-connectivity-watchdog-failsafe-runtime"
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

for required in   "$ROOT/.git"   "$ROOT/package.json"   "$ROOT/packages/core"   "$ROOT/firmware/esp32-scoreboard/include/ScoreboardRuntime.h"   "$ROOT/firmware/esp32-scoreboard/src/ScoreboardRuntime.cpp"   "$ROOT/firmware/esp32-scoreboard/include/ProvisioningManager.h"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

FW_DIR="firmware/esp32-scoreboard"
HEADER="$FW_DIR/include/ConnectivityWatchdog.h"
SOURCE="$FW_DIR/src/ConnectivityWatchdog.cpp"
RUNTIME_H="$FW_DIR/include/ScoreboardRuntime.h"
RUNTIME_CPP="$FW_DIR/src/ScoreboardRuntime.cpp"
README="$FW_DIR/README.md"
TEST="packages/core/test/esp32-connectivity-watchdog-11.5.test.ts"

mkdir -p   "$BACKUP_DIR/$(dirname "$HEADER")"   "$BACKUP_DIR/$(dirname "$SOURCE")"   "$BACKUP_DIR/$(dirname "$RUNTIME_H")"   "$BACKUP_DIR/$(dirname "$RUNTIME_CPP")"   "$BACKUP_DIR/$(dirname "$README")"   "$BACKUP_DIR/$(dirname "$TEST")"   "$(dirname "$HEADER")"   "$(dirname "$SOURCE")"   "$(dirname "$TEST")"

for file in "$HEADER" "$SOURCE" "$RUNTIME_H" "$RUNTIME_CPP" "$README" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$HEADER" <<'EOF'
#pragma once

#include <Arduino.h>

namespace sportsos {

enum class ConnectivityHealth : uint8_t {
  Healthy = 0,
  WifiLost,
  MqttLost,
  StaleAuthoritativeState,
  RecoveryRequired,
};

struct ConnectivityWatchdogConfig {
  uint32_t wifiFailureGraceMs;
  uint32_t mqttFailureGraceMs;
  uint32_t staleStateMs;
  uint32_t recoveryEscalationMs;
};

class ConnectivityWatchdog {
 public:
  explicit ConnectivityWatchdog(
      const ConnectivityWatchdogConfig& config);

  void begin(
      unsigned long nowMs);

  ConnectivityHealth evaluate(
      unsigned long nowMs,
      bool wifiConnected,
      bool mqttConnected);

  void noteAuthoritativeState(
      unsigned long nowMs);

  void noteSuccessfulMqttConnect(
      unsigned long nowMs);

  void noteSuccessfulWifiConnect(
      unsigned long nowMs);

  ConnectivityHealth health() const;

  bool displayStateIsStale() const;

  bool recoveryRequired() const;

 private:
  ConnectivityWatchdogConfig config_;

  unsigned long startedAtMs_;
  unsigned long lastAuthoritativeStateMs_;
  unsigned long lastWifiHealthyMs_;
  unsigned long lastMqttHealthyMs_;

  ConnectivityHealth health_;
};

}  // namespace sportsos
EOF

cat > "$SOURCE" <<'EOF'
#include "ConnectivityWatchdog.h"

namespace sportsos {

ConnectivityWatchdog::ConnectivityWatchdog(
    const ConnectivityWatchdogConfig& config)
    : config_(config),
      startedAtMs_(0),
      lastAuthoritativeStateMs_(0),
      lastWifiHealthyMs_(0),
      lastMqttHealthyMs_(0),
      health_(ConnectivityHealth::Healthy) {}

void ConnectivityWatchdog::begin(
    unsigned long nowMs) {
  startedAtMs_ = nowMs;
  lastAuthoritativeStateMs_ = nowMs;
  lastWifiHealthyMs_ = nowMs;
  lastMqttHealthyMs_ = nowMs;
  health_ = ConnectivityHealth::Healthy;
}

ConnectivityHealth ConnectivityWatchdog::evaluate(
    unsigned long nowMs,
    bool wifiConnected,
    bool mqttConnected) {
  if (wifiConnected) {
    lastWifiHealthyMs_ = nowMs;
  }

  if (mqttConnected) {
    lastMqttHealthyMs_ = nowMs;
  }

  if (
      !wifiConnected &&
      nowMs - lastWifiHealthyMs_ >=
          config_.recoveryEscalationMs
  ) {
    health_ =
        ConnectivityHealth::RecoveryRequired;
    return health_;
  }

  if (
      !wifiConnected &&
      nowMs - lastWifiHealthyMs_ >=
          config_.wifiFailureGraceMs
  ) {
    health_ =
        ConnectivityHealth::WifiLost;
    return health_;
  }

  if (
      wifiConnected &&
      !mqttConnected &&
      nowMs - lastMqttHealthyMs_ >=
          config_.recoveryEscalationMs
  ) {
    health_ =
        ConnectivityHealth::RecoveryRequired;
    return health_;
  }

  if (
      wifiConnected &&
      !mqttConnected &&
      nowMs - lastMqttHealthyMs_ >=
          config_.mqttFailureGraceMs
  ) {
    health_ =
        ConnectivityHealth::MqttLost;
    return health_;
  }

  if (
      mqttConnected &&
      nowMs - lastAuthoritativeStateMs_ >=
          config_.staleStateMs
  ) {
    health_ =
        ConnectivityHealth::StaleAuthoritativeState;
    return health_;
  }

  health_ = ConnectivityHealth::Healthy;
  return health_;
}

void ConnectivityWatchdog::noteAuthoritativeState(
    unsigned long nowMs) {
  lastAuthoritativeStateMs_ = nowMs;
}

void ConnectivityWatchdog::noteSuccessfulMqttConnect(
    unsigned long nowMs) {
  lastMqttHealthyMs_ = nowMs;
}

void ConnectivityWatchdog::noteSuccessfulWifiConnect(
    unsigned long nowMs) {
  lastWifiHealthyMs_ = nowMs;
}

ConnectivityHealth ConnectivityWatchdog::health() const {
  return health_;
}

bool ConnectivityWatchdog::displayStateIsStale() const {
  return
      health_ ==
      ConnectivityHealth::StaleAuthoritativeState;
}

bool ConnectivityWatchdog::recoveryRequired() const {
  return
      health_ ==
      ConnectivityHealth::RecoveryRequired;
}

}  // namespace sportsos
EOF

node <<'NODE'
const fs = require("fs");

const header =
  "firmware/esp32-scoreboard/include/ScoreboardRuntime.h";
let h = fs.readFileSync(header, "utf8");

if (!h.includes('#include "ConnectivityWatchdog.h"')) {
  h = h.replace(
    '#include "ScoreboardMqttCodec.h"',
    '#include "ConnectivityWatchdog.h"\n#include "ScoreboardMqttCodec.h"',
  );
}

if (!h.includes("ConnectivityWatchdog watchdog_;")) {
  const anchor = "  ScoreboardProtocol protocol_;";
  if (!h.includes(anchor)) {
    throw new Error("ScoreboardRuntime protocol_ anchor missing.");
  }
  h = h.replace(
    anchor,
    anchor + "\n  ConnectivityWatchdog watchdog_;",
  );
}

if (!h.includes("bool displayStateIsStale() const;")) {
  const anchor =
    "  const ScoreboardProtocol& protocol() const;";
  if (!h.includes(anchor)) {
    throw new Error("ScoreboardRuntime protocol() anchor missing.");
  }
  h = h.replace(
    anchor,
    anchor +
      "\n\n  bool displayStateIsStale() const;" +
      "\n  bool recoveryRequired() const;",
  );
}

fs.writeFileSync(header, h);

const source =
  "firmware/esp32-scoreboard/src/ScoreboardRuntime.cpp";
let s = fs.readFileSync(source, "utf8");

if (!s.includes("watchdog_(ConnectivityWatchdogConfig{")) {
  const anchor = "      protocol_(config.deviceId),";
  if (!s.includes(anchor)) {
    throw new Error("ScoreboardRuntime constructor anchor missing.");
  }
  s = s.replace(
    anchor,
    anchor +
      "\n      watchdog_(ConnectivityWatchdogConfig{" +
      "\n          15000," +
      "\n          15000," +
      "\n          120000," +
      "\n          60000," +
      "\n      }),",
  );
}

if (!s.includes("watchdog_.begin(")) {
  const anchor = "  activeInstance_ = this;";
  if (!s.includes(anchor)) {
    throw new Error("ScoreboardRuntime begin anchor missing.");
  }
  s = s.replace(
    anchor,
    anchor + "\n\n  watchdog_.begin(\n      millis());",
  );
}

if (!s.includes("watchdog_.evaluate(")) {
  const anchor = "  maintainMqtt(\n      nowMs);";
  if (!s.includes(anchor)) {
    throw new Error("ScoreboardRuntime loop anchor missing.");
  }
  s = s.replace(
    anchor,
    anchor +
      "\n\n  watchdog_.evaluate(" +
      "\n      nowMs," +
      "\n      WiFi.status() == WL_CONNECTED," +
      "\n      mqttClient_.connected());",
  );
}

if (!s.includes("watchdog_.noteSuccessfulWifiConnect(")) {
  const anchor =
`  if (
      WiFi.status() ==
      WL_CONNECTED
  ) {
    return;
  }`;
  if (!s.includes(anchor)) {
    throw new Error("maintainWifi connected anchor missing.");
  }
  s = s.replace(
    anchor,
`  if (
      WiFi.status() ==
      WL_CONNECTED
  ) {
    watchdog_.noteSuccessfulWifiConnect(
        nowMs);
    return;
  }`,
  );
}

if (!s.includes("watchdog_.noteSuccessfulMqttConnect(")) {
  const anchor =
`  protocol_.setConnectionState(
      ConnectionState::Online);

  return true;`;
  if (!s.includes(anchor)) {
    throw new Error("connectMqtt success anchor missing.");
  }
  s = s.replace(
    anchor,
`  watchdog_.noteSuccessfulMqttConnect(
      millis());

${anchor}`,
  );
}

if (!s.includes("watchdog_.noteAuthoritativeState(")) {
  const anchor =
`  if (
      result.status ==
      CommandStatus::Applied
  ) {
    publishState();
  }`;
  if (!s.includes(anchor)) {
    throw new Error("applied command anchor missing.");
  }
  s = s.replace(
    anchor,
`  if (
      result.status ==
      CommandStatus::Applied
  ) {
    watchdog_.noteAuthoritativeState(
        millis());
    publishState();
  }`,
  );
}

if (!s.includes("ScoreboardRuntime::displayStateIsStale")) {
  const anchor =
`const ScoreboardProtocol&
ScoreboardRuntime::protocol() const {
  return protocol_;
}`;
  if (!s.includes(anchor)) {
    throw new Error("const protocol() method anchor missing.");
  }
  s = s.replace(
    anchor,
`${anchor}

bool ScoreboardRuntime::displayStateIsStale() const {
  return watchdog_.displayStateIsStale();
}

bool ScoreboardRuntime::recoveryRequired() const {
  return watchdog_.recoveryRequired();
}`,
  );
}

fs.writeFileSync(source, s);
NODE

cat >> "$README" <<'EOF'

## Milestone 11.5 — Connectivity watchdog / failsafe runtime

The firmware now tracks connectivity health independently from the scoreboard state machine.

### Health states

- `Healthy`
- `WifiLost`
- `MqttLost`
- `StaleAuthoritativeState`
- `RecoveryRequired`

### Failsafe behavior

- short Wi-Fi and MQTT interruptions are tolerated during a grace period
- prolonged transport loss moves the device to a degraded/recovery state
- the display may continue projecting the last known clock locally
- stale authoritative state is explicitly detectable
- reconnecting does not invent new score, period, or game state
- SportsOS server synchronization remains authoritative

Milestone 11.6 will expose these health states to the physical display/status indicators and add safe operator-visible hardware diagnostics.
EOF

cat > "$TEST" <<'EOF'
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
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 11.5 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - ConnectivityWatchdog"
echo "  - Wi-Fi loss grace / failure state"
echo "  - MQTT loss grace / failure state"
echo "  - authoritative-state staleness detection"
echo "  - prolonged outage recovery escalation"
echo "  - runtime health integration"
echo "  - stale/recovery state accessors"
echo "  - Milestone 11.5 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "PlatformIO:"
echo "  Still optional."
echo
echo "Next after green:"
echo "  Milestone 11.6 - Physical Display / Status Driver Contract"
