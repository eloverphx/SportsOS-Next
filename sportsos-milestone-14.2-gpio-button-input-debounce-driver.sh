#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="14.2-gpio-button-input-debounce-driver"
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
  "$ROOT/firmware/esp32-scoreboard/include/ScoreboardControlInput.h" \
  "$ROOT/firmware/esp32-scoreboard/src/ScoreboardControlInput.cpp" \
  "$ROOT/firmware/esp32-scoreboard/src/main.cpp" \
  "$ROOT/firmware/esp32-scoreboard/build-in-docker.sh"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

DRIVER_H="firmware/esp32-scoreboard/include/GpioButtonInput.h"
DRIVER_CPP="firmware/esp32-scoreboard/src/GpioButtonInput.cpp"
MAIN="firmware/esp32-scoreboard/src/main.cpp"
README="firmware/esp32-scoreboard/README.md"
TEST="packages/core/test/gpio-button-input-debounce-driver-14.2.test.ts"

for file in "$DRIVER_H" "$DRIVER_CPP" "$MAIN" "$README" "$TEST"; do
  if [[ -f "$file" ]]; then
    rel="${file#$ROOT/}"
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$file" "$BACKUP_DIR/$rel"
  fi
done

mkdir -p \
  "$(dirname "$DRIVER_H")" \
  "$(dirname "$DRIVER_CPP")" \
  "$(dirname "$TEST")"

cat > "$DRIVER_H" <<'EOF'
#pragma once

#include <Arduino.h>

#include "ScoreboardControlInput.h"

namespace sportsos {

enum class ButtonActiveLevel : uint8_t {
  Low = LOW,
  High = HIGH,
};

enum class ButtonPinMode : uint8_t {
  Input = INPUT,
  InputPullup = INPUT_PULLUP,
#ifdef INPUT_PULLDOWN
  InputPulldown = INPUT_PULLDOWN,
#endif
};

struct GpioButtonBinding {
  uint8_t pin;
  ScoreboardControlInputType type;
  ButtonActiveLevel activeLevel;
  ButtonPinMode pinMode;
  uint32_t debounceMs;
};

struct GpioButtonEvent {
  uint8_t pin;
  ScoreboardControlInputType type;
  bool pressed;
  unsigned long occurredAtMs;
};

class GpioButtonInput {
 public:
  using EventCallback =
      void (*)(
          const GpioButtonEvent& event,
          void* context);

  GpioButtonInput(
      const GpioButtonBinding* bindings,
      size_t bindingCount);

  void begin();

  void setCallback(
      EventCallback callback,
      void* context);

  void poll(
      unsigned long nowMs);

  size_t bindingCount() const;

 private:
  struct ButtonState {
    int rawLevel;
    int stableLevel;
    unsigned long lastRawChangeMs;
    bool initialized;
  };

  const GpioButtonBinding* bindings_;
  size_t bindingCount_;
  ButtonState* states_;
  EventCallback callback_;
  void* callbackContext_;

  bool isPressed(
      const GpioButtonBinding& binding,
      int level) const;

  void emit(
      size_t index,
      bool pressed,
      unsigned long nowMs);
};

}  // namespace sportsos
EOF

cat > "$DRIVER_CPP" <<'EOF'
#include "GpioButtonInput.h"

