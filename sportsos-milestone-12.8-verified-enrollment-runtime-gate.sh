#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="12.8-verified-enrollment-runtime-gate"
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
  "$ROOT/firmware/esp32-scoreboard/include/EnrollmentClient.h" \
  "$ROOT/firmware/esp32-scoreboard/include/ScoreboardRuntime.h" \
  "$ROOT/firmware/esp32-scoreboard/src/main.cpp"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

GATE_H="firmware/esp32-scoreboard/include/VerifiedRuntimeGate.h"
GATE_CPP="firmware/esp32-scoreboard/src/VerifiedRuntimeGate.cpp"
MAIN="firmware/esp32-scoreboard/src/main.cpp"
README="firmware/esp32-scoreboard/README.md"
SIM="firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js"
SIM_TEST="firmware/esp32-scoreboard/simulator/test/verified-runtime-gate.test.js"
TEST="packages/core/test/verified-enrollment-runtime-gate-12.8.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$GATE_H")" \
  "$BACKUP_DIR/$(dirname "$GATE_CPP")" \
  "$BACKUP_DIR/$(dirname "$MAIN")" \
  "$BACKUP_DIR/$(dirname "$README")" \
  "$BACKUP_DIR/$(dirname "$SIM")" \
  "$BACKUP_DIR/$(dirname "$SIM_TEST")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$GATE_H")" \
  "$(dirname "$GATE_CPP")" \
  "$(dirname "$SIM_TEST")" \
  "$(dirname "$TEST")"

for file in "$GATE_H" "$GATE_CPP" "$MAIN" "$README" "$SIM" "$SIM_TEST" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$GATE_H" <<'EOF'
#pragma once

#include <stdint.h>

#include "EnrollmentClient.h"

namespace sportsos {

enum class RuntimeGateState : uint8_t {
  WaitingForEnrollment = 0,
  Allowed,
  Rejected,
};

class VerifiedRuntimeGate {
 public:
  RuntimeGateState evaluate(
      EnrollmentClientState enrollmentState);

  RuntimeGateState state() const;

  bool allowAuthoritativeRuntime() const;

 private:
  RuntimeGateState state_ =
      RuntimeGateState::WaitingForEnrollment;
};

}  // namespace sportsos
EOF

cat > "$GATE_CPP" <<'EOF'
#include "VerifiedRuntimeGate.h"

namespace sportsos {

RuntimeGateState VerifiedRuntimeGate::evaluate(
    EnrollmentClientState enrollmentState) {
  switch (enrollmentState) {
    case EnrollmentClientState::Verified:
      state_ =
          RuntimeGateState::Allowed;
      break;

    case EnrollmentClientState::Rejected:
      state_ =
          RuntimeGateState::Rejected;
      break;

    case EnrollmentClientState::Idle:
    case EnrollmentClientState::Pending:
    case EnrollmentClientState::TransportError:
    default:
      state_ =
          RuntimeGateState::WaitingForEnrollment;
      break;
  }

  return state_;
}

RuntimeGateState
VerifiedRuntimeGate::state() const {
  return state_;
}

bool VerifiedRuntimeGate::
allowAuthoritativeRuntime() const {
  return
      state_ ==
      RuntimeGateState::Allowed;
}

}  // namespace sportsos
EOF

cat > "$MAIN" <<'EOF'
#include <Arduino.h>
#include <WiFi.h>

#include "DeviceEnrollment.h"
#include "EnrollmentClient.h"
#include "ProvisioningManager.h"
#include "ScoreboardRuntime.h"
#include "VerifiedRuntimeGate.h"

using sportsos::DeviceEnrollment;
using sportsos::DeviceEnrollmentIdentity;
using sportsos::EnrollmentClient;
using sportsos::EnrollmentClientConfig;
using sportsos::PersistedRuntimeConfig;
using sportsos::ProvisioningManager;
using sportsos::RuntimeConfig;
using sportsos::ScoreboardRuntime;
using sportsos::VerifiedRuntimeGate;

