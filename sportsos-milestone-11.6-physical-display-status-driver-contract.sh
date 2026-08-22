#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="11.6-physical-display-status-driver-contract"
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
  "$ROOT/firmware/esp32-scoreboard/include/ScoreboardProtocol.h" \
  "$ROOT/firmware/esp32-scoreboard/include/ConnectivityWatchdog.h"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

FW_DIR="firmware/esp32-scoreboard"
HEADER="$FW_DIR/include/ScoreboardDisplayDriver.h"
NULL_H="$FW_DIR/include/NullScoreboardDisplayDriver.h"
NULL_CPP="$FW_DIR/src/NullScoreboardDisplayDriver.cpp"
CONTROLLER_H="$FW_DIR/include/ScoreboardDisplayController.h"
CONTROLLER_CPP="$FW_DIR/src/ScoreboardDisplayController.cpp"
README="$FW_DIR/README.md"
TEST="packages/core/test/physical-display-driver-contract-11.6.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$HEADER")" \
  "$BACKUP_DIR/$(dirname "$NULL_H")" \
  "$BACKUP_DIR/$(dirname "$NULL_CPP")" \
  "$BACKUP_DIR/$(dirname "$CONTROLLER_H")" \
  "$BACKUP_DIR/$(dirname "$CONTROLLER_CPP")" \
  "$BACKUP_DIR/$(dirname "$README")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$HEADER")" \
  "$(dirname "$NULL_CPP")" \
  "$(dirname "$TEST")"

for file in "$HEADER" "$NULL_H" "$NULL_CPP" "$CONTROLLER_H" "$CONTROLLER_CPP" "$README" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$HEADER" <<'EOF'
#pragma once

#include <stdint.h>

namespace sportsos {

enum class DisplayHealthState : uint8_t {
  Normal = 0,
  WifiLost,
  MqttLost,
  Stale,
  RecoveryRequired,
};

struct DisplayFrame {
  uint16_t homeScore;
  uint16_t awayScore;

  bool hasPeriod;
  uint8_t period;

  uint32_t remainingMs;
  bool clockRunning;

  bool hornActive;
  bool hasGame;

  DisplayHealthState health;
};

class ScoreboardDisplayDriver {
 public:
  virtual ~ScoreboardDisplayDriver() = default;

  virtual bool begin() = 0;

  virtual void render(
      const DisplayFrame& frame) = 0;

  virtual void setHorn(
      bool active) = 0;

  virtual void setStatusIndicator(
      DisplayHealthState health) = 0;

  virtual void clear() = 0;
};

}  // namespace sportsos
EOF

cat > "$NULL_H" <<'EOF'
#pragma once

#include "ScoreboardDisplayDriver.h"

namespace sportsos {

class NullScoreboardDisplayDriver final
    : public ScoreboardDisplayDriver {
 public:
  bool begin() override;

  void render(
      const DisplayFrame& frame) override;

  void setHorn(
      bool active) override;

  void setStatusIndicator(
      DisplayHealthState health) override;

  void clear() override;

  const DisplayFrame& lastFrame() const;

 private:
  DisplayFrame lastFrame_{};
};

}  // namespace sportsos
EOF

cat > "$NULL_CPP" <<'EOF'
#include "NullScoreboardDisplayDriver.h"

namespace sportsos {

bool NullScoreboardDisplayDriver::begin() {
  return true;
}

void NullScoreboardDisplayDriver::render(
    const DisplayFrame& frame) {
  lastFrame_ = frame;
}

void NullScoreboardDisplayDriver::setHorn(
    bool active) {
  lastFrame_.hornActive = active;
}

void NullScoreboardDisplayDriver::setStatusIndicator(
    DisplayHealthState health) {
  lastFrame_.health = health;
}

void NullScoreboardDisplayDriver::clear() {
  lastFrame_ = DisplayFrame{};
}

const DisplayFrame&
NullScoreboardDisplayDriver::lastFrame() const {
  return lastFrame_;
}

}  // namespace sportsos
EOF

cat > "$CONTROLLER_H" <<'EOF'
#pragma once

#include "ConnectivityWatchdog.h"
#include "ScoreboardDisplayDriver.h"
#include "ScoreboardProtocol.h"

namespace sportsos {

class ScoreboardDisplayController {
 public:
  explicit ScoreboardDisplayController(
      ScoreboardDisplayDriver& driver);

  bool begin();

  void update(
      const ScoreboardState& state,
      ConnectivityHealth connectivityHealth);

  static DisplayHealthState mapHealth(
      ConnectivityHealth connectivityHealth);