namespace sportsos {

GpioButtonInput::GpioButtonInput(
    const GpioButtonBinding* bindings,
    size_t bindingCount)
    : bindings_(bindings),
      bindingCount_(bindingCount),
      states_(nullptr),
      callback_(nullptr),
      callbackContext_(nullptr) {}

void GpioButtonInput::begin() {
  delete[] states_;

  states_ =
      new ButtonState[bindingCount_];

  for (
      size_t index = 0;
      index < bindingCount_;
      ++index
  ) {
    const auto& binding =
        bindings_[index];

    pinMode(
        binding.pin,
        static_cast<uint8_t>(
            binding.pinMode));

    const int level =
        digitalRead(
            binding.pin);

    states_[index] = {
        level,
        level,
        millis(),
        true,
    };
  }
}

void GpioButtonInput::setCallback(
    EventCallback callback,
    void* context) {
  callback_ =
      callback;

  callbackContext_ =
      context;
}

void GpioButtonInput::poll(
    unsigned long nowMs) {
  if (
      states_ == nullptr ||
      bindings_ == nullptr
  ) {
    return;
  }

  for (
      size_t index = 0;
      index < bindingCount_;
      ++index
  ) {
    const auto& binding =
        bindings_[index];

    auto& state =
        states_[index];

    const int rawLevel =
        digitalRead(
            binding.pin);

    if (
        !state.initialized
    ) {
      state.rawLevel =
          rawLevel;

      state.stableLevel =
          rawLevel;

      state.lastRawChangeMs =
          nowMs;

      state.initialized =
          true;

      continue;
    }

    if (
        rawLevel !=
        state.rawLevel
    ) {
      state.rawLevel =
          rawLevel;

      state.lastRawChangeMs =
          nowMs;

      continue;
    }

    if (
        rawLevel ==
        state.stableLevel
    ) {
      continue;
    }

    if (
        nowMs -
            state.lastRawChangeMs <
        binding.debounceMs
    ) {
      continue;
    }

    state.stableLevel =
        rawLevel;

    emit(
        index,
        isPressed(
            binding,
            rawLevel),
        nowMs);
  }
}

size_t
GpioButtonInput::bindingCount() const {
  return bindingCount_;
}

bool GpioButtonInput::isPressed(
    const GpioButtonBinding& binding,
    int level) const {
  return
      level ==
      static_cast<int>(
          binding.activeLevel);
}

void GpioButtonInput::emit(
    size_t index,
    bool pressed,
    unsigned long nowMs) {
  if (
      callback_ == nullptr
  ) {
    return;
  }

  const auto& binding =
      bindings_[index];

  callback_(
      GpioButtonEvent{
          binding.pin,
          binding.type,
          pressed,
          nowMs,
      },
      callbackContext_);
}

}  // namespace sportsos
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "firmware/esp32-scoreboard/src/main.cpp";

let text =
  fs.readFileSync(file, "utf8");

