#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="11.8-hardware-profiles-numeric-display-driver"
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
  "$ROOT/firmware/esp32-scoreboard/include/GpioScoreboardDisplayDriver.h"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

FW_DIR="firmware/esp32-scoreboard"
PROFILE_H="$FW_DIR/include/ScoreboardHardwareProfile.h"
PROFILE_CPP="$FW_DIR/src/ScoreboardHardwareProfile.cpp"
NUMERIC_H="$FW_DIR/include/NumericScoreboardDisplayDriver.h"
NUMERIC_CPP="$FW_DIR/src/NumericScoreboardDisplayDriver.cpp"
README="$FW_DIR/README.md"
TEST="packages/core/test/hardware-profiles-numeric-display-11.8.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$PROFILE_H")" \
  "$BACKUP_DIR/$(dirname "$PROFILE_CPP")" \
  "$BACKUP_DIR/$(dirname "$NUMERIC_H")" \
  "$BACKUP_DIR/$(dirname "$NUMERIC_CPP")" \
  "$BACKUP_DIR/$(dirname "$README")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$PROFILE_H")" \
  "$(dirname "$PROFILE_CPP")" \
  "$(dirname "$NUMERIC_H")" \
  "$(dirname "$NUMERIC_CPP")" \
  "$(dirname "$TEST")"

for file in "$PROFILE_H" "$PROFILE_CPP" "$NUMERIC_H" "$NUMERIC_CPP" "$README" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$PROFILE_H" <<'EOF'
#pragma once

#include <stdint.h>

namespace sportsos {

enum class NumericDisplayBackend : uint8_t {
  None = 0,
  ShiftRegister,
  GenericMultiplexed,
};

struct NumericDisplayProfile {
  NumericDisplayBackend backend;

  uint8_t homeScoreDigits;
  uint8_t awayScoreDigits;
  uint8_t periodDigits;
  uint8_t clockMinuteDigits;
  uint8_t clockSecondDigits;

  bool leadingZeroMinutes;
  bool leadingZeroSeconds;
};

struct ScoreboardHardwareProfile {
  const char* id;
  const char* displayName;

  NumericDisplayProfile numericDisplay;

  bool hornEnabled;
  bool statusIndicatorsEnabled;
};

class ScoreboardHardwareProfiles {
 public:
  static ScoreboardHardwareProfile minimalBench();

  static ScoreboardHardwareProfile standardHockey();

  static bool validate(
      const ScoreboardHardwareProfile& profile);
};

}  // namespace sportsos
EOF

cat > "$PROFILE_CPP" <<'EOF'
#include "ScoreboardHardwareProfile.h"

namespace sportsos {

ScoreboardHardwareProfile
ScoreboardHardwareProfiles::minimalBench() {
  return {
      "minimal-bench",
      "Minimal Bench Test",
      {
          NumericDisplayBackend::GenericMultiplexed,
          2,
          2,
          1,
          2,
          2,
          false,
          true,
      },
      false,
      true,
  };
}

ScoreboardHardwareProfile
ScoreboardHardwareProfiles::standardHockey() {
  return {
      "standard-hockey",
      "Standard Hockey Scoreboard",
      {
          NumericDisplayBackend::GenericMultiplexed,
          2,
          2,
          1,
          2,
          2,
          false,
          true,
      },
      true,
      true,
  };
}

bool ScoreboardHardwareProfiles::validate(
    const ScoreboardHardwareProfile& profile) {
  if (
      profile.id == nullptr ||
      profile.id[0] == '\0' ||
      profile.displayName == nullptr ||
      profile.displayName[0] == '\0'
  ) {
    return false;
  }

  const NumericDisplayProfile& display =
      profile.numericDisplay;

  if (
      display.backend ==
      NumericDisplayBackend::None
  ) {
    return false;
  }

  if (
      display.homeScoreDigits == 0 ||
      display.awayScoreDigits == 0 ||
      display.periodDigits == 0 ||
      display.clockMinuteDigits == 0 ||
      display.clockSecondDigits == 0
  ) {
    return false;
  }

  return true;
}

}  // namespace sportsos
EOF

cat > "$NUMERIC_H" <<'EOF'
#pragma once

#include <stdint.h>

#include "ScoreboardDisplayDriver.h"
#include "ScoreboardHardwareProfile.h"

namespace sportsos {

struct NumericDisplaySnapshot {
  uint16_t homeScore;
  uint16_t awayScore;

  uint8_t period;
  bool hasPeriod;

  uint16_t clockMinutes;
  uint8_t clockSeconds;
  bool clockRunning;

  DisplayHealthState health;
};

class NumericScoreboardDisplayDriver
    : public ScoreboardDisplayDriver {
 public:
  explicit NumericScoreboardDisplayDriver(
      const ScoreboardHardwareProfile& profile);

  bool begin() override;

  void render(
      const DisplayFrame& frame) override;

  void setHorn(
      bool active) override;

  void setStatusIndicator(
      DisplayHealthState health) override;

  void clear() override;

  const NumericDisplaySnapshot&
  snapshot() const;

  bool hornActive() const;

  static NumericDisplaySnapshot
  buildSnapshot(
      const DisplayFrame& frame);

 protected:
  virtual void writeNumericSnapshot(
      const NumericDisplaySnapshot& snapshot);

  virtual void writeHornOutput(
      bool active);

  virtual void writeHealthOutput(
      DisplayHealthState health);

 private:
  ScoreboardHardwareProfile profile_;
  NumericDisplaySnapshot snapshot_{};
  bool hornActive_;
};

}  // namespace sportsos
EOF

cat > "$NUMERIC_CPP" <<'EOF'
#include "NumericScoreboardDisplayDriver.h"

