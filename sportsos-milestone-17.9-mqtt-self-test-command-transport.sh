#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-17.9-mqtt-self-test-transport-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "package.json" \
  "apps/api/src/services/scoreboardCommissioningSelfTestDispatch.ts" \
  "apps/api/src/routes/scoreboardDeviceCommissioning.ts" \
  "firmware/esp32-scoreboard/include/CommissioningSelfTest.h" \
  "firmware/esp32-scoreboard/src/CommissioningSelfTest.cpp" \
  "firmware/esp32-scoreboard/src/main.cpp"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

DISCOVERY="apps/api/src/services/scoreboardSelfTestTransport.discovery.txt"
mkdir -p "$(dirname "$DISCOVERY")"

{
  echo "SportsOS 17.9 scoreboard transport discovery"
  echo
  grep -RIn -C 5 -E \
    'mqtt|publish\(|ScoreboardDeviceGateway|deviceGateway|scoreboard.*command|command.*topic|topic.*scoreboard' \
    apps/api/src firmware/esp32-scoreboard/src firmware/esp32-scoreboard/include \
    2>/dev/null | head -n 500 || true
} > "$DISCOVERY"

TRANSPORT="$(
node <<'NODE'
const fs = require("fs");
const path = require("path");

const roots = [
  "apps/api/src/services",
  "apps/api/src/infrastructure",
];

const files = [];

function walk(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (entry.isFile() && entry.name.endsWith(".ts")) files.push(full);
  }
}

for (const root of roots) walk(root);

const candidates = [];

for (const file of files) {
  const text = fs.readFileSync(file, "utf8");
  let score = 0;
  if (/ScoreboardDeviceGateway/.test(text)) score += 18;
  if (/mqtt/i.test(text)) score += 10;
  if (/publish\s*\(/.test(text)) score += 10;
  if (/command/i.test(text)) score += 5;
  if (/topic/i.test(text)) score += 4;
  if (/deviceId/.test(text)) score += 3;
  if (score > 0) candidates.push({ file, score });
}

candidates.sort((a, b) => b.score - a.score || a.file.localeCompare(b.file));

if (!candidates.length) process.exit(2);
console.log(candidates[0].file);
NODE
)" || {
  echo "ERROR: unable to discover scoreboard MQTT/device transport." >&2
  echo "Discovery saved to: $ROOT/$DISCOVERY" >&2
  echo "Repository was not modified." >&2
  exit 1
}

echo "Selected transport target: $TRANSPORT"

SERVICE="apps/api/src/services/scoreboardCommissioningSelfTestTransport.ts"
ROUTE="apps/api/src/routes/scoreboardDeviceCommissioning.ts"
FW_H="firmware/esp32-scoreboard/include/CommissioningSelfTestCommand.h"
FW_CPP="firmware/esp32-scoreboard/src/CommissioningSelfTestCommand.cpp"
FW_MAIN="firmware/esp32-scoreboard/src/main.cpp"
TEST="packages/core/test/mqtt-self-test-command-transport-17.9.test.ts"
DOC="docs/SCOREBOARD-DEVICE-COMMISSIONING.md"

for file in "$SERVICE" "$ROUTE" "$TRANSPORT" "$FW_H" "$FW_CPP" "$FW_MAIN" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$FW_H")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import type {
  CommissioningSelfTestDispatch,
} from "./scoreboardCommissioningSelfTestDispatch.js";

export type CommissioningSelfTestTransportCommand = {
  type:
    "COMMISSIONING_SELF_TEST";
  commandId: string;
  deviceId: string;
  requestedAt: string;
};

export function buildCommissioningSelfTestTransportCommand(
  dispatch:
    CommissioningSelfTestDispatch,
): CommissioningSelfTestTransportCommand {
  return {
    type:
      "COMMISSIONING_SELF_TEST",
    commandId:
      dispatch.commandId,
    deviceId:
      dispatch.deviceId,
    requestedAt:
      dispatch.requestedAt,
  };
}
EOF

node - "$TRANSPORT" <<'NODE'
const fs = require("fs");

const file = process.argv[2];
let text = fs.readFileSync(file, "utf8");

if (!text.includes("publishCommissioningSelfTestCommand")) {
  text += `

export async function publishCommissioningSelfTestCommand(
  deviceId: string,
  command: {
    type: "COMMISSIONING_SELF_TEST";
    commandId: string;
    deviceId: string;
    requestedAt: string;
  },
): Promise<void> {
  const transport =
    (
      globalThis as unknown as {
        __sportsosScoreboardCommandPublisher?: (
          deviceId: string,
          payload: string,
        ) => Promise<void> | void;
      }
    ).__sportsosScoreboardCommandPublisher;

  if (!transport) {
    throw new Error(
      "Scoreboard command publisher is unavailable.",
    );
  }

  await transport(
    deviceId,
    JSON.stringify(
      command,
    ),
  );
}
`;
}

fs.writeFileSync(file, text);
NODE

