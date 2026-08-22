#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="13.4-device-ota-update-check-offer-binding"
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
  "$ROOT/apps/api/src/routes/scoreboardFirmwareReleases.ts" \
  "$ROOT/apps/api/src/routes/scoreboardFirmwareArtifacts.ts" \
  "$ROOT/apps/api/src/services/scoreboardDeviceEnrollment.ts" \
  "$ROOT/firmware/esp32-scoreboard/include/FirmwareUpdateContract.h" \
  "$ROOT/firmware/esp32-scoreboard/src/main.cpp"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

API_ROUTE="apps/api/src/routes/scoreboardFirmwareReleases.ts"
FW_H="firmware/esp32-scoreboard/include/FirmwareUpdateClient.h"
FW_CPP="firmware/esp32-scoreboard/src/FirmwareUpdateClient.cpp"
MAIN="firmware/esp32-scoreboard/src/main.cpp"
SIM="firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js"
SIM_TEST="firmware/esp32-scoreboard/simulator/test/ota-update-check.test.js"
README="firmware/esp32-scoreboard/README.md"
TEST="packages/core/test/device-ota-update-check-offer-binding-13.4.test.ts"

for file in "$API_ROUTE" "$FW_H" "$FW_CPP" "$MAIN" "$SIM" "$SIM_TEST" "$README" "$TEST"; do
  if [[ -f "$file" ]]; then
    rel="${file#$ROOT/}"
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$file" "$BACKUP_DIR/$rel"
  fi
done

mkdir -p \
  "$(dirname "$FW_H")" \
  "$(dirname "$FW_CPP")" \
  "$(dirname "$SIM_TEST")" \
  "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");
const file =
  "apps/api/src/routes/scoreboardFirmwareReleases.ts";

let text =
  fs.readFileSync(file, "utf8");

if (
  !text.includes(
    'isVerifiedDevice',
  )
) {
  const importLine =
    'import { isVerifiedDevice } from "../services/scoreboardDeviceEnrollment.js";';

  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate firmware release route import block.",
    );
  }

  text =
    text.replace(
      imports[0],
      imports[0] +
        importLine +
        "\n",
    );
}

if (
  !text.includes(
    "/scoreboard-firmware/device-offer",
  )
) {
  const end =
    text.lastIndexOf("\n}");

  if (end === -1) {
    throw new Error(
      "Unable to locate firmware release route function end.",
    );
  }

  const addition = `

  app.get(
    "/scoreboard-firmware/device-offer",
    async (request, reply) => {
      const query =
        request.query as {
          deviceId?: string;
          currentVersion?: string;
          channel?: FirmwareReleaseChannel;
          target?: FirmwareReleaseTarget;
        };

      if (
        !query.deviceId ||
        !query.currentVersion
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "deviceId and currentVersion are required.",
        });
      }

      if (
        !isVerifiedDevice(
          query.deviceId,
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Verified scoreboard device required.",
        });
      }

      const release =
        getLatestCompatibleFirmwareRelease({
          currentVersion:
            query.currentVersion,
          channel:
            query.channel ??
            "stable",
          target:
            query.target ??
            "esp32dev",
        });

      if (!release) {
        return {
          success: true,
          data: {
            updateAvailable: false,
            offer: null,
          },
        };
      }

      const artifactUrl =
        \`/scoreboard-firmware/releases/\${encodeURIComponent(
          release.releaseId,
        )}/artifact?deviceId=\${encodeURIComponent(
          query.deviceId,
        )}\`;

      return {
        success: true,
        data: {
          updateAvailable: true,
          offer: {
            deviceId:
              query.deviceId,
            currentVersion:
              query.currentVersion,
            release,
            artifactUrl,
          },
        },
      };
    },
  );
`;

  text =
    text.slice(0, end) +
    addition +
    text.slice(end);
}

fs.writeFileSync(file, text);
NODE

cat > "$FW_H" <<'EOF'
#pragma once

#include <Arduino.h>

#include "FirmwareUpdateContract.h"

namespace sportsos {

enum class FirmwareUpdateCheckState : uint8_t {
  Idle = 0,
  Checking,
  NoUpdate,
  UpdateAvailable,
  TransportError,
  InvalidOffer,
};

struct FirmwareUpdateClientConfig {
  const char* apiBaseUrl;
  const char* deviceId;
  const char* currentVersion;
  const char* channel;
  const char* target;
  uint32_t checkIntervalMs;
};

class FirmwareUpdateClient {
 public:
  explicit FirmwareUpdateClient(
      const FirmwareUpdateClientConfig& config);

  void begin();

  void loop(
      bool wifiConnected,
      bool enrollmentVerified);

