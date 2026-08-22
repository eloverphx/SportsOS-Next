#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="14.1-hardware-control-input-contract"
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
  "$ROOT/packages/core/src/index.ts" \
  "$ROOT/firmware/esp32-scoreboard/include/ScoreboardProtocol.h" \
  "$ROOT/apps/api/src/services/scoreboardDeviceEnrollment.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

CORE="packages/core/src/scoreboard-control-input-contract.ts"
CORE_INDEX="packages/core/src/index.ts"
FW_H="firmware/esp32-scoreboard/include/ScoreboardControlInput.h"
FW_CPP="firmware/esp32-scoreboard/src/ScoreboardControlInput.cpp"
README="firmware/esp32-scoreboard/README.md"
TEST="packages/core/test/hardware-control-input-contract-14.1.test.ts"

for file in "$CORE" "$CORE_INDEX" "$FW_H" "$FW_CPP" "$README" "$TEST"; do
  if [[ -f "$file" ]]; then
    rel="${file#$ROOT/}"
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$file" "$BACKUP_DIR/$rel"
  fi
done

mkdir -p \
  "$(dirname "$CORE")" \
  "$(dirname "$FW_H")" \
  "$(dirname "$FW_CPP")" \
  "$(dirname "$TEST")"

cat > "$CORE" <<'EOF'
export const SCOREBOARD_CONTROL_INPUT_PROTOCOL_VERSION =
  1 as const;

export type ScoreboardControlInputType =
  | "SCORE_HOME_INCREMENT"
  | "SCORE_HOME_DECREMENT"
  | "SCORE_AWAY_INCREMENT"
  | "SCORE_AWAY_DECREMENT"
  | "CLOCK_TOGGLE"
  | "CLOCK_START"
  | "CLOCK_PAUSE"
  | "PERIOD_INCREMENT"
  | "PERIOD_DECREMENT"
  | "HORN_TRIGGER";

export type ScoreboardControlInputEvent = {
  protocolVersion:
    typeof SCOREBOARD_CONTROL_INPUT_PROTOCOL_VERSION;
  inputId: string;
  deviceId: string;
  type: ScoreboardControlInputType;
  occurredAt: string;
  sequence: number;
};

export type ScoreboardControlInputDisposition =
  | "ACCEPTED"
  | "REJECTED"
  | "IGNORED_DUPLICATE";

export type ScoreboardControlInputAck = {
  inputId: string;
  deviceId: string;
  disposition: ScoreboardControlInputDisposition;
  reason: string | null;
  authoritativeGameId: string | null;
  processedAt: string;
};

export function isScoreboardControlInputType(
  value: string,
): value is ScoreboardControlInputType {
  return (
    value === "SCORE_HOME_INCREMENT" ||
    value === "SCORE_HOME_DECREMENT" ||
    value === "SCORE_AWAY_INCREMENT" ||
    value === "SCORE_AWAY_DECREMENT" ||
    value === "CLOCK_TOGGLE" ||
    value === "CLOCK_START" ||
    value === "CLOCK_PAUSE" ||
    value === "PERIOD_INCREMENT" ||
    value === "PERIOD_DECREMENT" ||
    value === "HORN_TRIGGER"
  );
}
EOF

if ! grep -q 'scoreboard-control-input-contract.js' "$CORE_INDEX"; then
  printf '\nexport * from "./scoreboard-control-input-contract.js";\n' >> "$CORE_INDEX"
fi

cat > "$FW_H" <<'EOF'
#pragma once

#include <Arduino.h>

namespace sportsos {

constexpr uint8_t
CONTROL_INPUT_PROTOCOL_VERSION = 1;

enum class ScoreboardControlInputType : uint8_t {
  ScoreHomeIncrement = 0,
  ScoreHomeDecrement,
  ScoreAwayIncrement,
  ScoreAwayDecrement,
  ClockToggle,
  ClockStart,
  ClockPause,
  PeriodIncrement,
  PeriodDecrement,
  HornTrigger,
};

struct ScoreboardControlInputEvent {
  char inputId[64];
  char deviceId[64];
  ScoreboardControlInputType type;
  uint32_t sequence;
  unsigned long occurredAtMs;
};

class ScoreboardControlInput {
 public:
  static const char* typeText(
      ScoreboardControlInputType type);

  static bool validate(
      const ScoreboardControlInputEvent& event);
};

}  // namespace sportsos
EOF

cat > "$FW_CPP" <<'EOF'
#include "ScoreboardControlInput.h"

