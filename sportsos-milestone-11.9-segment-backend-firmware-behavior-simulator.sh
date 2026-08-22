#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="11.9-segment-backend-firmware-behavior-simulator"
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
  "$ROOT/firmware/esp32-scoreboard/include/NumericScoreboardDisplayDriver.h" \
  "$ROOT/firmware/esp32-scoreboard/include/ScoreboardHardwareProfile.h"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

FW_DIR="firmware/esp32-scoreboard"
SEG_H="$FW_DIR/include/SegmentDisplayBackend.h"
SEG_CPP="$FW_DIR/src/SegmentDisplayBackend.cpp"
SIM="$FW_DIR/simulator/firmware-behavior-simulator.js"
SIM_PKG="$FW_DIR/simulator/package.json"
SIM_TEST="$FW_DIR/simulator/test/firmware-behavior.test.js"
README="$FW_DIR/README.md"
TEST="packages/core/test/segment-backend-firmware-simulator-11.9.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$SEG_H")" \
  "$BACKUP_DIR/$(dirname "$SEG_CPP")" \
  "$BACKUP_DIR/$(dirname "$SIM")" \
  "$BACKUP_DIR/$(dirname "$SIM_PKG")" \
  "$BACKUP_DIR/$(dirname "$SIM_TEST")" \
  "$BACKUP_DIR/$(dirname "$README")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$SEG_H")" \
  "$(dirname "$SEG_CPP")" \
  "$(dirname "$SIM")" \
  "$(dirname "$SIM_TEST")" \
  "$(dirname "$TEST")"

for file in "$SEG_H" "$SEG_CPP" "$SIM" "$SIM_PKG" "$SIM_TEST" "$README" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$SEG_H" <<'EOF'
#pragma once

#include <stdint.h>

#include "NumericScoreboardDisplayDriver.h"

namespace sportsos {

struct SegmentBusConfig {
  int8_t dataPin;
  int8_t clockPin;
  int8_t latchPin;
  bool activeHigh;
};

class SegmentDisplayBackend final
    : public NumericScoreboardDisplayDriver {
 public:
  SegmentDisplayBackend(
      const ScoreboardHardwareProfile& profile,
      const SegmentBusConfig& bus);

  bool begin() override;

 protected:
  void writeNumericSnapshot(
      const NumericDisplaySnapshot& snapshot) override;

  void writeHornOutput(
      bool active) override;

  void writeHealthOutput(
      DisplayHealthState health) override;

 private:
  SegmentBusConfig bus_;

  void writeByte(
      uint8_t value);

  static uint8_t encodeDigit(
      uint8_t digit);

  static bool validOutputPin(
      int8_t pin);
};

}  // namespace sportsos
EOF

cat > "$SEG_CPP" <<'EOF'
#include "SegmentDisplayBackend.h"

#include <Arduino.h>

