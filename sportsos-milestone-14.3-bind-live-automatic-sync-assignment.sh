#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="14.3-bind-live-automatic-sync-assignment"
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
  "$ROOT/apps/api/src/services/scoreboardDeviceEnrollment.ts" \
  "$ROOT/packages/core/src/scoreboard-control-input-contract.ts" \
  "$ROOT/firmware/esp32-scoreboard/include/GpioButtonInput.h" \
  "$ROOT/firmware/esp32-scoreboard/src/main.cpp"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

SYNC="apps/api/src/services/automaticGameScoreboardSync.ts"
DEVICE_ROUTES="apps/api/src/routes/scoreboardDevices.ts"
CONTROL_SERVICE="apps/api/src/services/scoreboardControlInputs.ts"
CONTROL_ROUTE="apps/api/src/routes/scoreboardControlInputs.ts"
FW_H="firmware/esp32-scoreboard/include/ScoreboardControlInputClient.h"
FW_CPP="firmware/esp32-scoreboard/src/ScoreboardControlInputClient.cpp"
MAIN="firmware/esp32-scoreboard/src/main.cpp"
TEST="packages/core/test/physical-control-live-assignment-binding-14.3.test.ts"

for file in \
  "$SYNC" \
  "$DEVICE_ROUTES" \
  "$CONTROL_SERVICE" \
  "$CONTROL_ROUTE" \
  "$FW_H" \
  "$FW_CPP" \
  "$MAIN" \
  "$TEST"
do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
  fi
done

mkdir -p \
  "$(dirname "$CONTROL_SERVICE")" \
  "$(dirname "$CONTROL_ROUTE")" \
  "$(dirname "$FW_H")" \
  "$(dirname "$FW_CPP")" \
  "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/automaticGameScoreboardSync.ts";

let text =
  fs.readFileSync(file, "utf8");

if (
  !text.includes(
    "public getAssignmentByDeviceId(",
  )
) {
  const marker =
    "  public listAssignments():";

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate listAssignments() in AutomaticGameScoreboardSync.",
    );
  }

  const method = `  public getAssignmentByDeviceId(
    deviceId: string,
  ): GameScoreboardAssignment | null {
    const normalizedDeviceId =
      deviceId.trim();

    return (
      this.listAssignments().find(
        (assignment) =>
          assignment.deviceId ===
          normalizedDeviceId,
      ) ?? null
    );
  }

`;

  text =
    text.slice(0, idx) +
    method +
    text.slice(idx);
}

fs.writeFileSync(file, text);
NODE

cat > "$CONTROL_SERVICE" <<'EOF'
import type {
  ScoreboardControlInputAck,
  ScoreboardControlInputEvent,
} from "@sportsos/core";

import type {
  AutomaticGameScoreboardSync,
} from "./automaticGameScoreboardSync.js";

const recentInputs =
  new Map<
    string,
    {
      sequence: number;
      processedAt: string;
    }
  >();

export function processScoreboardControlInput(
  event: ScoreboardControlInputEvent,
  automaticSync: AutomaticGameScoreboardSync,
): ScoreboardControlInputAck {
  const processedAt =
    new Date().toISOString();

  const assignment =
    automaticSync
      .getAssignmentByDeviceId(
        event.deviceId,
      );

  const previous =
    recentInputs.get(
      event.deviceId,
    );

  if (
    previous &&
    event.sequence <=
      previous.sequence
  ) {
    return {
      inputId:
        event.inputId,
      deviceId:
        event.deviceId,
      disposition:
        "IGNORED_DUPLICATE",
      reason:
        "Sequence already processed.",
      authoritativeGameId:
        assignment?.gameId ?? null,
      processedAt,
    };
  }

  if (!assignment) {
    return {
      inputId:
        event.inputId,
      deviceId:
        event.deviceId,
      disposition:
        "REJECTED",
      reason:
        "Scoreboard device is not assigned to a game.",
      authoritativeGameId:
        null,
      processedAt,
    };
  }

  recentInputs.set(
    event.deviceId,
    {
      sequence:
        event.sequence,
      processedAt,
    },
  );

  return {
    inputId:
      event.inputId,
    deviceId:
      event.deviceId,
    disposition:
      "ACCEPTED",
    reason:
      null,
    authoritativeGameId:
      assignment.gameId,
    processedAt,
  };
}
EOF

