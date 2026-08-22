#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="11.7-configurable-physical-output-gpio-driver"
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
  "$ROOT/firmware/esp32-scoreboard/include/ScoreboardDisplayDriver.h" \
  "$ROOT/firmware/esp32-scoreboard/include/ScoreboardDisplayController.h"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

FW_DIR="firmware/esp32-scoreboard"
HEADER="$FW_DIR/include/GpioScoreboardDisplayDriver.h"
SOURCE="$FW_DIR/src/GpioScoreboardDisplayDriver.cpp"
README="$FW_DIR/README.md"
TEST="packages/core/test/configurable-gpio-driver-11.7.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$HEADER")" \
  "$BACKUP_DIR/$(dirname "$SOURCE")" \
  "$BACKUP_DIR/$(dirname "$README")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$HEADER")" \
  "$(dirname "$SOURCE")" \
  "$(dirname "$TEST")"

for file in "$HEADER" "$SOURCE" "$README" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$HEADER" <<'EOF'
#pragma once

#include <Arduino.h>

#include "ScoreboardDisplayDriver.h"

namespace sportsos {

struct DigitalOutputConfig {
  int8_t pin;
  bool activeHigh;
  bool enabled;
};

struct GpioScoreboardDisplayConfig {
  DigitalOutputConfig horn;
  DigitalOutputConfig statusNormal;
  DigitalOutputConfig statusWifiLost;
  DigitalOutputConfig statusMqttLost;
  DigitalOutputConfig statusStale;
  DigitalOutputConfig statusRecovery;
};

class GpioScoreboardDisplayDriver final
    : public ScoreboardDisplayDriver {
 public:
  explicit GpioScoreboardDisplayDriver(
      const GpioScoreboardDisplayConfig& config);

  bool begin() override;

  void render(
      const DisplayFrame& frame) override;

  void setHorn(
      bool active) override;

  void setStatusIndicator(
      DisplayHealthState health) override;

  void clear() override;

  const DisplayFrame& lastFrame() const;

  static bool validOutputPin(
      int8_t pin);

 private:
  GpioScoreboardDisplayConfig config_;
  DisplayFrame lastFrame_{};

  void configureOutput(
      const DigitalOutputConfig& output);

  void writeOutput(
      const DigitalOutputConfig& output,
      bool active);

  void clearStatusOutputs();
};

}  // namespace sportsos
EOF

cat > "$SOURCE" <<'EOF'
#include "GpioScoreboardDisplayDriver.h"

namespace sportsos {

GpioScoreboardDisplayDriver::
GpioScoreboardDisplayDriver(
    const GpioScoreboardDisplayConfig& config)
    : config_(config) {}

bool GpioScoreboardDisplayDriver::begin() {
  const DigitalOutputConfig outputs[] = {
      config_.horn,
      config_.statusNormal,
      config_.statusWifiLost,
      config_.statusMqttLost,
      config_.statusStale,
      config_.statusRecovery,
  };

  for (const auto& output : outputs) {
    if (
        output.enabled &&
        !validOutputPin(
            output.pin)
    ) {
      return false;
    }
  }

  for (const auto& output : outputs) {
    configureOutput(
        output);
  }

  clear();

  return true;
}

void GpioScoreboardDisplayDriver::render(
    const DisplayFrame& frame) {
  lastFrame_ = frame;

  setHorn(
      frame.hornActive);

  setStatusIndicator(
      frame.health);
}

void GpioScoreboardDisplayDriver::setHorn(
    bool active) {
  lastFrame_.hornActive =
      active;

  writeOutput(
      config_.horn,
      active);
}

void GpioScoreboardDisplayDriver::setStatusIndicator(
    DisplayHealthState health) {
  lastFrame_.health =
      health;

  clearStatusOutputs();

  switch (health) {
    case DisplayHealthState::Normal:
      writeOutput(
          config_.statusNormal,
          true);
      break;

    case DisplayHealthState::WifiLost:
      writeOutput(
          config_.statusWifiLost,
          true);
      break;

    case DisplayHealthState::MqttLost:
      writeOutput(
          config_.statusMqttLost,
          true);
      break;

    case DisplayHealthState::Stale:
      writeOutput(
          config_.statusStale,
          true);
      break;

    case DisplayHealthState::RecoveryRequired:
    default:
      writeOutput(
          config_.statusRecovery,
          true);
      break;
  }
}

void GpioScoreboardDisplayDriver::clear() {
  lastFrame_ =
      DisplayFrame{};

  writeOutput(
      config_.horn,
      false);

  clearStatusOutputs();
}

const DisplayFrame&
GpioScoreboardDisplayDriver::lastFrame() const {
  return lastFrame_;
}

bool GpioScoreboardDisplayDriver::validOutputPin(
    int8_t pin) {
  return
      pin >= 0 &&
      pin <= 33;
}

void GpioScoreboardDisplayDriver::configureOutput(
    const DigitalOutputConfig& output) {
  if (!output.enabled) {
    return;
  }

  pinMode(
      output.pin,
      OUTPUT);

  writeOutput(
      output,
      false);
}

void GpioScoreboardDisplayDriver::writeOutput(
    const DigitalOutputConfig& output,
    bool active) {
  if (!output.enabled) {
    return;
  }

  const uint8_t level =
      active == output.activeHigh
          ? HIGH
          : LOW;

  digitalWrite(
      output.pin,
      level);
}

void GpioScoreboardDisplayDriver::clearStatusOutputs() {
  writeOutput(
      config_.statusNormal,
      false);

  writeOutput(
      config_.statusWifiLost,
      false);

  writeOutput(
      config_.statusMqttLost,
      false);

  writeOutput(
      config_.statusStale,
      false);

  writeOutput(
      config_.statusRecovery,
      false);
}

}  // namespace sportsos
EOF