namespace sportsos {

SegmentDisplayBackend::SegmentDisplayBackend(
    const ScoreboardHardwareProfile& profile,
    const SegmentBusConfig& bus)
    : NumericScoreboardDisplayDriver(profile),
      bus_(bus) {}

bool SegmentDisplayBackend::begin() {
  if (
      !validOutputPin(bus_.dataPin) ||
      !validOutputPin(bus_.clockPin) ||
      !validOutputPin(bus_.latchPin)
  ) {
    return false;
  }

  pinMode(bus_.dataPin, OUTPUT);
  pinMode(bus_.clockPin, OUTPUT);
  pinMode(bus_.latchPin, OUTPUT);

  digitalWrite(bus_.dataPin, LOW);
  digitalWrite(bus_.clockPin, LOW);
  digitalWrite(bus_.latchPin, LOW);

  return NumericScoreboardDisplayDriver::begin();
}

void SegmentDisplayBackend::writeNumericSnapshot(
    const NumericDisplaySnapshot& snapshot) {
  const uint8_t values[] = {
      static_cast<uint8_t>(snapshot.homeScore / 10),
      static_cast<uint8_t>(snapshot.homeScore % 10),
      static_cast<uint8_t>(snapshot.awayScore / 10),
      static_cast<uint8_t>(snapshot.awayScore % 10),
      snapshot.hasPeriod ? snapshot.period : 0,
      static_cast<uint8_t>(snapshot.clockMinutes / 10),
      static_cast<uint8_t>(snapshot.clockMinutes % 10),
      static_cast<uint8_t>(snapshot.clockSeconds / 10),
      static_cast<uint8_t>(snapshot.clockSeconds % 10),
  };

  digitalWrite(bus_.latchPin, LOW);

  for (const uint8_t value : values) {
    writeByte(encodeDigit(value));
  }

  digitalWrite(bus_.latchPin, HIGH);
}

void SegmentDisplayBackend::writeHornOutput(bool) {}

void SegmentDisplayBackend::writeHealthOutput(
    DisplayHealthState) {}

void SegmentDisplayBackend::writeByte(
    uint8_t value) {
  if (!bus_.activeHigh) {
    value = static_cast<uint8_t>(~value);
  }

  shiftOut(
      bus_.dataPin,
      bus_.clockPin,
      MSBFIRST,
      value);
}

uint8_t SegmentDisplayBackend::encodeDigit(
    uint8_t digit) {
  static constexpr uint8_t digits[] = {
      0b00111111,
      0b00000110,
      0b01011011,
      0b01001111,
      0b01100110,
      0b01101101,
      0b01111101,
      0b00000111,
      0b01111111,
      0b01101111,
  };

  if (digit > 9) {
    return 0;
  }

  return digits[digit];
}

bool SegmentDisplayBackend::validOutputPin(
    int8_t pin) {
  return pin >= 0 && pin <= 33;
}

}  // namespace sportsos
EOF

cat > "$SIM" <<'EOF'
"use strict";

function clampNonNegativeInteger(value) {
  if (!Number.isFinite(value)) {
    return 0;
  }

  return Math.max(0, Math.floor(value));
}

function buildNumericSnapshot(frame) {
  const totalSeconds =
    Math.floor(
      clampNonNegativeInteger(frame.remainingMs) /
        1000,
    );

  return {
    homeScore:
      clampNonNegativeInteger(frame.homeScore),
    awayScore:
      clampNonNegativeInteger(frame.awayScore),
    period:
      frame.hasPeriod
        ? clampNonNegativeInteger(frame.period)
        : null,
    clockMinutes:
      Math.floor(totalSeconds / 60),
    clockSeconds:
      totalSeconds % 60,
    clockRunning:
      Boolean(frame.clockRunning),
    hornActive:
      Boolean(frame.hornActive),
    health:
      frame.health ?? "Normal",
  };
}

function renderSevenSegment(snapshot) {
  const two = (value) =>
    String(value).padStart(2, "0");

  return {
    home: two(snapshot.homeScore),
    away: two(snapshot.awayScore),
    period:
      snapshot.period === null
        ? "-"
        : String(snapshot.period),
    clock:
      `${two(snapshot.clockMinutes)}:${two(snapshot.clockSeconds)}`,
    running:
      snapshot.clockRunning,
    horn:
      snapshot.hornActive,
    health:
      snapshot.health,
  };
}

function tickFrame(frame, elapsedMs) {
  if (!frame.clockRunning) {
    return { ...frame };
  }

  const next =
    Math.max(
      0,
      clampNonNegativeInteger(frame.remainingMs) -
        clampNonNegativeInteger(elapsedMs),
    );

  return {
    ...frame,
    remainingMs: next,
    clockRunning: next > 0,
  };
}

module.exports = {
  buildNumericSnapshot,
  renderSevenSegment,
  tickFrame,
};
EOF

cat > "$SIM_PKG" <<'EOF'
{
  "name": "@sportsos/esp32-firmware-simulator",
  "private": true,
  "version": "0.11.9",
  "type": "commonjs",
  "scripts": {
    "test": "node --test test/*.test.js"
  }
}
EOF

cat > "$SIM_TEST" <<'EOF'
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildNumericSnapshot,
  renderSevenSegment,
  tickFrame,
} = require("../firmware-behavior-simulator.js");