if (!text.includes('#include "GpioButtonInput.h"')) {
  const anchor =
    '#include "ScoreboardControlInput.h"';

  if (text.includes(anchor)) {
    text =
      text.replace(
        anchor,
        `${anchor}\n#include "GpioButtonInput.h"`,
      );
  } else {
    const firstInclude =
      text.match(/^#include .*$/m);

    if (!firstInclude || firstInclude.index === undefined) {
      throw new Error(
        "Unable to locate include insertion point in main.cpp.",
      );
    }

    text =
      text.slice(
        0,
        firstInclude.index,
      ) +
      '#include "GpioButtonInput.h"\n' +
      text.slice(
        firstInclude.index,
      );
  }
}

for (const line of [
  "using sportsos::ButtonActiveLevel;",
  "using sportsos::ButtonPinMode;",
  "using sportsos::GpioButtonBinding;",
  "using sportsos::GpioButtonEvent;",
  "using sportsos::GpioButtonInput;",
]) {
  if (text.includes(line)) {
    continue;
  }

  const matches =
    [...text.matchAll(/^using sportsos::.*?;$/gm)];

  if (matches.length === 0) {
    throw new Error(
      `Unable to add using declaration: ${line}`,
    );
  }

  const last =
    matches[matches.length - 1];

  const insertAt =
    last.index +
    last[0].length;

  text =
    text.slice(0, insertAt) +
    "\n" +
    line +
    text.slice(insertAt);
}

if (
  !text.includes(
    "GpioButtonBinding scoreboardButtonBindings[]",
  )
) {
  const usingMatches =
    [...text.matchAll(/^using sportsos::.*?;$/gm)];

  if (usingMatches.length === 0) {
    throw new Error(
      "Unable to locate using declarations for button globals.",
    );
  }

  const last =
    usingMatches[
      usingMatches.length - 1
    ];

  const insertAt =
    last.index +
    last[0].length;

  const globals = `

#ifndef SPORTSOS_BUTTON_HOME_PLUS_PIN
#define SPORTSOS_BUTTON_HOME_PLUS_PIN 32
#endif

#ifndef SPORTSOS_BUTTON_HOME_MINUS_PIN
#define SPORTSOS_BUTTON_HOME_MINUS_PIN 33
#endif

#ifndef SPORTSOS_BUTTON_AWAY_PLUS_PIN
#define SPORTSOS_BUTTON_AWAY_PLUS_PIN 25
#endif

#ifndef SPORTSOS_BUTTON_AWAY_MINUS_PIN
#define SPORTSOS_BUTTON_AWAY_MINUS_PIN 26
#endif

#ifndef SPORTSOS_BUTTON_CLOCK_TOGGLE_PIN
#define SPORTSOS_BUTTON_CLOCK_TOGGLE_PIN 27
#endif

#ifndef SPORTSOS_BUTTON_PERIOD_PLUS_PIN
#define SPORTSOS_BUTTON_PERIOD_PLUS_PIN 14
#endif

#ifndef SPORTSOS_BUTTON_HORN_PIN
#define SPORTSOS_BUTTON_HORN_PIN 13
#endif

constexpr uint32_t
SPORTSOS_BUTTON_DEBOUNCE_MS = 40;

GpioButtonBinding scoreboardButtonBindings[] = {
    {
        SPORTSOS_BUTTON_HOME_PLUS_PIN,
        ScoreboardControlInputType::ScoreHomeIncrement,
        ButtonActiveLevel::Low,
        ButtonPinMode::InputPullup,
        SPORTSOS_BUTTON_DEBOUNCE_MS,
    },
    {
        SPORTSOS_BUTTON_HOME_MINUS_PIN,
        ScoreboardControlInputType::ScoreHomeDecrement,
        ButtonActiveLevel::Low,
        ButtonPinMode::InputPullup,
        SPORTSOS_BUTTON_DEBOUNCE_MS,
    },
    {
        SPORTSOS_BUTTON_AWAY_PLUS_PIN,
        ScoreboardControlInputType::ScoreAwayIncrement,
        ButtonActiveLevel::Low,
        ButtonPinMode::InputPullup,
        SPORTSOS_BUTTON_DEBOUNCE_MS,
    },
    {
        SPORTSOS_BUTTON_AWAY_MINUS_PIN,
        ScoreboardControlInputType::ScoreAwayDecrement,
        ButtonActiveLevel::Low,
        ButtonPinMode::InputPullup,
        SPORTSOS_BUTTON_DEBOUNCE_MS,
    },
    {
        SPORTSOS_BUTTON_CLOCK_TOGGLE_PIN,
        ScoreboardControlInputType::ClockToggle,
        ButtonActiveLevel::Low,
        ButtonPinMode::InputPullup,
        SPORTSOS_BUTTON_DEBOUNCE_MS,
    },
    {
        SPORTSOS_BUTTON_PERIOD_PLUS_PIN,
        ScoreboardControlInputType::PeriodIncrement,
        ButtonActiveLevel::Low,
        ButtonPinMode::InputPullup,
        SPORTSOS_BUTTON_DEBOUNCE_MS,
    },
    {
        SPORTSOS_BUTTON_HORN_PIN,
        ScoreboardControlInputType::HornTrigger,
        ButtonActiveLevel::Low,
        ButtonPinMode::InputPullup,
        SPORTSOS_BUTTON_DEBOUNCE_MS,
    },
};

GpioButtonInput scoreboardButtons(
    scoreboardButtonBindings,
    sizeof(scoreboardButtonBindings) /
        sizeof(scoreboardButtonBindings[0]));

void onScoreboardButtonEvent(
    const GpioButtonEvent& event,
    void*) {
  /*
   * Milestone 14.2 intentionally emits only PRESS edges.
   * Transport/API submission is introduced in Milestone 14.3.
   */
  if (!event.pressed) {
    return;
  }

  Serial.print(
      "[CONTROL] pin=");

  Serial.print(
      event.pin);

  Serial.print(
      " type=");

  Serial.print(
      ScoreboardControlInput::typeText(
          event.type));

  Serial.print(
      " occurredAtMs=");

  Serial.println(
      event.occurredAtMs);
}
`;

  text =
    text.slice(0, insertAt) +
    globals +
    text.slice(insertAt);
}

if (
  !text.includes(
    "scoreboardButtons.begin();",
  )
) {
  const setupStart =
    text.indexOf(
      "void setup()",
    );

  if (setupStart === -1) {
    throw new Error(
      "Unable to locate void setup().",
    );
  }

  const brace =
    text.indexOf(
      "{",
      setupStart,
    );

  if (brace === -1) {
    throw new Error(
      "Unable to locate setup() opening brace.",
    );
  }

  const setupCode = `
  scoreboardButtons.setCallback(
      onScoreboardButtonEvent,
      nullptr);

  scoreboardButtons.begin();
`;

  text =
    text.slice(
      0,
      brace + 1,
    ) +
    setupCode +
    text.slice(
      brace + 1,
    );
}

if (
  !text.includes(
    "scoreboardButtons.poll(",
  )
) {
  const loopStart =
    text.indexOf(
      "void loop()",
    );

  if (loopStart === -1) {
    throw new Error(
      "Unable to locate void loop().",
    );
  }

  const brace =
    text.indexOf(
      "{",
      loopStart,
    );

  if (brace === -1) {
    throw new Error(
      "Unable to locate loop() opening brace.",
    );
  }

  text =
    text.slice(
      0,
      brace + 1,
    ) +
    `
  scoreboardButtons.poll(
      millis());
` +
    text.slice(
      brace + 1,
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat >> "$README" <<'EOF'

## Milestone 14.2 — GPIO button input / debounce driver

The ESP32 scoreboard firmware now includes a reusable GPIO button driver.

Capabilities:

- configurable GPIO pin per control
- configurable active-high / active-low input
- configurable `INPUT`, `INPUT_PULLUP`, and supported pull-down modes
- per-button debounce interval
- stable press and release edge detection
- no repeated event while a button remains held
- one callback surface for all mapped scoreboard controls

The default hardware profile uses active-low buttons with internal pull-ups and a 40 ms debounce interval.

Default pins:

- GPIO 32 — home score +1
- GPIO 33 — home score -1
- GPIO 25 — away score +1
- GPIO 26 — away score -1
- GPIO 27 — clock toggle
- GPIO 14 — period +1
- GPIO 13 — horn

Each pin can be overridden at compile time using the corresponding `SPORTSOS_BUTTON_*_PIN` macro.

Milestone 14.2 stops at validated local button events. It does **not** yet send those events to the SportsOS API or mutate authoritative game state. Transport and acknowledgement handling are introduced in Milestone 14.3.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.2 GPIO button input / debounce driver", () => {
  const header = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/include/GpioButtonInput.h",
      import.meta.url,
    ),
    "utf8",
  );

  const source = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/GpioButtonInput.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  const main = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/main.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  it("supports configurable active level and pin mode", () => {
    expect(header).toContain(
      "ButtonActiveLevel",
    );

    expect(header).toContain(
      "ButtonPinMode",
    );

    expect(header).toContain(
      "debounceMs",
    );
  });

  it("tracks raw and stable GPIO levels for debounce", () => {
    expect(header).toContain(
      "rawLevel",
    );

    expect(header).toContain(
      "stableLevel",
    );

    expect(header).toContain(
      "lastRawChangeMs",
    );
  });

  it("waits for debounce time before changing stable state", () => {
    expect(source).toContain(
      "nowMs -",
    );

    expect(source).toContain(
      "binding.debounceMs",
    );

    expect(source).toContain(
      "state.stableLevel =",
    );
  });

  it("emits press and release edge state", () => {
    expect(header).toContain(
      "bool pressed",
    );

    expect(source).toContain(
      "emit(",
    );
  });

  it("maps physical buttons to scoreboard control intents", () => {
    for (const intent of [
      "ScoreHomeIncrement",
      "ScoreHomeDecrement",
      "ScoreAwayIncrement",
      "ScoreAwayDecrement",
      "ClockToggle",
      "PeriodIncrement",
      "HornTrigger",
    ]) {
      expect(main).toContain(
        intent,
      );
    }
  });

  it("polls the button driver from firmware loop", () => {
    expect(main).toContain(
      "scoreboardButtons.begin()",
    );

    expect(main).toContain(
      "scoreboardButtons.poll(",
    );
  });

  it("does not claim authoritative mutation in 14.2", () => {
    const readme = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/README.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(readme).toContain(
      "does **not** yet send those events to the SportsOS API or mutate authoritative game state",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 14.2 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - reusable ESP32 GPIO button driver"
echo "  - active-high / active-low configuration"
echo "  - pull-up / input mode configuration"
echo "  - per-button debounce timing"
echo "  - stable press / release edge detection"
echo "  - default scoreboard button pin map"
echo "  - control-intent callback integration"
echo "  - Milestone 14.2 regression tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then real firmware compile:"
echo "  bash firmware/esp32-scoreboard/build-in-docker.sh"
echo
echo "Next after green:"
echo "  Milestone 14.3 - Physical Control Event Transport / API Acknowledgement"