  FirmwareUpdateCheckState state() const;

  bool updateAvailable() const;

  const FirmwareUpdateOffer& offer() const;

 private:
  FirmwareUpdateClientConfig config_;
  FirmwareUpdateCheckState state_;
  FirmwareUpdateOffer offer_;
  unsigned long lastCheckMs_;

  bool checkForUpdate();
  void clearOffer();
};

}  // namespace sportsos
EOF

cat > "$FW_CPP" <<'EOF'
#include "FirmwareUpdateClient.h"

#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <string.h>

namespace sportsos {

FirmwareUpdateClient::FirmwareUpdateClient(
    const FirmwareUpdateClientConfig& config)
    : config_(config),
      state_(FirmwareUpdateCheckState::Idle),
      lastCheckMs_(0) {
  clearOffer();
}

void FirmwareUpdateClient::begin() {
  state_ =
      FirmwareUpdateCheckState::Idle;
  lastCheckMs_ =
      0;
  clearOffer();
}

void FirmwareUpdateClient::loop(
    bool wifiConnected,
    bool enrollmentVerified) {
  if (
      !wifiConnected ||
      !enrollmentVerified
  ) {
    return;
  }

  const unsigned long nowMs =
      millis();

  if (
      lastCheckMs_ != 0 &&
      nowMs - lastCheckMs_ <
        config_.checkIntervalMs
  ) {
    return;
  }

  lastCheckMs_ =
      nowMs;

  if (!checkForUpdate()) {
    state_ =
        FirmwareUpdateCheckState::TransportError;
  }
}

FirmwareUpdateCheckState
FirmwareUpdateClient::state() const {
  return state_;
}

bool FirmwareUpdateClient::updateAvailable() const {
  return
      state_ ==
      FirmwareUpdateCheckState::UpdateAvailable;
}

const FirmwareUpdateOffer&
FirmwareUpdateClient::offer() const {
  return offer_;
}

bool FirmwareUpdateClient::checkForUpdate() {
  state_ =
      FirmwareUpdateCheckState::Checking;

  HTTPClient http;

  String url =
      String(config_.apiBaseUrl) +
      "/scoreboard-firmware/device-offer" +
      "?deviceId=" +
      config_.deviceId +
      "&currentVersion=" +
      config_.currentVersion +
      "&channel=" +
      config_.channel +
      "&target=" +
      config_.target;

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
    state_ =
        FirmwareUpdateCheckState::InvalidOffer;

    return true;
  }

  const bool available =
      document["data"]["updateAvailable"] |
      false;

  if (!available) {
    clearOffer();
    state_ =
        FirmwareUpdateCheckState::NoUpdate;

    return true;
  }

  const JsonObject offer =
      document["data"]["offer"];

  const JsonObject release =
      offer["release"];

  const char* releaseId =
      release["releaseId"] | "";

  const char* version =
      release["version"] | "";

  const char* artifactUrl =
      offer["artifactUrl"] | "";

  const char* sha256 =
      release["firmwareSha256"] | "";

  const uint32_t size =
      release["firmwareSizeBytes"] | 0;

  const bool mandatory =
      release["mandatory"] | false;

  clearOffer();

  strlcpy(
      offer_.releaseId,
      releaseId,
      sizeof(
        offer_.releaseId));

  strlcpy(
      offer_.version,
      version,
      sizeof(
        offer_.version));

  strlcpy(
      offer_.firmwareUrl,
      artifactUrl,
      sizeof(
        offer_.firmwareUrl));

  strlcpy(
      offer_.firmwareSha256,
      sha256,
      sizeof(
        offer_.firmwareSha256));

  offer_.firmwareSizeBytes =
      size;

  offer_.mandatory =
      mandatory;

  if (
      !FirmwareUpdateContract::validateOffer(
        offer_)
  ) {
    clearOffer();

    state_ =
        FirmwareUpdateCheckState::InvalidOffer;

    return true;
  }

  state_ =
      FirmwareUpdateCheckState::UpdateAvailable;

  return true;
}

void FirmwareUpdateClient::clearOffer() {
  memset(
      &offer_,
      0,
      sizeof(
        offer_));
}

}  // namespace sportsos
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "firmware/esp32-scoreboard/src/main.cpp";

let text =
  fs.readFileSync(file, "utf8");

if (
  !text.includes(
    '#include "FirmwareUpdateClient.h"',
  )
) {
  const anchor =
    '#include "EnrollmentClient.h"';

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate main.cpp EnrollmentClient include.",
    );
  }

  text =
    text.replace(
      anchor,
      anchor +
        '\n#include "FirmwareUpdateClient.h"',
    );
}

