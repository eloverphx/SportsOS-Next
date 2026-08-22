#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="12.7-first-boot-enrollment-transport-binding"
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
  "$ROOT/firmware/esp32-scoreboard/include/DeviceEnrollment.h" \
  "$ROOT/firmware/esp32-scoreboard/include/ScoreboardRuntime.h" \
  "$ROOT/firmware/esp32-scoreboard/src/main.cpp"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

FW_DIR="firmware/esp32-scoreboard"
CLIENT_H="$FW_DIR/include/EnrollmentClient.h"
CLIENT_CPP="$FW_DIR/src/EnrollmentClient.cpp"
MAIN="$FW_DIR/src/main.cpp"
PLATFORMIO="$FW_DIR/platformio.ini"
README="$FW_DIR/README.md"
TEST="packages/core/test/first-boot-enrollment-transport-binding-12.7.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$CLIENT_H")" \
  "$BACKUP_DIR/$(dirname "$CLIENT_CPP")" \
  "$BACKUP_DIR/$(dirname "$MAIN")" \
  "$BACKUP_DIR/$(dirname "$PLATFORMIO")" \
  "$BACKUP_DIR/$(dirname "$README")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$CLIENT_H")" \
  "$(dirname "$CLIENT_CPP")" \
  "$(dirname "$TEST")"

for file in "$CLIENT_H" "$CLIENT_CPP" "$MAIN" "$PLATFORMIO" "$README" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$CLIENT_H" <<'EOF'
#pragma once

#include <Arduino.h>

#include "DeviceEnrollment.h"

namespace sportsos {

enum class EnrollmentClientState : uint8_t {
  Idle = 0,
  Pending,
  Verified,
  Rejected,
  TransportError,
};

struct EnrollmentClientConfig {
  const char* apiBaseUrl;
  uint32_t retryIntervalMs;
};

class EnrollmentClient {
 public:
  EnrollmentClient(
      const EnrollmentClientConfig& config,
      const DeviceEnrollmentIdentity& identity);

  void begin();

  void loop(
      bool wifiConnected);

  EnrollmentClientState state() const;

  bool isVerified() const;

  bool isRejected() const;

 private:
  EnrollmentClientConfig config_;
  DeviceEnrollmentIdentity identity_;

  EnrollmentClientState state_;
  unsigned long lastAttemptMs_;

  bool submitFirstBoot();

  bool refreshStatus();

  void applyServerStatus(
      const String& status);
};

}  // namespace sportsos
EOF

cat > "$CLIENT_CPP" <<'EOF'
#include "EnrollmentClient.h"

#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <WiFi.h>

