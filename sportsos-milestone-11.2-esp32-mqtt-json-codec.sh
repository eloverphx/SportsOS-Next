#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="11.2-esp32-mqtt-json-codec"
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
  "$ROOT/firmware/esp32-scoreboard/src/ScoreboardProtocol.cpp"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

FW_DIR="firmware/esp32-scoreboard"
HEADER="$FW_DIR/include/ScoreboardMqttCodec.h"
SOURCE="$FW_DIR/src/ScoreboardMqttCodec.cpp"
PLATFORMIO="$FW_DIR/platformio.ini"
README="$FW_DIR/README.md"
TEST="packages/core/test/esp32-mqtt-json-codec-11.2.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$HEADER")" \
  "$BACKUP_DIR/$(dirname "$SOURCE")" \
  "$BACKUP_DIR/$(dirname "$PLATFORMIO")" \
  "$BACKUP_DIR/$(dirname "$README")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$HEADER")" \
  "$(dirname "$SOURCE")" \
  "$(dirname "$TEST")"

for file in "$HEADER" "$SOURCE" "$PLATFORMIO" "$README" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$HEADER" <<'EOF'
#pragma once

#include <stddef.h>
#include <stdint.h>

#include "ScoreboardProtocol.h"

namespace sportsos {

struct MqttAcknowledgement {
  char commandId[64];
  CommandStatus status;
  char message[128];
  char acknowledgedAt[40];
};

struct MqttPresence {
  bool online;
  char reportedAt[40];
};

struct MqttTelemetry {
  char firmwareVersion[32];
  char ipAddress[48];
  int32_t wifiRssi;
  uint32_t uptimeSeconds;
  uint32_t freeHeapBytes;
  char reportedAt[40];
};

class ScoreboardMqttCodec {
 public:
  static bool parseCommand(
      const char* json,
      ParsedCommand& command,
      char* error,
      size_t errorSize);

  static bool encodeState(
      const ScoreboardState& state,
      const char* updatedAt,
      char* output,
      size_t outputSize);

  static bool encodeAcknowledgement(
      const MqttAcknowledgement& acknowledgement,
      char* output,
      size_t outputSize);

  static bool encodePresence(
      const MqttPresence& presence,
      char* output,
      size_t outputSize);

  static bool encodeTelemetry(
      const MqttTelemetry& telemetry,
      char* output,
      size_t outputSize);
};

}  // namespace sportsos
EOF

cat > "$SOURCE" <<'EOF'
#include "ScoreboardMqttCodec.h"

#include <ArduinoJson.h>
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

void setError(
    char* error,
    size_t errorSize,
    const char* message) {
  copyText(
      error,
      errorSize,
      message);
}

CommandType parseCommandType(
    const char* type) {
  if (type == nullptr) {
    return CommandType::Unknown;
  }

  if (strcmp(type, "SET_GAME") == 0) {
    return CommandType::SetGame;
  }

  if (strcmp(type, "SET_SCORE") == 0) {
    return CommandType::SetScore;
  }

  if (strcmp(type, "SET_CLOCK") == 0) {
    return CommandType::SetClock;
  }

  if (strcmp(type, "SET_PERIOD") == 0) {
    return CommandType::SetPeriod;
  }

  if (strcmp(type, "HORN") == 0) {
    return CommandType::Horn;
  }

  if (strcmp(type, "SYNC_STATE") == 0) {
    return CommandType::SyncState;
  }

  return CommandType::Unknown;
}

const char* statusText(
    CommandStatus status) {
  switch (status) {
    case CommandStatus::Accepted:
      return "ACCEPTED";
    case CommandStatus::Rejected:
      return "REJECTED";
    case CommandStatus::Applied:
      return "APPLIED";
    default:
      return "REJECTED";
  }
}

void encodeClock(
    JsonObject object,
    const ClockState& clock) {
  object["remainingMs"] =
      clock.remainingMs;
  object["running"] =
      clock.running;
}

void encodeStateFields(
    JsonObject object,
    const ScoreboardState& state) {
  object["protocolVersion"] =
      state.protocolVersion;
  object["deviceId"] =
      state.deviceId;

  if (state.hasGame) {
    object["gameId"] =
        state.gameId;
  } else {
    object["gameId"] = nullptr;
  }

  object["homeScore"] =
      state.homeScore;
  object["awayScore"] =
      state.awayScore;

  if (state.hasPeriod) {
    object["period"] =
        state.period;
  } else {
    object["period"] = nullptr;
  }

  JsonObject clock =
      object["clock"]
          .to<JsonObject>();

  encodeClock(
      clock,
      state.clock);

  object["hornActive"] =
      state.hornActive;
}