if (
  !text.includes(
    "using sportsos::FirmwareUpdateClient;",
  )
) {
  const anchor =
    "using sportsos::EnrollmentClientConfig;";

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate main.cpp using declarations.",
    );
  }

  text =
    text.replace(
      anchor,
      anchor +
        "\nusing sportsos::FirmwareUpdateClient;" +
        "\nusing sportsos::FirmwareUpdateClientConfig;",
    );
}

if (
  !text.includes(
    "FirmwareUpdateClient* firmwareUpdateClient",
  )
) {
  const anchor =
    "EnrollmentClient* enrollmentClient =";

  const idx =
    text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate enrollment client declaration.",
    );
  }

  const semicolon =
    text.indexOf(
      ";",
      idx,
    );

  if (semicolon === -1) {
    throw new Error(
      "Unable to locate enrollment client declaration end.",
    );
  }

  text =
    text.slice(0, semicolon + 1) +
    `

FirmwareUpdateClient* firmwareUpdateClient =
    nullptr;` +
    text.slice(semicolon + 1);
}

if (
  !text.includes(
    "SPORTSOS_FIRMWARE_VERSION",
  )
) {
  const anchor =
    "#ifndef SPORTSOS_API_BASE_URL";

  const idx =
    text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate SportsOS API macro.",
    );
  }

  const addition = `#ifndef SPORTSOS_FIRMWARE_VERSION
#define SPORTSOS_FIRMWARE_VERSION "0.13.4"
#endif

`;

  text =
    text.slice(0, idx) +
    addition +
    text.slice(idx);
}

if (
  !text.includes(
    "FirmwareUpdateClientConfig updateConfig",
  )
) {
  const anchor =
    "enrollmentClient->begin();";

  const idx =
    text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate enrollment client begin.",
    );
  }

  const insertAt =
    idx +
    anchor.length;

  const addition = `

  FirmwareUpdateClientConfig
      updateConfig{
          SPORTSOS_API_BASE_URL,
          persistedConfig.deviceId.c_str(),
          SPORTSOS_FIRMWARE_VERSION,
          "stable",
          "esp32dev",
          60000,
      };

  firmwareUpdateClient =
      new FirmwareUpdateClient(
          updateConfig);

  firmwareUpdateClient->begin();`;

  text =
    text.slice(0, insertAt) +
    addition +
    text.slice(insertAt);
}

if (
  !text.includes(
    "firmwareUpdateClient->loop",
  )
) {
  const anchor =
    "if (\n      runtimeStarted &&\n      runtime != nullptr\n  )";

  const idx =
    text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate runtime loop block.",
    );
  }

  const addition = `  if (
      firmwareUpdateClient != nullptr &&
      enrollmentClient != nullptr
  ) {
    firmwareUpdateClient->loop(
        WiFi.status() ==
          WL_CONNECTED,
        enrollmentClient->isVerified());
  }

`;

  text =
    text.slice(0, idx) +
    addition +
    text.slice(idx);
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file =
  "firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js";

let text =
  fs.readFileSync(file, "utf8");

if (
  !text.includes(
    "function evaluateFirmwareUpdateOffer",
  )
) {
  const anchor =
    "module.exports = {";

  if (!text.includes(anchor)) {
    throw new Error(
      "Simulator export anchor missing.",
    );
  }

  const helper = `
function evaluateFirmwareUpdateOffer({
  enrollmentStatus,
  currentVersion,
  release,
}) {
  if (enrollmentStatus !== "VERIFIED") {
    return {
      state: "BLOCKED_UNVERIFIED",
      updateAvailable: false,
    };
  }

  if (!release) {
    return {
      state: "NO_UPDATE",
      updateAvailable: false,
    };
  }

  if (
    !release.releaseId ||
    !release.version ||
    !release.firmwareSha256 ||
    release.firmwareSha256.length !== 64 ||
    !Number.isFinite(
      release.firmwareSizeBytes,
    ) ||
    release.firmwareSizeBytes <= 0
  ) {
    return {
      state: "INVALID_OFFER",
      updateAvailable: false,
    };
  }

  if (release.version === currentVersion) {
    return {
      state: "NO_UPDATE",
      updateAvailable: false,
    };
  }

  return {
    state: "UPDATE_AVAILABLE",
    updateAvailable: true,
    releaseId: release.releaseId,
    version: release.version,
  };
}

`;

  text =
    text.replace(
      anchor,
      helper +
        anchor,
    );

  const exportEnd =
    text.lastIndexOf("};");

  if (exportEnd === -1) {
    throw new Error(
      "Simulator export object end missing.",
    );
  }

  const before =
    text.slice(0, exportEnd);

  const after =
    text.slice(exportEnd);

  if (
    !before.includes(
      "evaluateFirmwareUpdateOffer,",
    )
  ) {
    text =
      before.replace(
        /(\n\s*)$/,
        "$1  evaluateFirmwareUpdateOffer,\n",
      ) +
      after;
  }
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
  evaluateFirmwareUpdateOffer,
} = require(
  "../firmware-behavior-simulator.js",
);