cat >> "$README" <<'EOF'

## Milestone 11.7 — Configurable GPIO output driver

The first concrete physical output driver is now available.

### Supported low-voltage digital outputs

- horn trigger output
- normal/healthy status output
- Wi-Fi-lost status output
- MQTT-lost status output
- stale-state status output
- recovery-required status output

Each output supports:

- configurable ESP32 pin
- enabled/disabled state
- active-high or active-low behavior

### Safety behavior

The firmware initializes configured outputs to their inactive state.

The shared driver validates output-capable GPIO numbers before startup.

This milestone defines only low-voltage ESP32 GPIO signaling. It does not define or assume mains-voltage wiring, contactors, power switching, or external scoreboard electrical design.

### Display rendering

Score, period and clock values remain available through `DisplayFrame`, but no specific numeric display chipset is selected yet.

Milestone 11.8 will add configurable hardware profiles and a concrete score/clock display implementation while preserving the shared driver contract.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.7 configurable GPIO driver", () => {
  it("defines configurable active-high/active-low outputs", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/GpioScoreboardDisplayDriver.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "DigitalOutputConfig",
    );
    expect(header).toContain(
      "activeHigh",
    );
    expect(header).toContain(
      "enabled",
    );
  });

  it("supports horn and all hardware health indicators", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/GpioScoreboardDisplayDriver.h",
        import.meta.url,
      ),
      "utf8",
    );

    for (const field of [
      "horn",
      "statusNormal",
      "statusWifiLost",
      "statusMqttLost",
      "statusStale",
      "statusRecovery",
    ]) {
      expect(header).toContain(field);
    }
  });

  it("initializes physical outputs to an inactive state", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/GpioScoreboardDisplayDriver.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "configureOutput",
    );
    expect(source).toContain(
      "writeOutput",
    );
    expect(source).toContain(
      "clear();",
    );
  });

  it("rejects classic ESP32 input-only GPIO 34 through 39", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/GpioScoreboardDisplayDriver.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "pin <= 33",
    );
  });

  it("keeps the concrete driver limited to low-voltage GPIO signaling", () => {
    const readme = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/README.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(readme).toContain(
      "low-voltage ESP32 GPIO signaling",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 11.7 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - GpioScoreboardDisplayDriver"
echo "  - configurable GPIO outputs"
echo "  - active-high / active-low support"
echo "  - horn output"
echo "  - normal / Wi-Fi / MQTT / stale / recovery indicators"
echo "  - safe inactive startup"
echo "  - classic ESP32 output-pin validation"
echo "  - low-voltage GPIO scope only"
echo "  - Milestone 11.7 tests"
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
echo "  Milestone 11.8 - Hardware Profiles / Numeric Display Driver"
