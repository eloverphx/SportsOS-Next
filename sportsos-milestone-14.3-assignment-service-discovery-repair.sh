#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="14.3-assignment-service-discovery-repair"
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
  "$ROOT/apps/api/src/app.ts" \
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

DISCOVERY_FILE="$(mktemp)"
trap 'rm -f "$DISCOVERY_FILE"' EXIT

node > "$DISCOVERY_FILE" <<'NODE'
const fs = require("fs");
const path = require("path");

const root =
  "apps/api/src";

const files = [];

function walk(dir) {
  for (const entry of fs.readdirSync(dir, {
    withFileTypes: true,
  })) {
    const full =
      path.join(
        dir,
        entry.name,
      );

    if (entry.isDirectory()) {
      walk(full);
      continue;
    }

    if (
      entry.isFile() &&
      entry.name.endsWith(".ts")
    ) {
      files.push(full);
    }
  }
}

walk(root);

const directNames = [
  "getScoreboardDeviceAssignmentByDeviceId",
  "getScoreboardDeviceAssignment",
  "findScoreboardDeviceAssignmentByDeviceId",
  "getAssignmentForDevice",
  "getDeviceAssignment",
  "findDeviceAssignment",
];

const listNames = [
  "listScoreboardDeviceAssignments",
  "getScoreboardDeviceAssignments",
  "listDeviceAssignments",
  "getDeviceAssignments",
];

let found = null;

for (const file of files) {
  const text =
    fs.readFileSync(
      file,
      "utf8",
    );

  if (
    !text.includes("deviceId") ||
    !text.includes("gameId")
  ) {
    continue;
  }

  for (const name of directNames) {
    const patterns = [
      new RegExp(
        `export\\s+(?:async\\s+)?function\\s+${name}\\b`,
      ),
      new RegExp(
        `export\\s+const\\s+${name}\\b`,
      ),
    ];

    if (
      patterns.some(
        (pattern) =>
          pattern.test(text),
      )
    ) {
      found = {
        kind: "direct",
        file,
        exportName: name,
      };
      break;
    }
  }

  if (found) {
    break;
  }
}

if (!found) {
  for (const file of files) {
    const text =
      fs.readFileSync(
        file,
        "utf8",
      );

    if (
      !text.includes("deviceId") ||
      !text.includes("gameId")
    ) {
      continue;
    }

    for (const name of listNames) {
      const patterns = [
        new RegExp(
          `export\\s+(?:async\\s+)?function\\s+${name}\\b`,
        ),
        new RegExp(
          `export\\s+const\\s+${name}\\b`,
        ),
      ];

      if (
        patterns.some(
          (pattern) =>
            pattern.test(text),
        )
      ) {
        found = {
          kind: "list",
          file,
          exportName: name,
        };
        break;
      }
    }

    if (found) {
      break;
    }
  }
}

if (!found) {
  /*
   * Last-resort structural discovery:
   * look for exported assignment-related functions in files that contain
   * both deviceId and gameId.
   */
  for (const file of files) {
    const text =
      fs.readFileSync(
        file,
        "utf8",
      );

    if (
      !text.includes("deviceId") ||
      !text.includes("gameId") ||
      !/assignment/i.test(text)
    ) {
      continue;
    }

    const exported =
      [
        ...text.matchAll(
          /export\s+(?:async\s+)?function\s+([A-Za-z0-9_]+)/g,
        ),
        ...text.matchAll(
          /export\s+const\s+([A-Za-z0-9_]+)/g,
        ),
      ]
        .map(
          (match) =>
            match[1],
        )
        .filter(
          (name) =>
            /assignment/i.test(name),
        );

    const direct =
      exported.find(
        (name) =>
          /device/i.test(name) &&
          !/list|all/i.test(name),
      );

    if (direct) {
      found = {
        kind: "direct",
        file,
        exportName: direct,
      };
      break;
    }

    const list =
      exported.find(
        (name) =>
          /list|all|get.*assignments/i.test(name),
      );

    if (list) {
      found = {
        kind: "list",
        file,
        exportName: list,
      };
      break;
    }
  }
}