const validRelease = {
  releaseId: "esp32dev-0.13.4-test",
  version: "0.13.4",
  firmwareSha256:
    "a".repeat(64),
  firmwareSizeBytes: 123456,
};

test(
  "13.4 blocks update offers for unverified devices",
  () => {
    const result =
      evaluateFirmwareUpdateOffer({
        enrollmentStatus: "PENDING",
        currentVersion: "0.13.3",
        release: validRelease,
      });

    assert.equal(
      result.updateAvailable,
      false,
    );

    assert.equal(
      result.state,
      "BLOCKED_UNVERIFIED",
    );
  },
);

test(
  "13.4 accepts valid update offer for verified device",
  () => {
    const result =
      evaluateFirmwareUpdateOffer({
        enrollmentStatus: "VERIFIED",
        currentVersion: "0.13.3",
        release: validRelease,
      });

    assert.equal(
      result.updateAvailable,
      true,
    );

    assert.equal(
      result.state,
      "UPDATE_AVAILABLE",
    );
  },
);

test(
  "13.4 rejects malformed firmware offers",
  () => {
    const result =
      evaluateFirmwareUpdateOffer({
        enrollmentStatus: "VERIFIED",
        currentVersion: "0.13.3",
        release: {
          ...validRelease,
          firmwareSha256: "bad",
        },
      });

    assert.equal(
      result.state,
      "INVALID_OFFER",
    );
  },
);
EOF

cat >> "$README" <<'EOF'

## Milestone 13.4 — Device OTA update check / offer binding

Verified ESP32 scoreboards now have a firmware update-check client.

The firmware periodically calls:

`GET /scoreboard-firmware/device-offer`

with:

- device ID
- current firmware version
- release channel
- hardware target

The API:

- requires a verified device identity
- selects the latest compatible release
- returns a device-bound artifact URL
- returns no offer when the device is current

The ESP32 validates the received offer using the Milestone 13.1 firmware update contract.

This milestone **does not install OTA firmware yet**. It only discovers and validates available releases.

Default firmware check interval:

`60 seconds`

Default channel:

`stable`

Default target:

`esp32dev`
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.4 device OTA update check / offer binding", () => {
  it("adds a verified-device OTA offer endpoint", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareReleases.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/device-offer",
    );

    expect(routes).toContain(
      "isVerifiedDevice",
    );

    expect(routes).toContain(
      "Verified scoreboard device required.",
    );
  });

  it("returns a device-bound firmware artifact URL", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareReleases.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "artifactUrl",
    );

    expect(routes).toContain(
      "deviceId=",
    );
  });

  it("defines an ESP32 firmware update check client", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/FirmwareUpdateClient.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "FirmwareUpdateClient",
    );

    expect(header).toContain(
      "FirmwareUpdateCheckState",
    );
  });

  it("validates offers before marking an update available", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareUpdateClient.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "FirmwareUpdateContract::validateOffer",
    );

    expect(source).toContain(
      "UpdateAvailable",
    );
  });

  it("checks for updates only after enrollment verification", () => {
    const main = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/main.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(main).toContain(
      "firmwareUpdateClient->loop",
    );

    expect(main).toContain(
      "enrollmentClient->isVerified()",
    );
  });

  it("adds host simulator coverage for OTA offers", () => {
    const simulator = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js",
        import.meta.url,
      ),
      "utf8",
    );

    expect(simulator).toContain(
      "evaluateFirmwareUpdateOffer",
    );

    expect(simulator).toContain(
      "BLOCKED_UNVERIFIED",
    );

    expect(simulator).toContain(
      "UPDATE_AVAILABLE",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 13.4 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - verified-device OTA offer endpoint"
echo "  - latest compatible release binding"
echo "  - device-bound artifact URL"
echo "  - ESP32 FirmwareUpdateClient"
echo "  - 60-second update check interval"
echo "  - verified-enrollment gate"
echo "  - firmware offer validation"
echo "  - firmware simulator OTA-offer coverage"
echo "  - Milestone 13.4 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then firmware simulator:"
echo "  node --test firmware/esp32-scoreboard/simulator/test/*.test.js"
echo
echo "Next after green:"
echo "  Milestone 13.5 - ESP32 OTA Download / Integrity Verification"