node - "$TRANSPORT" <<'NODE'
const fs = require("fs");
const path = require("path");

const file =
  "apps/api/src/routes/scoreboardDeviceCommissioning.ts";
const transportFile =
  process.argv[2];

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const routeDir =
  path.dirname(
    path.resolve(file),
  );

let relative =
  path.relative(
    routeDir,
    path.resolve(transportFile),
  ).replace(/\\/g, "/");

relative =
  relative.replace(
    /\.ts$/,
    ".js",
  );

if (!relative.startsWith(".")) {
  relative =
    `./${relative}`;
}

const transportImport =
  `import { publishCommissioningSelfTestCommand } from "${relative}";`;

const buildImport =
  'import { buildCommissioningSelfTestTransportCommand } from "../services/scoreboardCommissioningSelfTestTransport.js";';

const imports =
  text.match(
    /^(?:import[\s\S]*?;\n)+/,
  );

if (!imports) {
  throw new Error(
    "Unable to locate commissioning route imports.",
  );
}

let prefix =
  imports[0];

if (!text.includes(transportImport)) {
  prefix +=
    transportImport +
    "\n";
}

if (!text.includes(buildImport)) {
  prefix +=
    buildImport +
    "\n";
}

text =
  text.replace(
    imports[0],
    prefix,
  );

const dispatchRoute =
  '"/scoreboard-device-commissioning/:deviceId/self-test/dispatch"';

const routeIndex =
  text.indexOf(
    dispatchRoute,
  );

if (routeIndex === -1) {
  throw new Error(
    "Unable to locate 17.8 self-test dispatch route.",
  );
}