 private:
  ScoreboardDisplayDriver& driver_;
};

}  // namespace sportsos
EOF

cat > "$CONTROLLER_CPP" <<'EOF'
#include "ScoreboardDisplayController.h"

namespace sportsos {

ScoreboardDisplayController::ScoreboardDisplayController(
    ScoreboardDisplayDriver& driver)
    : driver_(driver) {}

bool ScoreboardDisplayController::begin() {
  return driver_.begin();
}

void ScoreboardDisplayController::update(
    const ScoreboardState& state,
    ConnectivityHealth connectivityHealth) {
  DisplayFrame frame{};

  frame.homeScore =
      state.homeScore;

  frame.awayScore =
      state.awayScore;

  frame.hasPeriod =
      state.hasPeriod;

  frame.period =
      state.period;

  frame.remainingMs =
      state.clock.remainingMs;

  frame.clockRunning =
      state.clock.running;

  frame.hornActive =
      state.hornActive;

  frame.hasGame =
      state.hasGame;

  frame.health =
      mapHealth(
          connectivityHealth);

  driver_.render(
      frame);

  driver_.setHorn(
      state.hornActive);

  driver_.setStatusIndicator(
      frame.health);
}

DisplayHealthState
ScoreboardDisplayController::mapHealth(
    ConnectivityHealth connectivityHealth) {
  switch (connectivityHealth) {
    case ConnectivityHealth::Healthy:
      return DisplayHealthState::Normal;

    case ConnectivityHealth::WifiLost:
      return DisplayHealthState::WifiLost;

    case ConnectivityHealth::MqttLost:
      return DisplayHealthState::MqttLost;

    case ConnectivityHealth::StaleAuthoritativeState:
      return DisplayHealthState::Stale;

    case ConnectivityHealth::RecoveryRequired:
      return DisplayHealthState::RecoveryRequired;

    default:
      return DisplayHealthState::RecoveryRequired;
  }
}

}  // namespace sportsos
EOF

cat >> "$README" <<'EOF'

## Milestone 11.6 — Physical display / status driver contract

The firmware now has a hardware abstraction layer between SportsOS state and physical scoreboard electronics.

### Display frame

The hardware driver receives:

- home score
- away score
- period
- remaining clock time
- clock running state
- horn state
- game assignment presence
- connectivity / stale-state health

### Driver responsibilities

Concrete hardware drivers implement:

- initialization
- score/period/clock rendering
- horn output
- connectivity/status indicators
- clear/reset behavior

No GPIO pins, LED protocols, segment drivers, or relay assumptions are part of the shared contract.

A `NullScoreboardDisplayDriver` is included for testing and hardware-independent firmware development.

Milestone 11.7 will add the first concrete physical output implementation and configurable hardware mapping.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.6 physical display/status driver contract", () => {
  it("defines a hardware-independent display frame", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardDisplayDriver.h",
        import.meta.url,
      ),
      "utf8",
    );

    for (const field of [
      "homeScore",
      "awayScore",
      "period",
      "remainingMs",
      "clockRunning",
      "hornActive",
      "health",
    ]) {
      expect(header).toContain(field);
    }
  });

  it("defines an abstract physical display driver", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardDisplayDriver.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "virtual bool begin() = 0",
    );
    expect(header).toContain(
      "virtual void render",
    );
    expect(header).toContain(
      "virtual void setHorn",
    );
    expect(header).toContain(
      "virtual void setStatusIndicator",
    );
  });

  it("maps connectivity watchdog state into operator-visible display health", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardDisplayController.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    for (const state of [
      "WifiLost",
      "MqttLost",
      "StaleAuthoritativeState",
      "RecoveryRequired",
    ]) {
      expect(source).toContain(state);
    }
  });

  it("includes a null driver for hardware-independent testing", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/NullScoreboardDisplayDriver.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "NullScoreboardDisplayDriver",
    );
    expect(header).toContain(
      "lastFrame",
    );
  });

  it("does not hardcode GPIO or a display chipset in the shared contract", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardDisplayDriver.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).not.toMatch(
      /\bGPIO\b|MAX7219|TM1637|HUB75|NeoPixel|WS2812/i,
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 11.6 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - ScoreboardDisplayDriver abstraction"
echo "  - DisplayFrame contract"
echo "  - display health/status states"
echo "  - ScoreboardDisplayController"
echo "  - ConnectivityWatchdog -> display health mapping"
echo "  - NullScoreboardDisplayDriver"
echo "  - no GPIO/display-chip assumptions"
echo "  - Milestone 11.6 tests"
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
echo "  Milestone 11.7 - Configurable Physical Output / GPIO Driver"
