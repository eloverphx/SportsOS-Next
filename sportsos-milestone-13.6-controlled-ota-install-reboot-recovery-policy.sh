#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="13.6-controlled-ota-install-reboot-recovery-policy"
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
  "$ROOT/firmware/esp32-scoreboard/include/FirmwareUpdateClient.h" \
  "$ROOT/firmware/esp32-scoreboard/include/FirmwareUpdateDownloader.h" \
  "$ROOT/firmware/esp32-scoreboard/src/FirmwareUpdateClient.cpp" \
  "$ROOT/firmware/esp32-scoreboard/src/main.cpp"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

POLICY_H="firmware/esp32-scoreboard/include/FirmwareInstallPolicy.h"
POLICY_CPP="firmware/esp32-scoreboard/src/FirmwareInstallPolicy.cpp"
BOOT_H="firmware/esp32-scoreboard/include/FirmwareBootHealth.h"
BOOT_CPP="firmware/esp32-scoreboard/src/FirmwareBootHealth.cpp"
MAIN="firmware/esp32-scoreboard/src/main.cpp"
SIM="firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js"
SIM_TEST="firmware/esp32-scoreboard/simulator/test/ota-install-recovery-policy.test.js"
README="firmware/esp32-scoreboard/README.md"
TEST="packages/core/test/controlled-ota-install-reboot-recovery-policy-13.6.test.ts"

for file in "$POLICY_H" "$POLICY_CPP" "$BOOT_H" "$BOOT_CPP" "$MAIN" "$SIM" "$SIM_TEST" "$README" "$TEST"; do
  if [[ -f "$file" ]]; then
    rel="${file#$ROOT/}"
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$file" "$BACKUP_DIR/$rel"
  fi
done

mkdir -p \
  "$(dirname "$POLICY_H")" \
  "$(dirname "$POLICY_CPP")" \
  "$(dirname "$BOOT_H")" \
  "$(dirname "$BOOT_CPP")" \
  "$(dirname "$SIM_TEST")" \
  "$(dirname "$TEST")"

cat > "$POLICY_H" <<'EOF'
#pragma once

#include <Arduino.h>

#include "FirmwareUpdateClient.h"

namespace sportsos {

enum class FirmwareInstallDecision : uint8_t {
  NotReady = 0,
  WaitForIdle,
  ReadyToInstall,
  BlockedUnverified,
  BlockedRuntimeUnsafe,
};

struct FirmwareInstallPolicyInput {
  bool enrollmentVerified;
  bool runtimeActive;
  bool gameInProgress;
  bool updateAvailable;
  bool stagedSuccessfully;
  bool mandatory;
};

class FirmwareInstallPolicy {
 public:
  static FirmwareInstallDecision evaluate(
      const FirmwareInstallPolicyInput& input);
};

}  // namespace sportsos
EOF

cat > "$POLICY_CPP" <<'EOF'
#include "FirmwareInstallPolicy.h"

namespace sportsos {

FirmwareInstallDecision
FirmwareInstallPolicy::evaluate(
    const FirmwareInstallPolicyInput& input) {
  if (!input.enrollmentVerified) {
    return
        FirmwareInstallDecision::BlockedUnverified;
  }

  if (
      input.runtimeActive &&
      input.gameInProgress
  ) {
    return
        FirmwareInstallDecision::WaitForIdle;
  }

  if (
      !input.updateAvailable ||
      !input.stagedSuccessfully
  ) {
    return
        FirmwareInstallDecision::NotReady;
  }

  if (
      input.runtimeActive &&
      !input.mandatory
  ) {
    return
        FirmwareInstallDecision::BlockedRuntimeUnsafe;
  }

  return
      FirmwareInstallDecision::ReadyToInstall;
}

}  // namespace sportsos
EOF

cat > "$BOOT_H" <<'EOF'
#pragma once

#include <Arduino.h>