cat > "$CONTROL_ROUTE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import {
  SCOREBOARD_CONTROL_INPUT_PROTOCOL_VERSION,
  isScoreboardControlInputType,
  type ScoreboardControlInputEvent,
} from "@sportsos/core";

import type {
  AutomaticGameScoreboardSync,
} from "../services/automaticGameScoreboardSync.js";

import {
  isVerifiedDevice,
} from "../services/scoreboardDeviceEnrollment.js";

import {
  processScoreboardControlInput,
} from "../services/scoreboardControlInputs.js";

export async function registerScoreboardControlInputRoutes(
  app: FastifyInstance,
  automaticSync: AutomaticGameScoreboardSync,
) {
  app.post(
    "/scoreboard-control-inputs",
    async (request, reply) => {
      const body =
        request.body as ScoreboardControlInputEvent;

      if (
        !body?.inputId ||
        !body?.deviceId ||
        !body?.type ||
        !body?.occurredAt ||
        !Number.isInteger(
          body?.sequence,
        ) ||
        body.sequence <= 0
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Invalid scoreboard control input.",
        });
      }

      if (
        body.protocolVersion !==
        SCOREBOARD_CONTROL_INPUT_PROTOCOL_VERSION
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Unsupported scoreboard control input protocol version.",
        });
      }

      if (
        !isScoreboardControlInputType(
          body.type,
        )
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Unsupported scoreboard control input type.",
        });
      }

      if (
        !isVerifiedDevice(
          body.deviceId,
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Verified scoreboard device required.",
        });
      }

      return {
        success: true,
        data:
          processScoreboardControlInput(
            body,
            automaticSync,
          ),
      };
    },
  );
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardDevices.ts";

let text =
  fs.readFileSync(file, "utf8");

const importLine =
  'import { registerScoreboardControlInputRoutes } from "./scoreboardControlInputs.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate import block in scoreboardDevices.ts.",
    );
  }

  text =
    text.replace(
      imports[0],
      imports[0] +
        importLine +
        "\n",
    );
}

if (
  !text.includes(
    "await registerScoreboardControlInputRoutes(app, automaticSync);",
  )
) {
  /*
   * scoreboardDevices.ts already owns the live automaticSync instance.
   * Insert registration inside the exported route function, immediately
   * before its closing brace.
   */
  const exportMarker =
    "export async function scoreboardDevicesRoutes";

  const start =
    text.indexOf(exportMarker);

  if (start === -1) {
    throw new Error(
      "Unable to locate scoreboardDevicesRoutes export.",
    );
  }

  const open =
    text.indexOf("{", start);

  if (open === -1) {
    throw new Error(
      "Unable to locate scoreboardDevicesRoutes opening brace.",
    );
  }

  let depth = 0;
  let end = -1;

  for (let i = open; i < text.length; i += 1) {
    if (text[i] === "{") {
      depth += 1;
    } else if (text[i] === "}") {
      depth -= 1;

      if (depth === 0) {
        end = i;
        break;
      }
    }
  }

  if (end === -1) {
    throw new Error(
      "Unable to locate scoreboardDevicesRoutes closing brace.",
    );
  }

  const functionBlock =
    text.slice(start, end);

  if (
    !functionBlock.includes(
      "automaticSync",
    )
  ) {
    throw new Error(
      "scoreboardDevicesRoutes does not expose automaticSync in function scope.",
    );
  }

  text =
    text.slice(0, end) +
    `  await registerScoreboardControlInputRoutes(
    app,
    automaticSync,
  );

` +
    text.slice(end);
}