namespace sportsos {

const char*
ScoreboardControlInput::typeText(
    ScoreboardControlInputType type) {
  switch (type) {
    case ScoreboardControlInputType::ScoreHomeIncrement:
      return "SCORE_HOME_INCREMENT";
    case ScoreboardControlInputType::ScoreHomeDecrement:
      return "SCORE_HOME_DECREMENT";
    case ScoreboardControlInputType::ScoreAwayIncrement:
      return "SCORE_AWAY_INCREMENT";
    case ScoreboardControlInputType::ScoreAwayDecrement:
      return "SCORE_AWAY_DECREMENT";
    case ScoreboardControlInputType::ClockToggle:
      return "CLOCK_TOGGLE";
    case ScoreboardControlInputType::ClockStart:
      return "CLOCK_START";
    case ScoreboardControlInputType::ClockPause:
      return "CLOCK_PAUSE";
    case ScoreboardControlInputType::PeriodIncrement:
      return "PERIOD_INCREMENT";
    case ScoreboardControlInputType::PeriodDecrement:
      return "PERIOD_DECREMENT";
    case ScoreboardControlInputType::HornTrigger:
      return "HORN_TRIGGER";
    default:
      return "UNKNOWN";
  }
}

bool ScoreboardControlInput::validate(
    const ScoreboardControlInputEvent& event) {
  return
      event.inputId[0] != '\0' &&
      event.deviceId[0] != '\0' &&
      event.sequence > 0;
}

}  // namespace sportsos
EOF

cat >> "$README" <<'EOF'

## Milestone 14.1 — Hardware button / control input contract

SportsOS now defines a physical scoreboard input contract for ESP32-connected buttons and control panels.

Supported input intents:

- home score +1
- home score -1
- away score +1
- away score -1
- clock toggle
- clock start
- clock pause
- period +1
- period -1
- horn trigger

Physical controls do **not** directly mutate authoritative SportsOS game state.

Instead, firmware emits a control-input event containing:

- protocol version
- unique input ID
- device ID
- control intent
- sequence number
- occurrence time

SportsOS will later validate the device, assignment, game state, permissions, and duplicate sequence before applying any authoritative change.

The server returns one of:

- `ACCEPTED`
- `REJECTED`
- `IGNORED_DUPLICATE`

This preserves SportsOS as the authoritative game-state source while still supporting low-latency physical controls.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  SCOREBOARD_CONTROL_INPUT_PROTOCOL_VERSION,
  isScoreboardControlInputType,
} from "../src/scoreboard-control-input-contract.js";

describe("Milestone 14.1 hardware control input contract", () => {
  it("defines protocol version 1", () => {
    expect(
      SCOREBOARD_CONTROL_INPUT_PROTOCOL_VERSION,
    ).toBe(1);
  });

  it("supports score clock period and horn intents", () => {
    for (const type of [
      "SCORE_HOME_INCREMENT",
      "SCORE_HOME_DECREMENT",
      "SCORE_AWAY_INCREMENT",
      "SCORE_AWAY_DECREMENT",
      "CLOCK_TOGGLE",
      "CLOCK_START",
      "CLOCK_PAUSE",
      "PERIOD_INCREMENT",
      "PERIOD_DECREMENT",
      "HORN_TRIGGER",
    ]) {
      expect(
        isScoreboardControlInputType(
          type,
        ),
      ).toBe(true);
    }
  });

  it("defines server disposition contract", () => {
    const source = fs.readFileSync(
      new URL(
        "../src/scoreboard-control-input-contract.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      '"ACCEPTED"',
    );

    expect(source).toContain(
      '"REJECTED"',
    );

    expect(source).toContain(
      '"IGNORED_DUPLICATE"',
    );
  });

  it("defines firmware-side control input contract", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardControlInput.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "ScoreboardControlInputEvent",
    );

    expect(header).toContain(
      "sequence",
    );

    expect(header).toContain(
      "inputId",
    );
  });

  it("keeps physical control as intent rather than direct authority", () => {
    const readme = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/README.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(readme).toContain(
      "do **not** directly mutate authoritative SportsOS game state",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 14.1 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - shared hardware control-input protocol"
echo "  - score +/- intents"
echo "  - clock start/pause/toggle intents"
echo "  - period +/- intents"
echo "  - horn trigger intent"
echo "  - unique input ID + sequence contract"
echo "  - accepted/rejected/duplicate acknowledgement contract"
echo "  - ESP32-side input model"
echo "  - Milestone 14.1 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run build --workspace @sportsos/core"
echo "  npm run typecheck && npm test"
echo
echo "Then real firmware compile:"
echo "  bash firmware/esp32-scoreboard/build-in-docker.sh"
echo
echo "Next after green:"
echo "  Milestone 14.2 - GPIO Button Input / Debounce Driver"