bool serialize(
    JsonDocument& document,
    char* output,
    size_t outputSize) {
  if (
      output == nullptr ||
      outputSize == 0
  ) {
    return false;
  }

  const size_t required =
      measureJson(document) + 1;

  if (required > outputSize) {
    output[0] = '\0';
    return false;
  }

  serializeJson(
      document,
      output,
      outputSize);

  return true;
}

}  // namespace

bool ScoreboardMqttCodec::parseCommand(
    const char* json,
    ParsedCommand& command,
    char* error,
    size_t errorSize) {
  memset(
      &command,
      0,
      sizeof(command));

  if (json == nullptr) {
    setError(
        error,
        errorSize,
        "Command JSON is null.");
    return false;
  }

  JsonDocument document;

  const DeserializationError parseError =
      deserializeJson(
          document,
          json);

  if (parseError) {
    setError(
        error,
        errorSize,
        "Invalid JSON.");
    return false;
  }

  command.protocolVersion =
      document["protocolVersion"] | 0;

  copyText(
      command.commandId,
      sizeof(command.commandId),
      document["commandId"] | "");

  command.type =
      parseCommandType(
          document["type"] | "");

  if (
      command.protocolVersion !=
      SCOREBOARD_PROTOCOL_VERSION
  ) {
    setError(
        error,
        errorSize,
        "Protocol version mismatch.");
    return false;
  }

  if (command.commandId[0] == '\0') {
    setError(
        error,
        errorSize,
        "commandId is required.");
    return false;
  }

  if (
      command.type ==
      CommandType::Unknown
  ) {
    setError(
        error,
        errorSize,
        "Unsupported command type.");
    return false;
  }

  switch (command.type) {
    case CommandType::SetGame: {
      const char* gameId =
          document["gameId"];

      command.hasGame =
          gameId != nullptr &&
          gameId[0] != '\0';

      copyText(
          command.gameId,
          sizeof(command.gameId),
          command.hasGame
              ? gameId
              : "");

      break;
    }

    case CommandType::SetScore:
      command.homeScore =
          document["homeScore"] | 0;
      command.awayScore =
          document["awayScore"] | 0;
      break;

    case CommandType::SetClock:
      command.remainingMs =
          document["remainingMs"] | 0;
      command.clockRunning =
          document["running"] | false;
      break;

    case CommandType::SetPeriod:
      command.hasPeriod =
          !document["period"].isNull();

      command.period =
          command.hasPeriod
              ? document["period"].as<uint8_t>()
              : 0;

      break;

    case CommandType::Horn:
      command.hornActive =
          document["active"] | false;
      break;

    case CommandType::SyncState: {
      JsonObjectConst snapshot =
          document["snapshot"]
              .as<JsonObjectConst>();

      if (snapshot.isNull()) {
        setError(
            error,
            errorSize,
            "SYNC_STATE snapshot is required.");
        return false;
      }

      command.syncState.protocolVersion =
          snapshot["protocolVersion"] | 0;

      copyText(
          command.syncState.deviceId,
          sizeof(command.syncState.deviceId),
          snapshot["deviceId"] | "");

      const char* gameId =
          snapshot["gameId"];

      command.syncState.hasGame =
          gameId != nullptr &&
          gameId[0] != '\0';

      copyText(
          command.syncState.gameId,
          sizeof(command.syncState.gameId),
          command.syncState.hasGame
              ? gameId
              : "");

      command.syncState.homeScore =
          snapshot["homeScore"] | 0;
      command.syncState.awayScore =
          snapshot["awayScore"] | 0;

      command.syncState.hasPeriod =
          !snapshot["period"].isNull();

      command.syncState.period =
          command.syncState.hasPeriod
              ? snapshot["period"]
                    .as<uint8_t>()
              : 0;

      JsonObjectConst clock =
          snapshot["clock"]
              .as<JsonObjectConst>();

      command.syncState.clock.remainingMs =
          clock["remainingMs"] | 0;
      command.syncState.clock.running =
          clock["running"] | false;

      command.syncState.hornActive =
          snapshot["hornActive"] | false;

      break;
    }

    case CommandType::Unknown:
    default:
      setError(
          error,
          errorSize,
          "Unsupported command type.");
      return false;
  }

  setError(
      error,
      errorSize,
      "");

  return true;
}

bool ScoreboardMqttCodec::encodeState(
    const ScoreboardState& state,
    const char* updatedAt,
    char* output,
    size_t outputSize) {
  JsonDocument document;

  JsonObject root =
      document.to<JsonObject>();

  encodeStateFields(
      root,
      state);

  root["updatedAt"] =
      updatedAt != nullptr
          ? updatedAt
          : "";

  return serialize(
      document,
      output,
      outputSize);
}