fs.writeFileSync(file, text);
NODE

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
  lastReason_ =
      "";

  authoritativeGameId_ =
      "";

  if (
      config_.apiBaseUrl == nullptr ||
      config_.deviceId == nullptr ||
      config_.deviceId[0] == '\0'
  ) {
    return
        ScoreboardControlSubmitResult::TransportError;
  }

  HTTPClient http;

  const String url =
      String(config_.apiBaseUrl) +
      "/scoreboard-control-inputs";

  if (!http.begin(url)) {
    return
        ScoreboardControlSubmitResult::TransportError;
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
    return
        ScoreboardControlSubmitResult::TransportError;
  }

  JsonDocument responseDocument;

  const auto error =
      deserializeJson(
          responseDocument,
          response);

  if (error) {
    return
        ScoreboardControlSubmitResult::InvalidResponse;
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
    return
        ScoreboardControlSubmitResult::Accepted;
  }

  if (
      strcmp(
          disposition,
          "REJECTED") == 0
  ) {
    return
        ScoreboardControlSubmitResult::Rejected;
  }

  if (
      strcmp(
          disposition,
          "IGNORED_DUPLICATE") == 0
  ) {
    return
        ScoreboardControlSubmitResult::IgnoredDuplicate;
  }

  return
      ScoreboardControlSubmitResult::InvalidResponse;
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

if (
  !text.includes(
    '#include "ScoreboardControlInputClient.h"',
  )
) {
  const anchor =
    '#include "ScoreboardControlInput.h"';

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate ScoreboardControlInput include.",
    );
  }

  text =
    text.replace(
      anchor,
      anchor +
        '\n#include "ScoreboardControlInputClient.h"',
    );
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

for (
  let i = callbackOpen;
  i < text.length;
  i += 1
) {
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
    "Unable to locate button callback end.",
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
      "Unable to locate button press gate.",
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
      "Unable to locate scoreboard button initialization.",
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

describe("Milestone 14.3 live automatic-sync assignment binding", () => {
  it("adds a by-device lookup to the authoritative assignment owner", () => {
    const sync = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/automaticGameScoreboardSync.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(sync).toContain(
      "public getAssignmentByDeviceId(",
    );

    expect(sync).toContain(
      "this.listAssignments().find",
    );
  });

  it("injects the live automaticSync instance into control processing", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardControlInputs.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "automaticSync: AutomaticGameScoreboardSync",
    );

    expect(service).toContain(
      ".getAssignmentByDeviceId(",
    );
  });

  it("registers control routes from scoreboardDevices where automaticSync is live", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "registerScoreboardControlInputRoutes",
    );

    expect(routes).toContain(
      "automaticSync",
    );
  });

  it("keeps verified-device and duplicate protections", () => {
    const route = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardControlInputs.ts",
        import.meta.url,
      ),
      "utf8",
    );

    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardControlInputs.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain(
      "isVerifiedDevice",
    );

    expect(service).toContain(
      "IGNORED_DUPLICATE",
    );
  });

  it("parses authoritative acknowledgement on ESP32", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardControlInputClient.cpp",
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

    expect(source).toContain(
      "authoritativeGameId",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 14.3 live assignment binding installed"
echo "============================================================"
echo
echo "Bound to existing architecture:"
echo "  - AutomaticGameScoreboardSync remains assignment source of truth"
echo "  - adds getAssignmentByDeviceId() to the existing class"
echo "  - control route receives the same live automaticSync instance"
echo "  - no duplicate assignment registry is created"
echo
echo "14.3 capabilities:"
echo "  - POST /scoreboard-control-inputs"
echo "  - protocol/type validation"
echo "  - verified-device enforcement"
echo "  - authoritative assignment validation"
echo "  - duplicate sequence acknowledgement"
echo "  - ESP32 acknowledgement parsing"
echo "  - ACCEPTED / REJECTED / IGNORED_DUPLICATE"
echo
echo "Important:"
echo "  - still does NOT mutate game state"
echo "  - authoritative command binding is Milestone 14.4"
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
