#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="14.3-control-input-client-include-repair"
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
  "$ROOT/apps/api/src/routes/scoreboardDevices.ts" \
  "$ROOT/apps/api/src/services/automaticGameScoreboardSync.ts" \
  "$ROOT/firmware/esp32-scoreboard/src/main.cpp" \
  "$ROOT/firmware/esp32-scoreboard/include/GpioButtonInput.h"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

MAIN="firmware/esp32-scoreboard/src/main.cpp"
FW_H="firmware/esp32-scoreboard/include/ScoreboardControlInputClient.h"
FW_CPP="firmware/esp32-scoreboard/src/ScoreboardControlInputClient.cpp"
TEST="packages/core/test/control-input-client-include-14.3-repair.test.ts"

for file in "$MAIN" "$FW_H" "$FW_CPP" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
  fi
done

mkdir -p \
  "$(dirname "$FW_H")" \
  "$(dirname "$FW_CPP")" \
  "$(dirname "$TEST")"

cat > "$FW_H" <<'EOF'
#pragma once

#include <Arduino.h>

#include "ScoreboardControlInput.h"

namespace sportsos {

struct ScoreboardControlInputClientConfig {
  const char* apiBaseUrl;
  const char* deviceId;
};

enum class ScoreboardControlSubmitResult : uint8_t {
  Accepted = 0,
  Rejected,
  IgnoredDuplicate,
  TransportError,
  InvalidResponse,
};

class ScoreboardControlInputClient {
 public:
  explicit ScoreboardControlInputClient(
      const ScoreboardControlInputClientConfig& config);

  ScoreboardControlSubmitResult submit(
      ScoreboardControlInputType type,
      uint32_t sequence,
      unsigned long occurredAtMs);

  const String& lastReason() const;
  const String& authoritativeGameId() const;

 private:
  ScoreboardControlInputClientConfig config_;
  String lastReason_;
  String authoritativeGameId_;

  String createInputId(
      uint32_t sequence,
      unsigned long occurredAtMs) const;
};

}  // namespace sportsos
EOF

cat > "$FW_CPP" <<'EOF'
#include "ScoreboardControlInputClient.h"

#include <ArduinoJson.h>
#include <HTTPClient.h>

namespace sportsos {

ScoreboardControlInputClient::ScoreboardControlInputClient(
    const ScoreboardControlInputClientConfig& config)
    : config_(config),
      lastReason_(""),
      authoritativeGameId_("") {}

ScoreboardControlSubmitResult
ScoreboardControlInputClient::submit(
    ScoreboardControlInputType type,
    uint32_t sequence,
    unsigned long occurredAtMs) {
  lastReason_ = "";
  authoritativeGameId_ = "";

  if (
      config_.apiBaseUrl == nullptr ||
      config_.deviceId == nullptr ||
      config_.deviceId[0] == '\0'
  ) {
    return ScoreboardControlSubmitResult::TransportError;
  }

  HTTPClient http;

  const String url =
      String(config_.apiBaseUrl) +
      "/scoreboard-control-inputs";

  if (!http.begin(url)) {
    return ScoreboardControlSubmitResult::TransportError;
  }

  http.addHeader(
      "Content-Type",
      "application/json");

  JsonDocument document;

  document["protocolVersion"] =
      CONTROL_INPUT_PROTOCOL_VERSION;

  document["inputId"] =
      createInputId(
          sequence,
          occurredAtMs);

  document["deviceId"] =
      config_.deviceId;

  document["type"] =
      ScoreboardControlInput::typeText(
          type);

  document["occurredAt"] =
      String(occurredAtMs);

  document["sequence"] =
      sequence;

  String payload;

  serializeJson(
      document,
      payload);

  const int status =
      http.POST(
          payload);

  const String response =
      http.getString();

  http.end();

  if (
      status < 200 ||
      status >= 300
  ) {
    return ScoreboardControlSubmitResult::TransportError;
  }

  JsonDocument responseDocument;

  const auto error =
      deserializeJson(
          responseDocument,
          response);

  if (error) {
    return ScoreboardControlSubmitResult::InvalidResponse;
  }

  const char* disposition =
      responseDocument["data"]["disposition"] |
      "";

  lastReason_ =
      String(
          responseDocument["data"]["reason"] |
          "");

  authoritativeGameId_ =
      String(
          responseDocument["data"]["authoritativeGameId"] |
          "");

  if (
      strcmp(
          disposition,
          "ACCEPTED") == 0
  ) {
    return ScoreboardControlSubmitResult::Accepted;
  }

  if (
      strcmp(
          disposition,
          "REJECTED") == 0
  ) {
    return ScoreboardControlSubmitResult::Rejected;
  }

  if (
      strcmp(
          disposition,
          "IGNORED_DUPLICATE") == 0
  ) {
    return ScoreboardControlSubmitResult::IgnoredDuplicate;
  }

  return ScoreboardControlSubmitResult::InvalidResponse;
}

const String&
ScoreboardControlInputClient::lastReason() const {
  return lastReason_;
}

const String&
ScoreboardControlInputClient::authoritativeGameId() const {
  return authoritativeGameId_;
}

String
ScoreboardControlInputClient::createInputId(
    uint32_t sequence,
    unsigned long occurredAtMs) const {
  return
      String(config_.deviceId) +
      "-" +
      String(sequence) +
      "-" +
      String(occurredAtMs);
}

}  // namespace sportsos
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "firmware/esp32-scoreboard/src/main.cpp";