namespace sportsos {

enum class BootHealthState : uint8_t {
  Unknown = 0,
  PendingValidation,
  Healthy,
  Failed,
};

class FirmwareBootHealth {
 public:
  FirmwareBootHealth();

  void begin();

  void markPendingValidation();

  void confirmHealthy();

  void markFailed();

  BootHealthState state() const;

  bool requiresValidation() const;

 private:
  BootHealthState state_;
};

}  // namespace sportsos
EOF

cat > "$BOOT_CPP" <<'EOF'
#include "FirmwareBootHealth.h"

#include <Preferences.h>

namespace sportsos {

namespace {
Preferences prefs;

constexpr const char* NAMESPACE_NAME =
    "sportsos-ota";

constexpr const char* KEY_PENDING =
    "pending";

constexpr const char* KEY_FAILED =
    "failed";
}  // namespace

FirmwareBootHealth::FirmwareBootHealth()
    : state_(BootHealthState::Unknown) {}

void FirmwareBootHealth::begin() {
  prefs.begin(
      NAMESPACE_NAME,
      false);

  const bool failed =
      prefs.getBool(
          KEY_FAILED,
          false);

  const bool pending =
      prefs.getBool(
          KEY_PENDING,
          false);

  if (failed) {
    state_ =
        BootHealthState::Failed;
    return;
  }

  if (pending) {
    state_ =
        BootHealthState::PendingValidation;
    return;
  }

  state_ =
      BootHealthState::Healthy;
}

void FirmwareBootHealth::markPendingValidation() {
  prefs.putBool(
      KEY_PENDING,
      true);

  prefs.putBool(
      KEY_FAILED,
      false);

  state_ =
      BootHealthState::PendingValidation;
}

void FirmwareBootHealth::confirmHealthy() {
  prefs.putBool(
      KEY_PENDING,
      false);

  prefs.putBool(
      KEY_FAILED,
      false);

  state_ =
      BootHealthState::Healthy;
}

void FirmwareBootHealth::markFailed() {
  prefs.putBool(
      KEY_FAILED,
      true);

  state_ =
      BootHealthState::Failed;
}

BootHealthState
FirmwareBootHealth::state() const {
  return state_;
}

bool FirmwareBootHealth::requiresValidation() const {
  return
      state_ ==
      BootHealthState::PendingValidation;
}

}  // namespace sportsos
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "firmware/esp32-scoreboard/src/main.cpp";

let text =
  fs.readFileSync(file, "utf8");

for (const includeLine of [
  '#include "FirmwareBootHealth.h"',
  '#include "FirmwareInstallPolicy.h"',
]) {
  if (!text.includes(includeLine)) {
    const anchor =
      '#include "FirmwareUpdateClient.h"';

    if (!text.includes(anchor)) {
      throw new Error(
        "Unable to locate FirmwareUpdateClient include.",
      );
    }

    text =
      text.replace(
        anchor,
        anchor +
          "\n" +
          includeLine,
      );
  }
}

for (const usingLine of [
  "using sportsos::FirmwareBootHealth;",
  "using sportsos::FirmwareInstallDecision;",
  "using sportsos::FirmwareInstallPolicy;",
  "using sportsos::FirmwareInstallPolicyInput;",
]) {
  if (!text.includes(usingLine)) {
    const anchor =
      "using sportsos::FirmwareUpdateClientConfig;";

    if (!text.includes(anchor)) {
      throw new Error(
        "Unable to locate firmware update using declarations.",
      );
    }

    text =
      text.replace(
        anchor,
        anchor +
          "\n" +
          usingLine,
      );
  }
}

if (
  !text.includes(
    "FirmwareBootHealth bootHealth;",
  )
) {
  const anchor =
    "VerifiedRuntimeGate runtimeGate;";

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate runtime gate declaration.",
    );
  }

  text =
    text.replace(
      anchor,
      anchor +
        "\n\nFirmwareBootHealth bootHealth;",
    );
}