test("11.9 converts state into numeric display state", () => {
  const snapshot =
    buildNumericSnapshot({
      homeScore: 4,
      awayScore: 2,
      hasPeriod: true,
      period: 3,
      remainingMs: 125000,
      clockRunning: true,
      hornActive: false,
      health: "Normal",
    });

  assert.deepEqual(snapshot, {
    homeScore: 4,
    awayScore: 2,
    period: 3,
    clockMinutes: 2,
    clockSeconds: 5,
    clockRunning: true,
    hornActive: false,
    health: "Normal",
  });
});

test("11.9 renders fixed-width fields", () => {
  const rendered =
    renderSevenSegment({
      homeScore: 4,
      awayScore: 2,
      period: 3,
      clockMinutes: 2,
      clockSeconds: 5,
      clockRunning: true,
      hornActive: false,
      health: "Normal",
    });

  assert.equal(rendered.home, "04");
  assert.equal(rendered.away, "02");
  assert.equal(rendered.clock, "02:05");
});

test("11.9 projects clock and stops at zero", () => {
  const next =
    tickFrame(
      {
        remainingMs: 1500,
        clockRunning: true,
      },
      2000,
    );

  assert.equal(next.remainingMs, 0);
  assert.equal(next.clockRunning, false);
});
EOF

cat >> "$README" <<'EOF'

## Milestone 11.9 — Segment backend / firmware behavior simulator

The firmware now includes a concrete low-voltage seven-segment output backend using a generic shift-register bus.

### Segment backend

The backend supports:

- configurable data pin
- configurable clock pin
- configurable latch pin
- active-high or active-low segment logic
- score digits
- period digit
- clock minute/second digits

The implementation uses only low-voltage ESP32 digital signaling.

### Host-side behavior simulator

`firmware/esp32-scoreboard/simulator` mirrors the core display behavior without requiring PlatformIO or ESP32 hardware.

It validates:

- authoritative state to numeric display conversion
- fixed-width score/clock rendering
- local clock projection
- stop-at-zero behavior

Milestone 11.10 will add firmware diagnostics and closeout integration before real-device flashing.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.9 segment backend and firmware simulator", () => {
  it("defines a concrete shift-register segment backend", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/SegmentDisplayBackend.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain("shiftOut");
    expect(source).toContain("encodeDigit");
    expect(source).toContain("latchPin");
  });

  it("maps decimal digits to seven-segment bit patterns", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/SegmentDisplayBackend.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain("0b00111111");
    expect(source).toContain("0b01101111");
  });

  it("keeps output pins configurable", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/SegmentDisplayBackend.h",
        import.meta.url,
      ),
      "utf8",
    );

    for (const field of [
      "dataPin",
      "clockPin",
      "latchPin",
      "activeHigh",
    ]) {
      expect(header).toContain(field);
    }
  });

  it("adds a host-side firmware behavior simulator", () => {
    const simulator = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js",
        import.meta.url,
      ),
      "utf8",
    );

    expect(simulator).toContain("buildNumericSnapshot");
    expect(simulator).toContain("renderSevenSegment");
    expect(simulator).toContain("tickFrame");
  });

  it("adds standalone simulator tests without PlatformIO", () => {
    const packageJson = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/simulator/package.json",
        import.meta.url,
      ),
      "utf8",
    );

    expect(packageJson).toContain("node --test");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 11.9 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - SegmentDisplayBackend"
echo "  - configurable data/clock/latch pins"
echo "  - active-high / active-low segment logic"
echo "  - seven-segment digit encoding"
echo "  - score / period / clock output path"
echo "  - host-side firmware behavior simulator"
echo "  - simulator tests that do not require PlatformIO"
echo "  - Milestone 11.9 repository tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run repository validation:"
echo "  npm run typecheck && npm test"
echo
echo "Run firmware simulator:"
echo "  node --test firmware/esp32-scoreboard/simulator/test/*.test.js"
echo
echo "PlatformIO:"
echo "  Still optional."
echo
echo "Next after green:"
echo "  Milestone 11.10 - Firmware Diagnostics / Hardware Closeout"