if (!found) {
  console.error(
    "ERROR: unable to discover an exported scoreboard device assignment lookup.",
  );
  console.error(
    "Repository was not modified.",
  );
  process.exit(2);
}

const serviceDir =
  path.dirname(
    "apps/api/src/services/scoreboardControlInputs.ts",
  );

let relative =
  path.relative(
    serviceDir,
    found.file,
  )
    .replaceAll("\\", "/")
    .replace(/\.ts$/, ".js");

if (!relative.startsWith(".")) {
  relative =
    "./" +
    relative;
}

console.log(
  JSON.stringify({
    ...found,
    importPath: relative,
  }),
);
NODE

DISCOVERY_JSON="$(cat "$DISCOVERY_FILE")"

if [[ -z "$DISCOVERY_JSON" ]]; then
  echo "ERROR: assignment discovery returned no result." >&2
  echo "Repository was not modified." >&2
  exit 1
fi

echo "Discovered assignment source:"
node -e '
const d = JSON.parse(process.argv[1]);
console.log("  File:   " + d.file);
console.log("  Export: " + d.exportName);
console.log("  Mode:   " + d.kind);
' "$DISCOVERY_JSON"

SERVICE="apps/api/src/services/scoreboardControlInputs.ts"
ROUTE="apps/api/src/routes/scoreboardControlInputs.ts"
FW_H="firmware/esp32-scoreboard/include/ScoreboardControlInputClient.h"
FW_CPP="firmware/esp32-scoreboard/src/ScoreboardControlInputClient.cpp"
MAIN="firmware/esp32-scoreboard/src/main.cpp"
TEST="packages/core/test/physical-control-event-transport-api-ack-14.3.test.ts"

for file in "$SERVICE" "$ROUTE" "$FW_H" "$FW_CPP" "$MAIN" "$TEST" "apps/api/src/app.ts"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
  fi
done

mkdir -p \
  "$(dirname "$SERVICE")" \
  "$(dirname "$ROUTE")" \
  "$(dirname "$FW_H")" \
  "$(dirname "$FW_CPP")" \
  "$(dirname "$TEST")"

DISCOVERY_JSON="$DISCOVERY_JSON" node <<'NODE'
const fs = require("fs");

const discovery =
  JSON.parse(
    process.env.DISCOVERY_JSON,
  );

const service =
  "apps/api/src/services/scoreboardControlInputs.ts";

let assignmentAdapter;

if (discovery.kind === "direct") {
  assignmentAdapter = `
import {
  ${discovery.exportName},
} from "${discovery.importPath}";

function findAuthoritativeAssignment(
  deviceId: string,
) {
  return ${discovery.exportName}(
    deviceId,
  );
}
`;
} else {
  assignmentAdapter = `
import {
  ${discovery.exportName},
} from "${discovery.importPath}";

function findAuthoritativeAssignment(
  deviceId: string,
) {
  const assignments =
    ${discovery.exportName}();

  return (
    assignments.find(
      (assignment: {
        deviceId?: string;
        gameId?: string;
      }) =>
        assignment.deviceId ===
        deviceId,
    ) ?? null
  );
}
`;
}

const content = `import type {
  ScoreboardControlInputAck,
  ScoreboardControlInputEvent,
} from "@sportsos/core";
${assignmentAdapter}
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
): ScoreboardControlInputAck {
  const processedAt =
    new Date().toISOString();

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
        findAuthoritativeAssignment(
          event.deviceId,
        )?.gameId ?? null,
      processedAt,
    };
  }

  const assignment =
    findAuthoritativeAssignment(
      event.deviceId,
    );

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
`;

fs.writeFileSync(
  service,
  content,
);
NODE

cat > "$ROUTE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import {
  SCOREBOARD_CONTROL_INPUT_PROTOCOL_VERSION,
  isScoreboardControlInputType,
  type ScoreboardControlInputEvent,
} from "@sportsos/core";

import {
  isVerifiedDevice,
} from "../services/scoreboardDeviceEnrollment.js";