if (
  !text.includes(
    "bootHealth.begin();",
  )
) {
  const anchor =
    "Serial.begin(\n      115200);";

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate setup serial initialization.",
    );
  }

  text =
    text.replace(
      anchor,
      anchor +
        "\n\n  bootHealth.begin();",
    );
}

if (
  !text.includes(
    "bootHealth.confirmHealthy();",
  )
) {
  const anchor =
    "runtimeStarted =\n      true;";

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate authoritative runtime start marker.",
    );
  }

  text =
    text.replace(
      anchor,
      anchor +
        `

  if (
      bootHealth.requiresValidation()
  ) {
    bootHealth.confirmHealthy();
  }`,
    );
}

if (
  !text.includes(
    "FirmwareInstallPolicy::evaluate",
  )
) {
  const anchor =
`  if (
      runtimeStarted &&
      runtime != nullptr
  ) {
    runtime->loop();
  }`;

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate runtime loop block for OTA policy insertion.",
    );
  }

  const addition = `

  if (
      firmwareUpdateClient != nullptr &&
      enrollmentClient != nullptr &&
      firmwareUpdateClient->updateAvailable()
  ) {
    const auto& progress =
        firmwareUpdateClient->downloadProgress();

    const bool staged =
        progress.state ==
        sportsos::FirmwareUpdateState::ReadyToInstall;

    const FirmwareInstallPolicyInput
        policyInput{
            enrollmentClient->isVerified(),
            runtimeStarted,
            false,
            firmwareUpdateClient->updateAvailable(),
            staged,
            firmwareUpdateClient->offer().mandatory,
        };

    const auto decision =
        FirmwareInstallPolicy::evaluate(
            policyInput);

    if (
        decision ==
        FirmwareInstallDecision::ReadyToInstall
    ) {
      bootHealth.markPendingValidation();

      delay(100);

      ESP.restart();
    }
  }`;

  text =
    text.replace(
      anchor,
      anchor +
        addition,
    );
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
    "function evaluateFirmwareInstallPolicy",
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
function evaluateFirmwareInstallPolicy({
  enrollmentVerified,
  runtimeActive,
  gameInProgress,
  updateAvailable,
  stagedSuccessfully,
  mandatory,
}) {
  if (!enrollmentVerified) {
    return "BLOCKED_UNVERIFIED";
  }

  if (runtimeActive && gameInProgress) {
    return "WAIT_FOR_IDLE";
  }

  if (!updateAvailable || !stagedSuccessfully) {
    return "NOT_READY";
  }

  if (runtimeActive && !mandatory) {
    return "BLOCKED_RUNTIME_UNSAFE";
  }

  return "READY_TO_INSTALL";
}

function evaluateBootHealth({
  pendingValidation,
  failed,
}) {
  if (failed) {
    return "FAILED";
  }

  if (pendingValidation) {
    return "PENDING_VALIDATION";
  }

  return "HEALTHY";
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

  let before =
    text.slice(0, exportEnd);

  const after =
    text.slice(exportEnd);

  for (const name of [
    "evaluateFirmwareInstallPolicy",
    "evaluateBootHealth",
  ]) {
    if (
      !before.includes(
        `${name},`,
      )
    ) {
      before =
        before.replace(
          /(\n\s*)$/,
          `$1  ${name},\n`,
        );
    }
  }

  text =
    before +
    after;
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
  evaluateBootHealth,
  evaluateFirmwareInstallPolicy,
} = require(
  "../firmware-behavior-simulator.js",
);

test(
  "13.6 blocks install for unverified devices",
  () => {
    assert.equal(
      evaluateFirmwareInstallPolicy({
        enrollmentVerified: false,
        runtimeActive: false,
        gameInProgress: false,
        updateAvailable: true,
        stagedSuccessfully: true,
        mandatory: false,
      }),
      "BLOCKED_UNVERIFIED",
    );
  },
);