bool ScoreboardMqttCodec::encodeAcknowledgement(
    const MqttAcknowledgement& acknowledgement,
    char* output,
    size_t outputSize) {
  JsonDocument document;

  document["commandId"] =
      acknowledgement.commandId;
  document["status"] =
      statusText(
          acknowledgement.status);

  if (
      acknowledgement.message[0] != '\0'
  ) {
    document["message"] =
        acknowledgement.message;
  } else {
    document["message"] = nullptr;
  }

  document["acknowledgedAt"] =
      acknowledgement.acknowledgedAt;

  return serialize(
      document,
      output,
      outputSize);
}

bool ScoreboardMqttCodec::encodePresence(
    const MqttPresence& presence,
    char* output,
    size_t outputSize) {
  JsonDocument document;

  document["online"] =
      presence.online;
  document["reportedAt"] =
      presence.reportedAt;

  return serialize(
      document,
      output,
      outputSize);
}

bool ScoreboardMqttCodec::encodeTelemetry(
    const MqttTelemetry& telemetry,
    char* output,
    size_t outputSize) {
  JsonDocument document;

  document["firmwareVersion"] =
      telemetry.firmwareVersion;
  document["ipAddress"] =
      telemetry.ipAddress;
  document["wifiRssi"] =
      telemetry.wifiRssi;
  document["uptimeSeconds"] =
      telemetry.uptimeSeconds;
  document["freeHeapBytes"] =
      telemetry.freeHeapBytes;
  document["reportedAt"] =
      telemetry.reportedAt;

  return serialize(
      document,
      output,
      outputSize);
}

}  // namespace sportsos
EOF

cat > "$PLATFORMIO" <<'EOF'
[platformio]
default_envs = esp32dev

[env:esp32dev]
platform = espressif32
board = esp32dev
framework = arduino
monitor_speed = 115200

lib_deps =
  bblanchon/ArduinoJson@^7.2.1

build_flags =
  -D SPORTSOS_FIRMWARE_VERSION=\"0.11.2\"
EOF

cat >> "$README" <<'EOF'

## Milestone 11.2 — MQTT JSON codec

The firmware now contains a JSON codec compatible with the SportsOS scoreboard MQTT contract.

### Command parsing

Supported JSON command types:

- `SET_GAME`
- `SET_SCORE`
- `SET_CLOCK`
- `SET_PERIOD`
- `HORN`
- `SYNC_STATE`

Required command fields include:

- `protocolVersion`
- `commandId`
- `type`

### Device publications

The codec can serialize:

- authoritative device state
- command acknowledgements
- retained presence state
- telemetry

ArduinoJson is used only for serialization/deserialization. The underlying scoreboard state machine remains independent of the JSON library and hardware drivers.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.2 ESP32 MQTT JSON codec", () => {
  it("declares command parsing and device serializers", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardMqttCodec.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "parseCommand",
    );
    expect(header).toContain(
      "encodeState",
    );
    expect(header).toContain(
      "encodeAcknowledgement",
    );
    expect(header).toContain(
      "encodePresence",
    );
    expect(header).toContain(
      "encodeTelemetry",
    );
  });

  it("maps every protocol command type", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardMqttCodec.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    for (const type of [
      "SET_GAME",
      "SET_SCORE",
      "SET_CLOCK",
      "SET_PERIOD",
      "HORN",
      "SYNC_STATE",
    ]) {
      expect(source).toContain(type);
    }
  });

  it("enforces protocol version and commandId", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardMqttCodec.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "Protocol version mismatch.",
    );
    expect(source).toContain(
      "commandId is required.",
    );
  });

  it("serializes the Milestone 10 telemetry contract", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardMqttCodec.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    for (const field of [
      "firmwareVersion",
      "ipAddress",
      "wifiRssi",
      "uptimeSeconds",
      "freeHeapBytes",
      "reportedAt",
    ]) {
      expect(source).toContain(
        `document["${field}"]`,
      );
    }
  });

  it("uses ArduinoJson through PlatformIO", () => {
    const platformio = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/platformio.ini",
        import.meta.url,
      ),
      "utf8",
    );

    expect(platformio).toContain(
      "bblanchon/ArduinoJson",
    );
    expect(platformio).toContain(
      "framework = arduino",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 11.2 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - prerequisite 11.1 firmware verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - ScoreboardMqttCodec.h/.cpp"
echo "  - JSON command parser"
echo "  - SET_GAME / SET_SCORE / SET_CLOCK / SET_PERIOD decoding"
echo "  - HORN / SYNC_STATE decoding"
echo "  - state serialization"
echo "  - ACCEPTED / REJECTED / APPLIED acknowledgement serialization"
echo "  - presence serialization"
echo "  - telemetry serialization"
echo "  - PlatformIO ArduinoJson dependency"
echo "  - Milestone 11.2 contract tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Optional firmware compile if PlatformIO is installed:"
echo "  cd firmware/esp32-scoreboard && pio run"
echo
echo "Next after green:"
echo "  Milestone 11.3 - ESP32 Wi-Fi / MQTT Runtime"