let text =
  fs.readFileSync(file, "utf8");

const includeLine =
  '#include "ScoreboardControlInputClient.h"';

if (!text.includes(includeLine)) {
  const includes =
    [...text.matchAll(/^#include .*$/gm)];

  if (includes.length === 0) {
    throw new Error(
      "Unable to locate any include directives in main.cpp.",
    );
  }

  const last =
    includes[includes.length - 1];

  const insertAt =
    last.index +
    last[0].length;

  text =
    text.slice(0, insertAt) +
    "\n" +
    includeLine +
    text.slice(insertAt);
}

for (const line of [
  "using sportsos::ScoreboardControlInputClient;",
  "using sportsos::ScoreboardControlInputClientConfig;",
  "using sportsos::ScoreboardControlSubmitResult;",
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
    "ScoreboardControlInputClient* scoreboardControlInputClient",
  )
) {
  const anchor =
    "GpioButtonInput scoreboardButtons(";

  const idx =
    text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate scoreboardButtons global.",
    );
  }

  text =
    text.slice(0, idx) +
    `ScoreboardControlInputClient* scoreboardControlInputClient =
    nullptr;

uint32_t scoreboardControlSequence =
    0;

` +
    text.slice(idx);
}

const callbackStart =
  text.indexOf(
    "void onScoreboardButtonEvent(",
  );

if (callbackStart === -1) {
  throw new Error(
    "Unable to locate onScoreboardButtonEvent().",
  );
}

const callbackOpen =
  text.indexOf(
    "{",
    callbackStart,
  );

let depth = 0;
let callbackEnd = -1;

for (let i = callbackOpen; i < text.length; i += 1) {
  if (text[i] === "{") {
    depth += 1;
  } else if (text[i] === "}") {
    depth -= 1;

    if (depth === 0) {
      callbackEnd = i + 1;
      break;
    }
  }
}

if (callbackEnd === -1) {
  throw new Error(
    "Unable to locate end of onScoreboardButtonEvent().",
  );
}

let callback =
  text.slice(
    callbackStart,
    callbackEnd,
  );

if (
  !callback.includes(
    "scoreboardControlInputClient->submit",
  )
) {
  const pressGate =
`  if (!event.pressed) {
    return;
  }`;

  if (!callback.includes(pressGate)) {
    throw new Error(
      "Unable to locate press-only gate in button callback.",
    );
  }

  callback =
    callback.replace(
      pressGate,
`${pressGate}

  if (
      scoreboardControlInputClient != nullptr
  ) {
    scoreboardControlSequence += 1;

    const auto submitResult =
        scoreboardControlInputClient->submit(
            event.type,
            scoreboardControlSequence,
            event.occurredAtMs);

    Serial.print(
        "[CONTROL] submit=");

    Serial.println(
        static_cast<int>(
            submitResult));
  }`,
    );
}

text =
  text.slice(0, callbackStart) +
  callback +
  text.slice(callbackEnd);

if (
  !text.includes(
    "ScoreboardControlInputClientConfig controlInputClientConfig",
  )
) {
  const setupStart =
    text.indexOf(
      "void setup()",
    );

  const buttonBegin =
    text.indexOf(
      "scoreboardButtons.begin();",
      setupStart,
    );

  if (
    setupStart === -1 ||
    buttonBegin === -1
  ) {
    throw new Error(
      "Unable to locate scoreboard button initialization in setup().",
    );
  }

  const insertAt =
    buttonBegin +
    "scoreboardButtons.begin();".length;

  text =
    text.slice(0, insertAt) +
    `

  ScoreboardControlInputClientConfig
      controlInputClientConfig{
          SPORTSOS_API_BASE_URL,
          persistedConfig.deviceId.c_str(),
      };

  scoreboardControlInputClient =
      new ScoreboardControlInputClient(
          controlInputClientConfig);` +
    text.slice(insertAt);
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.3 control-input client include repair", () => {
  const main = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/main.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  it("includes the control input client directly", () => {
    expect(main).toContain(
      '#include "ScoreboardControlInputClient.h"',
    );
  });

  it("does not depend on ScoreboardControlInput.h being directly included", () => {
    expect(main).toContain(
      "ScoreboardControlInputClient",
    );
  });

  it("submits physical button events through the client", () => {
    expect(main).toContain(
      "scoreboardControlInputClient->submit",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 14.3 include repair installed"
echo "============================================================"
echo
echo "Repair:"
echo "  - removes dependency on a direct ScoreboardControlInput.h include"
echo "  - inserts ScoreboardControlInputClient.h into generic include block"
echo "  - preserves existing API-side 14.3 changes"
echo "  - idempotently wires ESP32 client globals/callback/setup"
echo "  - adds focused regression coverage"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run build --workspace @sportsos/core"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  bash firmware/esp32-scoreboard/build-in-docker.sh"
echo "  docker compose up -d --build api"
