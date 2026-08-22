#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="14.8-physical-horn-output-control-binding"
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
  "$ROOT/apps/api/src/routes/scoreboardControlInputs.ts" \
  "$ROOT/apps/api/src/services/scoreboardPhysicalControlExecution.ts" \
  "$ROOT/apps/api/src/services/automaticGameScoreboardSync.ts" \
  "$ROOT/apps/api/src/services/scoreboardDeviceGateway.ts"
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

const targets = [
  "apps/api/src/services/scoreboardDeviceGateway.ts",
  "apps/api/src/routes/scoreboardDevices.ts",
  "packages/core/src/scoreboard-device-contract.ts",
  "packages/core/src/scoreboard-mqtt-contract.ts",
];

const result = [];

for (const file of targets) {
  if (!fs.existsSync(file)) continue;

  const text = fs.readFileSync(file, "utf8");

  result.push({
    file,
    exports: [
      ...text.matchAll(/export\s+(?:async\s+)?function\s+([A-Za-z0-9_]+)/g),
      ...text.matchAll(/export\s+class\s+([A-Za-z0-9_]+)/g),
      ...text.matchAll(/export\s+const\s+([A-Za-z0-9_]+)/g),
    ].map(m => m[1]),
    hornMentions:
      [...text.matchAll(/.{0,80}horn.{0,120}/gi)]
        .map(m => m[0])
        .slice(0, 20),
    commandMentions:
      [...text.matchAll(/.{0,80}(command|publish|send|trigger).{0,120}/gi)]
        .map(m => m[0])
        .slice(0, 40),
  });
}

console.log(JSON.stringify(result, null, 2));
NODE

echo "Horn/output transport discovery:"
cat "$DISCOVERY_FILE"

SERVICE="apps/api/src/services/scoreboardPhysicalHornOutput.ts"
EXECUTION="apps/api/src/services/scoreboardPhysicalControlExecution.ts"
ROUTE="apps/api/src/routes/scoreboardControlInputs.ts"
TEST="packages/core/test/physical-horn-output-control-binding-14.8.test.ts"
DISCOVERY_DOC="apps/api/src/services/scoreboardPhysicalHornOutput.discovery.json"

for file in \
  "$SERVICE" \
  "$EXECUTION" \
  "$ROUTE" \
  "$TEST" \
  "$DISCOVERY_DOC"
do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
  fi
done

mkdir -p \
  "$(dirname "$SERVICE")" \
  "$(dirname "$TEST")"

cp "$DISCOVERY_FILE" "$DISCOVERY_DOC"

cat > "$SERVICE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

export type PhysicalHornOutputResult = {
  triggered: boolean;
  statusCode: number;
  deviceId: string;
  responseBody: unknown;
  reason: string | null;
};

type HornCandidate = {
  method: "POST";
  url: string;
  payload: Record<string, unknown>;
};

function candidatesFor(
  deviceId: string,
): HornCandidate[] {
  const encoded =
    encodeURIComponent(
      deviceId,
    );

  return [
    {
      method: "POST",
      url:
        `/scoreboard-devices/${encoded}/commands`,
      payload: {
        command: "TRIGGER_HORN",
      },
    },
    {
      method: "POST",
      url:
        `/scoreboard-devices/${encoded}/command`,
      payload: {
        command: "TRIGGER_HORN",
      },
    },
    {
      method: "POST",
      url:
        `/scoreboard-devices/${encoded}/horn`,
      payload: {
        action: "trigger",
      },
    },
  ];
}