#ifndef SPORTSOS_API_BASE_URL
#define SPORTSOS_API_BASE_URL "http://192.168.5.3:4001"
#endif

ProvisioningManager provisioning;

ScoreboardRuntime* runtime =
    nullptr;

EnrollmentClient* enrollmentClient =
    nullptr;

VerifiedRuntimeGate runtimeGate;

bool runtimeStarted =
    false;

PersistedRuntimeConfig persistedConfig;

void startAuthoritativeRuntime() {
  if (runtimeStarted) {
    return;
  }

  RuntimeConfig runtimeConfig{
      persistedConfig.deviceId.c_str(),
      persistedConfig.wifiSsid.c_str(),
      persistedConfig.wifiPassword.c_str(),
      persistedConfig.mqttHost.c_str(),
      persistedConfig.mqttPort,
      persistedConfig.mqttUsername.c_str(),
      persistedConfig.mqttPassword.c_str(),
      5000,
      3000,
      30000,
  };

  runtime =
      new ScoreboardRuntime(
          runtimeConfig);

  runtime->begin();

  runtimeStarted =
      true;
}

void setup() {
  Serial.begin(
      115200);

  provisioning.begin();

  if (
      !provisioning.hasValidConfig()
  ) {
    return;
  }

  persistedConfig =
      provisioning.config();

  /*
   * Wi-Fi is required for enrollment transport, but authoritative
   * MQTT/game runtime is intentionally not started yet.
   */
  WiFi.mode(
      WIFI_STA);

  WiFi.begin(
      persistedConfig.wifiSsid.c_str(),
      persistedConfig.wifiPassword.c_str());

  const DeviceEnrollmentIdentity
      identity =
          DeviceEnrollment::buildIdentity(
              persistedConfig.deviceId.c_str());

  EnrollmentClientConfig
      enrollmentConfig{
          SPORTSOS_API_BASE_URL,
          10000,
      };

  enrollmentClient =
      new EnrollmentClient(
          enrollmentConfig,
          identity);

  enrollmentClient->begin();
}

void loop() {
  provisioning.loop();

  if (enrollmentClient != nullptr) {
    enrollmentClient->loop(
        WiFi.status() ==
        WL_CONNECTED);

    runtimeGate.evaluate(
        enrollmentClient->state());

    if (
        runtimeGate
          .allowAuthoritativeRuntime()
    ) {
      startAuthoritativeRuntime();
    }
  }

  if (
      runtimeStarted &&
      runtime != nullptr
  ) {
    runtime->loop();
  }

  delay(5);
}
EOF

node <<'NODE'
const fs = require("fs");
const file =
  "firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js";

let text =
  fs.readFileSync(file, "utf8");