test(
  "13.6 waits for idle during a live game",
  () => {
    assert.equal(
      evaluateFirmwareInstallPolicy({
        enrollmentVerified: true,
        runtimeActive: true,
        gameInProgress: true,
        updateAvailable: true,
        stagedSuccessfully: true,
        mandatory: true,
      }),
      "WAIT_FOR_IDLE",
    );
  },
);

test(
  "13.6 allows install after staging when safe",
  () => {
    assert.equal(
      evaluateFirmwareInstallPolicy({
        enrollmentVerified: true,
        runtimeActive: false,
        gameInProgress: false,
        updateAvailable: true,
        stagedSuccessfully: true,
        mandatory: false,
      }),
      "READY_TO_INSTALL",
    );
  },
);

test(
  "13.6 reports pending boot validation",
  () => {
    assert.equal(
      evaluateBootHealth({
        pendingValidation: true,
        failed: false,
      }),
      "PENDING_VALIDATION",
    );
  },
);
EOF

cat >> "$README" <<'EOF'

## Milestone 13.6 — Controlled OTA install / reboot / recovery policy

SportsOS now separates OTA staging from installation.

Installation policy requires:

- verified enrollment
- an available update
- successful binary staging/integrity verification
- no active live-game risk

The firmware marks the next boot as requiring validation before rebooting into the staged image.

Boot-health states:

- `PENDING_VALIDATION`
- `HEALTHY`
- `FAILED`

After the new firmware boots and authoritative runtime starts successfully, it confirms the boot healthy.

This gives SportsOS a foundation for controlled OTA activation and future rollback handling instead of treating every successful download as a successful deployment.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.6 controlled OTA install / reboot / recovery policy", () => {
  it("defines controlled firmware install policy", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/FirmwareInstallPolicy.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "FirmwareInstallDecision",
    );

    expect(header).toContain(
      "ReadyToInstall",
    );

    expect(header).toContain(
      "WaitForIdle",
    );
  });

  it("blocks unverified and unsafe runtime installs", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareInstallPolicy.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "BlockedUnverified",
    );

    expect(source).toContain(
      "BlockedRuntimeUnsafe",
    );
  });

  it("tracks pending boot validation", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareBootHealth.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "PendingValidation",
    );

    expect(source).toContain(
      "confirmHealthy",
    );

    expect(source).toContain(
      "Preferences",
    );
  });

  it("marks pending validation before restart", () => {
    const main = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/main.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    const pending =
      main.indexOf(
        "bootHealth.markPendingValidation()",
      );

    const restart =
      main.indexOf(
        "ESP.restart()",
      );

    expect(pending).toBeGreaterThan(
      -1,
    );

    expect(restart).toBeGreaterThan(
      pending,
    );
  });

  it("confirms boot health after authoritative runtime starts", () => {
    const main = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/main.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(main).toContain(
      "bootHealth.confirmHealthy()",
    );
  });

  it("adds simulator install/recovery coverage", () => {
    const simulator = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js",
        import.meta.url,
      ),
      "utf8",
    );

    expect(simulator).toContain(
      "evaluateFirmwareInstallPolicy",
    );

    expect(simulator).toContain(
      "evaluateBootHealth",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 13.6 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - controlled firmware install policy"
echo "  - live-runtime safety gate"
echo "  - verified-device install requirement"
echo "  - explicit ready-to-install decision"
echo "  - boot pending-validation state"
echo "  - boot health confirmation"
echo "  - reboot only after staging/integrity success"
echo "  - simulator install/recovery coverage"
echo "  - Milestone 13.6 tests"
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
echo "Then real firmware compile:"
echo "  bash firmware/esp32-scoreboard/build-in-docker.sh"
echo
echo "Next after green:"
echo "  Milestone 13.7 - OTA Update Reporting / Deployment Status API"