namespace sportsos {

NumericScoreboardDisplayDriver::
NumericScoreboardDisplayDriver(
    const ScoreboardHardwareProfile& profile)
    : profile_(profile),
      hornActive_(false) {}

bool NumericScoreboardDisplayDriver::begin() {
  if (
      !ScoreboardHardwareProfiles::validate(
          profile_)
  ) {
    return false;
  }

  clear();

  return true;
}

void NumericScoreboardDisplayDriver::render(
    const DisplayFrame& frame) {
  snapshot_ =
      buildSnapshot(
          frame);

  writeNumericSnapshot(
      snapshot_);

  setHorn(
      frame.hornActive);

  setStatusIndicator(
      frame.health);
}

void NumericScoreboardDisplayDriver::setHorn(
    bool active) {
  hornActive_ =
      active;

  if (
      !profile_.hornEnabled
  ) {
    writeHornOutput(
        false);
    return;
  }

  writeHornOutput(
      active);
}

void NumericScoreboardDisplayDriver::setStatusIndicator(
    DisplayHealthState health) {
  snapshot_.health =
      health;

  if (
      !profile_.statusIndicatorsEnabled
  ) {
    return;
  }

  writeHealthOutput(
      health);
}

void NumericScoreboardDisplayDriver::clear() {
  snapshot_ =
      NumericDisplaySnapshot{};

  hornActive_ =
      false;

  writeNumericSnapshot(
      snapshot_);

  writeHornOutput(
      false);

  if (
      profile_.statusIndicatorsEnabled
  ) {
    writeHealthOutput(
        DisplayHealthState::Normal);
  }
}

const NumericDisplaySnapshot&
NumericScoreboardDisplayDriver::snapshot() const {
  return snapshot_;
}

bool NumericScoreboardDisplayDriver::hornActive() const {
  return hornActive_;
}

NumericDisplaySnapshot
NumericScoreboardDisplayDriver::buildSnapshot(
    const DisplayFrame& frame) {
  NumericDisplaySnapshot snapshot{};

  snapshot.homeScore =
      frame.homeScore;

  snapshot.awayScore =
      frame.awayScore;

  snapshot.period =
      frame.period;

  snapshot.hasPeriod =
      frame.hasPeriod;

  const uint32_t totalSeconds =
      frame.remainingMs / 1000UL;

  snapshot.clockMinutes =
      static_cast<uint16_t>(
          totalSeconds / 60UL);

  snapshot.clockSeconds =
      static_cast<uint8_t>(
          totalSeconds % 60UL);

  snapshot.clockRunning =
      frame.clockRunning;

  snapshot.health =
      frame.health;

  return snapshot;
}

void NumericScoreboardDisplayDriver::writeNumericSnapshot(
    const NumericDisplaySnapshot&) {
  /*
   * Hardware backend intentionally deferred.
   * Concrete shift-register or multiplexed drivers will override this.
   */
}

void NumericScoreboardDisplayDriver::writeHornOutput(
    bool) {}

void NumericScoreboardDisplayDriver::writeHealthOutput(
    DisplayHealthState) {}

}  // namespace sportsos
EOF

cat >> "$README" <<'EOF'

## Milestone 11.8 — Hardware profiles / numeric display driver

The firmware now supports named hardware profiles and a concrete numeric scoreboard display layer.

### Included profiles

- `minimal-bench`
- `standard-hockey`

Profiles define:

- score digit counts
- period digit count
- clock minute/second digit counts
- numeric display backend type
- horn availability
- status indicator availability
- leading-zero preferences

### Numeric display snapshot

`NumericScoreboardDisplayDriver` converts the shared `DisplayFrame` into:

- home score
- away score
- period
- clock minutes
- clock seconds
- clock running state
- display health state

The driver remains backend-extensible. No high-current display wiring or mains-power switching is defined here.

Milestone 11.9 will add a concrete low-voltage shift-register / multiplexed segment backend and a host-side firmware behavior simulator.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.8 hardware profiles and numeric display", () => {
  it("defines named scoreboard hardware profiles", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardHardwareProfile.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "minimal-bench",
    );
    expect(source).toContain(
      "standard-hockey",
    );
  });

  it("defines configurable numeric display geometry", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardHardwareProfile.h",
        import.meta.url,
      ),
      "utf8",
    );

    for (const field of [
      "homeScoreDigits",
      "awayScoreDigits",
      "periodDigits",
      "clockMinuteDigits",
      "clockSecondDigits",
    ]) {
      expect(header).toContain(field);
    }
  });

  it("converts milliseconds into clock minutes and seconds", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/NumericScoreboardDisplayDriver.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "totalSeconds / 60UL",
    );
    expect(source).toContain(
      "totalSeconds % 60UL",
    );
  });

  it("keeps numeric rendering backend-extensible", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/NumericScoreboardDisplayDriver.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "virtual void writeNumericSnapshot",
    );
    expect(header).toContain(
      "virtual void writeHornOutput",
    );
    expect(header).toContain(
      "virtual void writeHealthOutput",
    );
  });

  it("avoids high-current or mains-power hardware assumptions", () => {
    const readme = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/README.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(readme).toContain(
      "No high-current display wiring or mains-power switching is defined here.",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 11.8 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - ScoreboardHardwareProfile"
echo "  - minimal-bench profile"
echo "  - standard-hockey profile"
echo "  - configurable numeric display geometry"
echo "  - NumericScoreboardDisplayDriver"
echo "  - score/period/clock snapshot conversion"
echo "  - backend-extensible numeric output layer"
echo "  - horn/status capability flags"
echo "  - Milestone 11.8 tests"
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
echo "  Milestone 11.9 - Segment Backend / Firmware Behavior Simulator"