if (!text.includes("function evaluateVerifiedRuntimeGate")) {
  const anchor =
    "module.exports = {";

  if (!text.includes(anchor)) {
    throw new Error(
      "Simulator export anchor missing.",
    );
  }

  const helper = `
function evaluateVerifiedRuntimeGate(
  enrollmentState,
) {
  if (enrollmentState === "VERIFIED") {
    return {
      state: "ALLOWED",
      allowAuthoritativeRuntime: true,
    };
  }

  if (enrollmentState === "REJECTED") {
    return {
      state: "REJECTED",
      allowAuthoritativeRuntime: false,
    };
  }

  return {
    state: "WAITING_FOR_ENROLLMENT",
    allowAuthoritativeRuntime: false,
  };
}

`;

  text =
    text.replace(
      anchor,
      helper + anchor,
    );

  text =
    text.replace(
      "  buildDiagnosticSnapshot,\n};",
      "  buildDiagnosticSnapshot,\n  evaluateVerifiedRuntimeGate,\n};",
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
  evaluateVerifiedRuntimeGate,
} = require(
  "../firmware-behavior-simulator.js",
);

test(
  "12.8 pending enrollment blocks authoritative runtime",
  () => {
    const result =
      evaluateVerifiedRuntimeGate(
        "PENDING",
      );

    assert.equal(
      result.allowAuthoritativeRuntime,
      false,
    );

    assert.equal(
      result.state,
      "WAITING_FOR_ENROLLMENT",
    );
  },
);

test(
  "12.8 verified enrollment allows authoritative runtime",
  () => {
    const result =
      evaluateVerifiedRuntimeGate(
        "VERIFIED",
      );

    assert.equal(
      result.allowAuthoritativeRuntime,
      true,
    );

    assert.equal(
      result.state,
      "ALLOWED",
    );
  },
);

test(
  "12.8 rejected enrollment permanently blocks authoritative runtime",
  () => {
    const result =
      evaluateVerifiedRuntimeGate(
        "REJECTED",
      );

    assert.equal(
      result.allowAuthoritativeRuntime,
      false,
    );

    assert.equal(
      result.state,
      "REJECTED",
    );
  },
);
EOF

cat >> "$README" <<'EOF'

## Milestone 12.8 — Verified enrollment runtime gate

The ESP32 firmware now separates:

- provisioning connectivity
- enrollment transport
- authoritative SportsOS scoreboard runtime

A newly configured device may join Wi-Fi and contact the enrollment API, but it does **not** start the normal MQTT/game runtime until the enrollment state is `VERIFIED`.

### Gate behavior

- `PENDING` → authoritative runtime blocked
- transport error → authoritative runtime blocked
- `VERIFIED` → authoritative runtime starts
- `REJECTED` → authoritative runtime remains blocked

This prevents a newly flashed or untrusted device from subscribing to live scoreboard commands before its physical identity has been reviewed and claimed in SportsOS.

The host-side firmware simulator includes the same runtime-gate behavior.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.8 verified enrollment runtime gate", () => {
  it("defines waiting allowed and rejected runtime states", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/VerifiedRuntimeGate.h",
        import.meta.url,
      ),
      "utf8",
    );

    for (const state of [
      "WaitingForEnrollment",
      "Allowed",
      "Rejected",
    ]) {
      expect(header).toContain(state);
    }
  });

  it("allows authoritative runtime only for verified enrollment", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/VerifiedRuntimeGate.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "EnrollmentClientState::Verified",
    );

    expect(source).toContain(
      "RuntimeGateState::Allowed",
    );

    expect(source).toContain(
      "allowAuthoritativeRuntime",
    );
  });

  it("keeps pending and transport-error devices blocked", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/VerifiedRuntimeGate.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "EnrollmentClientState::Pending",
    );

    expect(source).toContain(
      "EnrollmentClientState::TransportError",
    );

    expect(source).toContain(
      "WaitingForEnrollment",
    );
  });

  it("starts ScoreboardRuntime only through the verified gate", () => {
    const main = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/main.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(main).toContain(
      "runtimeGate",
    );

    expect(main).toContain(
      "allowAuthoritativeRuntime",
    );

    expect(main).toContain(
      "startAuthoritativeRuntime",
    );
  });

  it("adds equivalent host simulator gate behavior", () => {
    const simulator = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js",
        import.meta.url,
      ),
      "utf8",
    );

    expect(simulator).toContain(
      "evaluateVerifiedRuntimeGate",
    );

    expect(simulator).toContain(
      "WAITING_FOR_ENROLLMENT",
    );

    expect(simulator).toContain(
      "ALLOWED",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 12.8 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - VerifiedRuntimeGate"
echo "  - pending enrollment blocks authoritative runtime"
echo "  - transport errors block authoritative runtime"
echo "  - rejected enrollment blocks authoritative runtime"
echo "  - verified enrollment starts ScoreboardRuntime"
echo "  - Wi-Fi enrollment transport remains available before verification"
echo "  - host simulator runtime-gate coverage"
echo "  - Milestone 12.8 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then run firmware simulator:"
echo "  node --test firmware/esp32-scoreboard/simulator/test/*.test.js"
echo
echo "Next after green:"
echo "  Milestone 12.9 - Enrollment / Hardware Operations Integration"
