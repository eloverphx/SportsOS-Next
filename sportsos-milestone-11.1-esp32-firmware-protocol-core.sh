#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="11.1-esp32-firmware-protocol-core"
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
  "$ROOT/apps" \
  "$ROOT/packages/core"
do
  [[ -e "$required" ]] || {
    echo "ERROR: repository safety marker missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

FW_DIR="firmware/esp32-scoreboard"
HEADER="$FW_DIR/include/ScoreboardProtocol.h"
SOURCE="$FW_DIR/src/ScoreboardProtocol.cpp"
README="$FW_DIR/README.md"
TEST="packages/core/test/esp32-firmware-protocol-11.1.test.ts"

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

#include <stdint.h>
#include <stddef.h>

namespace sportsos {

static constexpr uint8_t SCOREBOARD_PROTOCOL_VERSION = 1;

enum class ConnectionState : uint8_t {
  Offline = 0,
  Connecting = 1,
  Online = 2,
  Degraded = 3,
};

struct ClockState {
  uint32_t remainingMs;
  bool running;
};

struct ScoreboardState {
  uint8_t protocolVersion;
  char deviceId[64];
  char gameId[64];
  bool hasGame;
  ConnectionState connectionState;
  uint16_t homeScore;
  uint16_t awayScore;
  uint8_t period;
  bool hasPeriod;
  ClockState clock;
  bool hornActive;
};

enum class CommandType : uint8_t {
  Unknown = 0,
  SetGame,
  SetScore,
  SetClock,
  SetPeriod,
  Horn,
  SyncState,
};

struct ParsedCommand {
  uint8_t protocolVersion;
  char commandId[64];
  CommandType type;

  char gameId[64];
  bool hasGame;

  uint16_t homeScore;
  uint16_t awayScore;

  uint32_t remainingMs;
  bool clockRunning;

  uint8_t period;
  bool hasPeriod;

  bool hornActive;

  ScoreboardState syncState;
};

enum class CommandStatus : uint8_t {
  Accepted = 0,
  Rejected = 1,
  Applied = 2,
};

struct CommandResult {
  CommandStatus status;
  char message[128];
};

class ScoreboardProtocol {
 public:
  explicit ScoreboardProtocol(const char* deviceId);

  const ScoreboardState& state() const;

  CommandResult apply(const ParsedCommand& command);

  void setConnectionState(ConnectionState state);

  void tick(uint32_t elapsedMs);

  void clearHorn();

 private:
  ScoreboardState state_;

  CommandResult reject(const char* message) const;
  CommandResult applied() const;

  bool validateBase(const ParsedCommand& command) const;
};

}  // namespace sportsos
EOF

cat > "$SOURCE" <<'EOF'
#include "ScoreboardProtocol.h"

#include <string.h>

namespace sportsos {

namespace {

void copyText(
    char* destination,
    size_t destinationSize,
    const char* source) {
  if (destinationSize == 0) {
    return;
  }

  if (source == nullptr) {
    destination[0] = '\0';
    return;
  }

  strncpy(
      destination,
      source,
      destinationSize - 1);

  destination[
      destinationSize - 1] = '\0';
}

CommandResult makeResult(
    CommandStatus status,
    const char* message) {
  CommandResult result{};
  result.status = status;

  copyText(
      result.message,
      sizeof(result.message),
      message);

  return result;
}

}  // namespace

ScoreboardProtocol::ScoreboardProtocol(
    const char* deviceId) {
  memset(&state_, 0, sizeof(state_));

  state_.protocolVersion =
      SCOREBOARD_PROTOCOL_VERSION;

  copyText(
      state_.deviceId,
      sizeof(state_.deviceId),
      deviceId);

  state_.connectionState =
      ConnectionState::Offline;

  state_.clock.remainingMs = 0;
  state_.clock.running = false;
}

const ScoreboardState&
ScoreboardProtocol::state() const {
  return state_;
}

bool ScoreboardProtocol::validateBase(
    const ParsedCommand& command) const {
  return
      command.protocolVersion ==
          SCOREBOARD_PROTOCOL_VERSION &&
      command.commandId[0] != '\0';
}

CommandResult
ScoreboardProtocol::reject(
    const char* message) const {
  return makeResult(
      CommandStatus::Rejected,
      message);
}

CommandResult
ScoreboardProtocol::applied() const {
  return makeResult(
      CommandStatus::Applied,
      nullptr);
}

CommandResult
ScoreboardProtocol::apply(
    const ParsedCommand& command) {
  if (!validateBase(command)) {
    return reject(
        "Invalid command protocol or commandId.");
  }

  switch (command.type) {
    case CommandType::SetGame:
      state_.hasGame =
          command.hasGame;

      copyText(
          state_.gameId,
          sizeof(state_.gameId),
          command.hasGame
              ? command.gameId
              : "");

      return applied();

    case CommandType::SetScore:
      state_.homeScore =
          command.homeScore;
      state_.awayScore =
          command.awayScore;

      return applied();

    case CommandType::SetClock:
      state_.clock.remainingMs =
          command.remainingMs;
      state_.clock.running =
          command.clockRunning;

      return applied();

    case CommandType::SetPeriod:
      state_.hasPeriod =
          command.hasPeriod;
      state_.period =
          command.hasPeriod
              ? command.period
              : 0;

      return applied();

    case CommandType::Horn:
      state_.hornActive =
          command.hornActive;

      return applied();

    case CommandType::SyncState:
      if (
          command.syncState.protocolVersion !=
          SCOREBOARD_PROTOCOL_VERSION
      ) {
        return reject(
            "SYNC_STATE protocol version mismatch.");
      }

      state_.hasGame =
          command.syncState.hasGame;

      copyText(
          state_.gameId,
          sizeof(state_.gameId),
          command.syncState.hasGame
              ? command.syncState.gameId
              : "");

      state_.homeScore =
          command.syncState.homeScore;
      state_.awayScore =
          command.syncState.awayScore;
      state_.hasPeriod =
          command.syncState.hasPeriod;
      state_.period =
          command.syncState.period;
      state_.clock =
          command.syncState.clock;
      state_.hornActive =
          command.syncState.hornActive;

      return applied();

    case CommandType::Unknown:
    default:
      return reject(
          "Unsupported command type.");
  }
}

void ScoreboardProtocol::setConnectionState(
    ConnectionState state) {
  state_.connectionState = state;
}

void ScoreboardProtocol::tick(
    uint32_t elapsedMs) {
  if (!state_.clock.running) {
    return;
  }

  if (
      elapsedMs >=
      state_.clock.remainingMs
  ) {
    state_.clock.remainingMs = 0;
    state_.clock.running = false;
    return;
  }

  state_.clock.remainingMs -=
      elapsedMs;
}

void ScoreboardProtocol::clearHorn() {
  state_.hornActive = false;
}

}  // namespace sportsos
EOF

cat > "$README" <<'EOF'
# SportsOS ESP32 Scoreboard Firmware

Milestone 11.1 establishes the hardware-independent firmware protocol core.

## Design rules

- SportsOS remains authoritative.
- ESP32 maintains a local display copy of the latest authoritative state.
- MQTT protocol version is currently `1`.
- Device state includes game assignment, score, period, clock and horn state.
- Local clock ticking is presentation behavior only; new server state always re-anchors it.
- Reconnect recovery is handled by the SportsOS API/MQTT gateway.
- Hardware pin mappings are intentionally not defined in Milestone 11.1.

## Supported commands

- `SET_GAME`
- `SET_SCORE`
- `SET_CLOCK`
- `SET_PERIOD`
- `HORN`
- `SYNC_STATE`

## Next firmware milestones

Milestone 11.2 will add JSON/MQTT serialization and parsing compatible with the SportsOS 10.x device contract.

Later firmware milestones will add Wi-Fi provisioning, MQTT connection management, display drivers, horn output, watchdog/recovery and OTA updating.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.1 ESP32 firmware protocol core", () => {
  it("defines protocol version 1", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardProtocol.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "SCOREBOARD_PROTOCOL_VERSION = 1",
    );
  });

  it("supports all SportsOS device commands", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardProtocol.h",
        import.meta.url,
      ),
      "utf8",
    );

    for (const command of [
      "SetGame",
      "SetScore",
      "SetClock",
      "SetPeriod",
      "Horn",
      "SyncState",
    ]) {
      expect(header).toContain(command);
    }
  });

  it("implements local clock projection without changing server authority", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardProtocol.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "ScoreboardProtocol::tick",
    );
    expect(source).toContain(
      "state_.clock.remainingMs",
    );
    expect(source).toContain(
      "state_.clock.running = false",
    );
  });

  it("implements full state synchronization", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardProtocol.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "CommandType::SyncState",
    );
    expect(source).toContain(
      "command.syncState.homeScore",
    );
    expect(source).toContain(
      "command.syncState.clock",
    );
  });

  it("does not hardcode hardware pins in the protocol core", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardProtocol.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).not.toMatch(
      /\bGPIO\b|\bPIN_[A-Z_]+\b/,
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 11.1 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - .git / package.json / apps verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - firmware/esp32-scoreboard"
echo "  - hardware-independent C++ scoreboard state machine"
echo "  - protocol version 1"
echo "  - SET_GAME / SET_SCORE / SET_CLOCK / SET_PERIOD"
echo "  - HORN / SYNC_STATE support"
echo "  - local clock projection"
echo "  - no hardware pin assumptions"
echo "  - Milestone 11.1 contract tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Next after green:"
echo "  Milestone 11.2 - ESP32 MQTT JSON Codec"