namespace sportsos {

EnrollmentClient::EnrollmentClient(
    const EnrollmentClientConfig& config,
    const DeviceEnrollmentIdentity& identity)
    : config_(config),
      identity_(identity),
      state_(EnrollmentClientState::Idle),
      lastAttemptMs_(0) {}

void EnrollmentClient::begin() {
  state_ =
      EnrollmentClientState::Pending;

  lastAttemptMs_ = 0;
}

void EnrollmentClient::loop(
    bool wifiConnected) {
  if (!wifiConnected) {
    return;
  }

  if (
      state_ ==
      EnrollmentClientState::Verified ||
      state_ ==
      EnrollmentClientState::Rejected
  ) {
    return;
  }

  const unsigned long nowMs =
      millis();

  if (
      lastAttemptMs_ != 0 &&
      nowMs - lastAttemptMs_ <
          config_.retryIntervalMs
  ) {
    return;
  }

  lastAttemptMs_ =
      nowMs;

  if (
      state_ ==
      EnrollmentClientState::Idle ||
      state_ ==
      EnrollmentClientState::Pending ||
      state_ ==
      EnrollmentClientState::TransportError
  ) {
    if (!submitFirstBoot()) {
      state_ =
          EnrollmentClientState::TransportError;

      return;
    }

    refreshStatus();
  }
}

EnrollmentClientState
EnrollmentClient::state() const {
  return state_;
}

bool EnrollmentClient::isVerified() const {
  return
      state_ ==
      EnrollmentClientState::Verified;
}

bool EnrollmentClient::isRejected() const {
  return
      state_ ==
      EnrollmentClientState::Rejected;
}

bool EnrollmentClient::submitFirstBoot() {
  HTTPClient http;

  const String url =
      String(config_.apiBaseUrl) +
      "/scoreboard-devices/enrollment/first-boot";

  if (!http.begin(url)) {
    return false;
  }

  http.addHeader(
      "Content-Type",
      "application/json");

  const String payload =
      DeviceEnrollment::buildFirstBootJson(
          identity_);

  const int status =
      http.POST(payload);

  const String response =
      http.getString();

  http.end();

  if (
      status < 200 ||
      status >= 300
  ) {
    return false;
  }

  JsonDocument document;

  if (
      deserializeJson(
          document,
          response)
  ) {
    return false;
  }

  const char* enrollmentStatus =
      document["data"]["status"] | "";

  applyServerStatus(
      String(enrollmentStatus));

  return true;
}

bool EnrollmentClient::refreshStatus() {
  HTTPClient http;

  const String url =
      String(config_.apiBaseUrl) +
      "/scoreboard-devices/enrollment/" +
      identity_.deviceId;

  if (!http.begin(url)) {
    return false;
  }

  const int status =
      http.GET();

  const String response =
      http.getString();

  http.end();

  if (
      status < 200 ||
      status >= 300
  ) {
    return false;
  }

  JsonDocument document;

  if (
      deserializeJson(
          document,
          response)
  ) {
    return false;
  }

  const char* enrollmentStatus =
      document["data"]["status"] | "";

  applyServerStatus(
      String(enrollmentStatus));

  return true;
}

void EnrollmentClient::applyServerStatus(
    const String& status) {
  if (status == "VERIFIED") {
    state_ =
        EnrollmentClientState::Verified;

    return;
  }

  if (status == "REJECTED") {
    state_ =
        EnrollmentClientState::Rejected;

    return;
  }

  state_ =
      EnrollmentClientState::Pending;
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

using sportsos::DeviceEnrollment;
using sportsos::DeviceEnrollmentIdentity;
using sportsos::EnrollmentClient;
using sportsos::EnrollmentClientConfig;
using sportsos::PersistedRuntimeConfig;
using sportsos::ProvisioningManager;
using sportsos::RuntimeConfig;
using sportsos::ScoreboardRuntime;

#ifndef SPORTSOS_API_BASE_URL
#define SPORTSOS_API_BASE_URL "http://192.168.5.3:4001"
#endif

ProvisioningManager provisioning;

ScoreboardRuntime* runtime =
    nullptr;

EnrollmentClient* enrollmentClient =
    nullptr;

void setup() {
  Serial.begin(
      115200);

  provisioning.begin();

  if (
      !provisioning.hasValidConfig()
  ) {
    return;
  }

  const PersistedRuntimeConfig&
      persisted =
          provisioning.config();

  RuntimeConfig runtimeConfig{
      persisted.deviceId.c_str(),
      persisted.wifiSsid.c_str(),
      persisted.wifiPassword.c_str(),
      persisted.mqttHost.c_str(),
      persisted.mqttPort,
      persisted.mqttUsername.c_str(),
      persisted.mqttPassword.c_str(),
      5000,
      3000,
      30000,
  };

  runtime =
      new ScoreboardRuntime(
          runtimeConfig);

  runtime->begin();

  const DeviceEnrollmentIdentity
      identity =
          DeviceEnrollment::buildIdentity(
              persisted.deviceId.c_str());

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

  if (runtime != nullptr) {
    runtime->loop();
  }

  if (enrollmentClient != nullptr) {
    enrollmentClient->loop(
        WiFi.status() ==
        WL_CONNECTED);
  }

  delay(5);
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "firmware/esp32-scoreboard/platformio.ini";

let text =
  fs.readFileSync(file, "utf8");

if (
  !text.includes(
    "SPORTSOS_API_BASE_URL",
  )
) {
  text += `

; SportsOS API used for first-boot enrollment.
; Override for the deployment network as needed.
; -D SPORTSOS_API_BASE_URL=\\"http://192.168.5.3:4001\\"
`;
}

fs.writeFileSync(file, text);
NODE

cat >> "$README" <<'EOF'

## Milestone 12.7 — First-boot enrollment transport binding

The ESP32 runtime now actively registers its first-boot identity with SportsOS.

### Runtime flow

After provisioning and Wi-Fi connection:

1. firmware builds its device identity
2. ESP32 POSTs identity to:
   `POST /scoreboard-devices/enrollment/first-boot`
3. ESP32 reads the returned enrollment state
4. firmware periodically refreshes:
   `GET /scoreboard-devices/enrollment/:deviceId`
5. `PENDING` devices retry safely
6. `VERIFIED` devices stop enrollment polling
7. `REJECTED` devices stop enrollment polling
8. transport failures retry after a configured interval

The default local API base URL is:

`http://192.168.5.3:4001`

It can be overridden at firmware build time using `SPORTSOS_API_BASE_URL`.

This milestone binds the previously separate firmware identity contract to the SportsOS enrollment API.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.7 first-boot enrollment transport", () => {
  it("defines an enrollment HTTP client", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/EnrollmentClient.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "EnrollmentClient",
    );

    expect(header).toContain(
      "EnrollmentClientState",
    );
  });

  it("posts first-boot identity to the SportsOS API", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/EnrollmentClient.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "/scoreboard-devices/enrollment/first-boot",
    );

    expect(source).toContain(
      "http.POST",
    );

    expect(source).toContain(
      "buildFirstBootJson",
    );
  });

  it("polls enrollment status until verified or rejected", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/EnrollmentClient.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      '"VERIFIED"',
    );

    expect(source).toContain(
      '"REJECTED"',
    );

    expect(source).toContain(
      "retryIntervalMs",
    );
  });

  it("binds enrollment client into firmware main loop", () => {
    const main = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/main.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(main).toContain(
      "EnrollmentClient",
    );

    expect(main).toContain(
      "enrollmentClient->loop",
    );
  });

  it("defines a configurable local API base URL", () => {
    const main = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/main.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(main).toContain(
      "SPORTSOS_API_BASE_URL",
    );

    expect(main).toContain(
      "http://192.168.5.3:4001",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 12.7 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - EnrollmentClient"
echo "  - first-boot HTTP registration"
echo "  - enrollment status polling"
echo "  - pending retry behavior"
echo "  - verified/rejected terminal states"
echo "  - transport retry behavior"
echo "  - configurable SportsOS API base URL"
echo "  - firmware main-loop binding"
echo "  - Milestone 12.7 tests"
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
echo "  Milestone 12.8 - Verified Enrollment Runtime Gate"