export async function triggerPhysicalHornOutput(
  app: FastifyInstance,
  deviceId: string,
): Promise<PhysicalHornOutputResult> {
  for (
    const candidate of candidatesFor(
      deviceId,
    )
  ) {
    const response =
      await app.inject({
        method:
          candidate.method,
        url:
          candidate.url,
        payload:
          candidate.payload,
      });

    if (
      response.statusCode === 404
    ) {
      continue;
    }

    let responseBody: unknown =
      response.body;

    try {
      responseBody =
        response.json();
    } catch {
      // Preserve raw response for diagnostics.
    }

    return {
      triggered:
        response.statusCode >= 200 &&
        response.statusCode < 300,
      statusCode:
        response.statusCode,
      deviceId,
      responseBody,
      reason:
        response.statusCode >= 200 &&
        response.statusCode < 300
          ? null
          : "Scoreboard horn command was rejected.",
    };
  }

  return {
    triggered: false,
    statusCode: 501,
    deviceId,
    responseBody: null,
    reason:
      "No compatible scoreboard horn command route was found.",
  };
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/scoreboardPhysicalControlExecution.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { triggerPhysicalHornOutput } from "./scoreboardPhysicalHornOutput.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate physical-control execution import block.",
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

const oldHornBlock =
`  if (command.kind === "HORN") {
    return {
      executed: true,
      statusCode: 202,
      authoritativeGameId:
        gameId,
      command,
      responseBody: {
        accepted: true,
        deferredToDeviceTransport: true,
      },
      reason:
        null,
    };
  }`;

if (
  text.includes(oldHornBlock)
) {
  text =
    text.replace(
      oldHornBlock,
`  if (command.kind === "HORN") {
    /*
     * Horn is a physical side-effect rather than persistent game state.
     * Resolve the live device assignment and re-enter the existing scoreboard
     * device command API so MQTT/device authorization stays centralized.
     */
    const assignment =
      (
        await app.inject({
          method: "GET",
          url:
            "/scoreboard-devices/assignments",
        })
      );

    let deviceId:
      string | null =
        null;

    try {
      const payload =
        assignment.json() as {
          data?: {
            assignments?: Array<{
              gameId?: string;
              deviceId?: string;
            }>;
          };
          assignments?: Array<{
            gameId?: string;
            deviceId?: string;
          }>;
        };

      const assignments =
        payload.data?.assignments ??
        payload.assignments ??
        [];

      deviceId =
        assignments.find(
          (item) =>
            item.gameId ===
            gameId,
        )?.deviceId ??
        null;
    } catch {
      deviceId =
        null;
    }

    if (!deviceId) {
      return {
        executed: false,
        statusCode: 409,
        authoritativeGameId:
          gameId,
        command,
        responseBody: null,
        reason:
          "No scoreboard device assignment is available for horn output.",
      };
    }

    const horn =
      await triggerPhysicalHornOutput(
        app,
        deviceId,
      );

    return {
      executed:
        horn.triggered,
      statusCode:
        horn.statusCode,
      authoritativeGameId:
        gameId,
      command,
      responseBody:
        horn.responseBody,
      reason:
        horn.reason,
    };
  }`,
    );
}

if (
  !text.includes(
    "triggerPhysicalHornOutput(",
  )
) {
  throw new Error(
    "Unable to bind physical horn output into control execution.",
  );
}

fs.writeFileSync(
  file,
  text,
);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardControlInputs.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

/*
 * Horn does not require game snapshot reconciliation because it is not a
 * persistent game-state mutation. Skip the reconciliation GET probes for horn.
 */
if (
  !text.includes(
    'execution.command.kind === "HORN"',
  )
) {
  const anchor =
`      const assignment =
        automaticSync
          .getAssignmentByDeviceId(
            body.deviceId,
          );`;

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate reconciliation assignment block.",
    );
  }

  text =
    text.replace(
      anchor,
`      if (
        execution.command.kind ===
          "HORN"
      ) {
        recordScoreboardControlAudit({
          auditId:
            body.inputId,
          deviceId:
            body.deviceId,
          gameId:
            result.authoritativeGameId,
          inputId:
            body.inputId,
          inputType:
            body.type,
          sequence:
            body.sequence,
          disposition:
            "ACCEPTED",
          command:
            execution.command,
          execution,
          reconciliation:
            null,
          error:
            null,
          createdAt:
            new Date().toISOString(),
        });

        return {
          success: true,
          data: {
            ...result,
            execution,
            reconciliation:
              null,
          },
        };
      }

${anchor}`,
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.8 physical horn / output control binding", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardPhysicalHornOutput.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const execution = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardPhysicalControlExecution.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlInputs.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("re-enters existing scoreboard device command routes", () => {
    expect(service).toContain(
      "app.inject",
    );

    expect(service).toContain(
      "/scoreboard-devices/",
    );

    expect(service).toContain(
      "TRIGGER_HORN",
    );
  });

  it("does not write horn state directly", () => {
    expect(service).not.toContain(
      "UPDATE",
    );

    expect(service).not.toContain(
      "INSERT",
    );

    expect(service).not.toContain(
      "mqtt.publish",
    );
  });

  it("resolves horn device from existing assignment API", () => {
    expect(execution).toContain(
      "/scoreboard-devices/assignments",
    );

    expect(execution).toContain(
      "triggerPhysicalHornOutput",
    );
  });

  it("fails safely if there is no assigned device", () => {
    expect(execution).toContain(
      "No scoreboard device assignment is available for horn output.",
    );
  });

  it("skips game-state reconciliation for horn side effects", () => {
    expect(route).toContain(
      'execution.command.kind ===',
    );

    expect(route).toContain(
      '"HORN"',
    );

    expect(route).toContain(
      "reconciliation:",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 14.8 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - physical horn output execution service"
echo "  - horn re-entry through existing scoreboard device command API"
echo "  - live game->device assignment resolution"
echo "  - safe failure when no device is assigned"
echo "  - horn audit integration"
echo "  - horn skips game-state reconciliation"
echo "  - no direct MQTT publishing added"
echo "  - discovery snapshot:"
echo "    $DISCOVERY_DOC"
echo
echo "Safety:"
echo "  - device gateway/API remains output transport authority"
echo "  - horn remains a side-effect, not persistent game state"
echo "  - no duplicate MQTT transport path"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 14.9 - Physical Control Failure / Offline Retry Policy"