import {
  processScoreboardControlInput,
} from "../services/scoreboardControlInputs.js";

export async function registerScoreboardControlInputRoutes(
  app: FastifyInstance,
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
        )
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
          ),
      };
    },
  );
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/app.ts";

let text =
  fs.readFileSync(file, "utf8");

const importLine =
  'import { registerScoreboardControlInputRoutes } from "./routes/scoreboardControlInputs.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate API import block.",
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
    "await registerScoreboardControlInputRoutes(app);",
  )
) {
  const anchor =
    "return app;";

  const idx =
    text.lastIndexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate return app; in API app.",
    );
  }

  text =
    text.slice(0, idx) +
    "  await registerScoreboardControlInputRoutes(app);\n\n" +
    text.slice(idx);
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

class ScoreboardControlInputClient {
 public:
  explicit ScoreboardControlInputClient(
      const ScoreboardControlInputClientConfig& config);

  bool submit(
      ScoreboardControlInputType type,
      uint32_t sequence,
      unsigned long occurredAtMs);

 private:
  ScoreboardControlInputClientConfig config_;

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
    : config_(config) {}

bool ScoreboardControlInputClient::submit(
    ScoreboardControlInputType type,
    uint32_t sequence,
    unsigned long occurredAtMs) {
  if (
      config_.apiBaseUrl == nullptr ||
      config_.deviceId == nullptr ||
      config_.deviceId[0] == '\0'
  ) {
    return false;
  }

  HTTPClient http;

  const String url =
      String(config_.apiBaseUrl) +
      "/scoreboard-control-inputs";

  if (!http.begin(url)) {
    return false;
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

  http.end();

  return
      status >= 200 &&
      status < 300;
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
      `${anchor}\n#include "ScoreboardControlInputClient.h"`,
    );
}

for (const line of [
  "using sportsos::ScoreboardControlInputClient;",
  "using sportsos::ScoreboardControlInputClientConfig;",
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
  const globalsAnchor =
    "GpioButtonInput scoreboardButtons(";

  const idx =
    text.indexOf(globalsAnchor);

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
    "Unable to locate end of button callback.",
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

    scoreboardControlInputClient->submit(
        event.type,
        scoreboardControlSequence,
        event.occurredAtMs);
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
      "Unable to locate setup button initialization.",
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

describe("Milestone 14.3 physical control transport / API ack", () => {
  it("adds verified-device control input endpoint", () => {
    const route = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardControlInputs.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain(
      "/scoreboard-control-inputs",
    );

    expect(route).toContain(
      "isVerifiedDevice",
    );
  });

  it("uses the discovered authoritative assignment registry", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardControlInputs.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "findAuthoritativeAssignment",
    );

    expect(service).toContain(
      "assignment.gameId",
    );
  });

  it("deduplicates device input sequences", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardControlInputs.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "IGNORED_DUPLICATE",
    );

    expect(service).toContain(
      "event.sequence <=",
    );
  });

  it("adds ESP32 control input transport", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardControlInputClient.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "/scoreboard-control-inputs",
    );

    expect(source).toContain(
      "CONTROL_INPUT_PROTOCOL_VERSION",
    );
  });

  it("submits debounced physical press events", () => {
    const main = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/main.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(main).toContain(
      "scoreboardControlInputClient->submit",
    );

    expect(main).toContain(
      "scoreboardControlSequence += 1",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 14.3 discovery repair installed"
echo "============================================================"
echo
echo "Added:"
echo "  - runtime discovery of existing assignment registry"
echo "  - compatibility adapter for direct/list assignment exports"
echo "  - POST /scoreboard-control-inputs"
echo "  - verified-device validation"
echo "  - duplicate sequence acknowledgement"
echo "  - assignment validation"
echo "  - ESP32 control-input HTTP transport"
echo "  - focused 14.3 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run build --workspace @sportsos/core"
echo "  npm run typecheck && npm test"
echo
echo "Then firmware compile:"
echo "  bash firmware/esp32-scoreboard/build-in-docker.sh"
echo
echo "Then rebuild API:"
echo "  docker compose up -d --build api"