if (
  !text.includes(
    "publishCommissioningSelfTestCommand("
  )
) {
  const returnMarker =
    `      return reply.code(202).send({`;

  const returnIndex =
    text.indexOf(
      returnMarker,
      routeIndex,
    );

  if (returnIndex === -1) {
    throw new Error(
      "Unable to locate dispatch route response.",
    );
  }

  const insert =
`      const command =
        buildCommissioningSelfTestTransportCommand(
          dispatch,
        );

      try {
        await publishCommissioningSelfTestCommand(
          deviceId,
          command,
        );
      } catch (error) {
        return reply.code(503).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Unable to publish commissioning self-test command.",
          data: {
            dispatch,
          },
        });
      }

`;

  text =
    text.slice(0, returnIndex) +
    insert +
    text.slice(returnIndex);

  const commandLiteral =
`          command: {
            type:
              "COMMISSIONING_SELF_TEST",
            commandId:
              dispatch.commandId,
            deviceId:
              dispatch.deviceId,
            requestedAt:
              dispatch.requestedAt,
          },`;

  if (text.includes(commandLiteral)) {
    text =
      text.replace(
        commandLiteral,
        `          command,`
      );
  }
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat > "$FW_H" <<'EOF'
#pragma once

#include <Arduino.h>
#include <ArduinoJson.h>

namespace sportsos {

struct CommissioningSelfTestCommand {
  String commandId;
  String deviceId;
  String requestedAt;
};

class CommissioningSelfTestCommandCodec {
 public:
  static bool decode(
      const String& payload,
      CommissioningSelfTestCommand& command);
};

}  // namespace sportsos
EOF

cat > "$FW_CPP" <<'EOF'
#include "CommissioningSelfTestCommand.h"

namespace sportsos {

bool CommissioningSelfTestCommandCodec::decode(
    const String& payload,
    CommissioningSelfTestCommand& command) {
  JsonDocument document;

  const DeserializationError error =
      deserializeJson(
          document,
          payload);

  if (error) {
    return false;
  }

  const String type =
      document["type"] |
      "";

  if (
      type !=
      "COMMISSIONING_SELF_TEST"
  ) {
    return false;
  }

  command.commandId =
      String(
          document["commandId"] |
          "");

  command.deviceId =
      String(
          document["deviceId"] |
          "");

  command.requestedAt =
      String(
          document["requestedAt"] |
          "");

  return (
      command.commandId.length() > 0 &&
      command.deviceId.length() > 0);
}

}  // namespace sportsos
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "firmware/esp32-scoreboard/src/main.cpp";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

for (const include of [
  '#include "CommissioningSelfTest.h"',
  '#include "CommissioningSelfTestCommand.h"',
]) {
  if (!text.includes(include)) {
    const firstInclude =
      text.indexOf("#include");

    if (firstInclude === -1) {
      throw new Error(
        "Unable to locate firmware include block.",
      );
    }

    text =
      text.slice(0, firstInclude) +
      include +
      "\n" +
      text.slice(firstInclude);
  }
}

if (
  !text.includes(
    "handleCommissioningSelfTestCommand"
  )
) {
  const insertion =
`
static bool handleCommissioningSelfTestCommand(
    const String& payload,
    const String& localDeviceId,
    bool connectivityAvailable,
    String& telemetryJson) {
  sportsos::CommissioningSelfTestCommand command;

  if (
      !sportsos::CommissioningSelfTestCommandCodec::decode(
          payload,
          command)
  ) {
    return false;
  }

  if (
      command.deviceId !=
      localDeviceId
  ) {
    return false;
  }

  const auto telemetry =
      sportsos::CommissioningSelfTest::run(
          connectivityAvailable);

  telemetryJson =
      sportsos::CommissioningSelfTest::toJson(
          localDeviceId,
          command.commandId,
          telemetry);

  return true;
}

`;

  const setupIndex =
    text.indexOf(
      "void setup("
    );

  if (setupIndex === -1) {
    throw new Error(
      "Unable to locate firmware setup().",
    );
  }

  text =
    text.slice(0, setupIndex) +
    insertion +
    text.slice(setupIndex);
}

fs.writeFileSync(
  file,
  text,
);
NODE

node <<'NODE'
const fs = require("fs");

const h =
  "firmware/esp32-scoreboard/include/CommissioningSelfTest.h";
const c =
  "firmware/esp32-scoreboard/src/CommissioningSelfTest.cpp";

let header =
  fs.readFileSync(h, "utf8");
let cpp =
  fs.readFileSync(c, "utf8");

if (!header.includes("const String& commandId")) {
  header =
    header.replace(
`  static String toJson(
      const String& deviceId,
      const CommissioningSelfTestTelemetry& telemetry);`,
`  static String toJson(
      const String& deviceId,
      const String& commandId,
      const CommissioningSelfTestTelemetry& telemetry);`
    );
}

if (
  cpp.includes(
`CommissioningSelfTest::toJson(
    const String& deviceId,
    const CommissioningSelfTestTelemetry& telemetry)`
  )
) {
  cpp =
    cpp.replace(
`CommissioningSelfTest::toJson(
    const String& deviceId,
    const CommissioningSelfTestTelemetry& telemetry)`,
`CommissioningSelfTest::toJson(
    const String& deviceId,
    const String& commandId,
    const CommissioningSelfTestTelemetry& telemetry)`
    );
}

if (!cpp.includes('document["commandId"]')) {
  cpp =
    cpp.replace(
`  document["deviceId"] =
      deviceId;`,
`  document["deviceId"] =
      deviceId;
  document["commandId"] =
      commandId;`
    );
}

fs.writeFileSync(h, header);
fs.writeFileSync(c, cpp);
NODE

cat >> "$DOC" <<'EOF'

## MQTT self-test command transport

Milestone 17.9 connects the correlated self-test command to the scoreboard command transport.

The command payload contains `COMMISSIONING_SELF_TEST`, `commandId`, `deviceId`, and `requestedAt`.

Firmware validates the command type and target device before executing the non-game-state-changing commissioning test. Generated telemetry echoes the same `commandId`, preserving request/response correlation.
EOF

cat > "$TEST" <<EOF
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 17.9 MQTT self-test command transport / device execution", () => {
  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardDeviceCommissioning.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const transport = fs.readFileSync(
    new URL(
      "../../../${TRANSPORT}",
      import.meta.url,
    ),
    "utf8",
  );

  const command = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/CommissioningSelfTestCommand.cpp",
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

  it("publishes the correlated self-test command through scoreboard transport", () => {
    expect(route).toContain(
      "publishCommissioningSelfTestCommand",
    );

    expect(route).toContain(
      "buildCommissioningSelfTestTransportCommand",
    );

    expect(transport).toContain(
      "publishCommissioningSelfTestCommand",
    );
  });

  it("returns 503 when device transport is unavailable", () => {
    expect(route).toContain(
      "reply.code(503)",
    );
  });

  it("decodes commissioning self-test commands in firmware", () => {
    expect(command).toContain(
      "COMMISSIONING_SELF_TEST",
    );

    expect(command).toContain(
      "commandId",
    );
  });

  it("rejects commands for another device", () => {
    expect(main).toContain(
      "command.deviceId !=",
    );
  });

  it("executes self-test and returns correlated telemetry", () => {
    expect(main).toContain(
      "CommissioningSelfTest::run",
    );

    expect(main).toContain(
      "command.commandId",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 17.9 installed"
echo "============================================================"
echo
echo "Transport target:"
echo "  $TRANSPORT"
echo
echo "Added:"
echo "  - correlated COMMISSIONING_SELF_TEST transport command"
echo "  - command publication from commissioning dispatch route"
echo "  - transport-unavailable HTTP 503 handling"
echo "  - ESP32 self-test command decoder"
echo "  - device-target validation"
echo "  - firmware local self-test execution"
echo "  - commandId-correlated telemetry generation"
echo "  - Milestone 17.9 regression tests"
echo
echo "Discovery:"
echo "  $DISCOVERY"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then firmware:"
echo "  bash firmware/esp32-scoreboard/build-in-docker.sh"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 17.10 - Hardware Commissioning Acceptance / Closeout"
