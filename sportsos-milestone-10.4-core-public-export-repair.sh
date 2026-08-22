#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10.4-core-public-export-repair"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/${MILESTONE}-${STAMP}"

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
  "$ROOT/packages/core/package.json" \
  "$ROOT/packages/core/src/index.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: repository safety marker missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

CORE_PKG="packages/core/package.json"
CORE_INDEX="packages/core/src/index.ts"
DEVICE="packages/core/src/scoreboard-device-contract.ts"
MQTT="packages/core/src/scoreboard-mqtt-contract.ts"
TEST="packages/core/test/public-scoreboard-exports-10.4-repair.test.ts"

for file in "$DEVICE" "$MQTT"; do
  [[ -f "$file" ]] || {
    echo "ERROR: required Milestone 10 contract missing: $file" >&2
    exit 1
  }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$CORE_PKG")" \
  "$BACKUP_DIR/$(dirname "$CORE_INDEX")" \
  "$BACKUP_DIR/$(dirname "$TEST")"

cp -a "$CORE_PKG" "$BACKUP_DIR/$CORE_PKG"
cp -a "$CORE_INDEX" "$BACKUP_DIR/$CORE_INDEX"
[[ -f "$TEST" ]] && cp -a "$TEST" "$BACKUP_DIR/$TEST"

node <<'NODE'
const fs = require("fs");

const indexFile = "packages/core/src/index.ts";
let text = fs.readFileSync(indexFile, "utf8");

const required = [
  'export * from "./scoreboard-device-contract.js";',
  'export * from "./scoreboard-mqtt-contract.js";',
];

text = text
  .replaceAll(
    'export * from "./scoreboard-device-contract";',
    required[0],
  )
  .replaceAll(
    'export * from "./scoreboard-mqtt-contract";',
    required[1],
  );

for (const line of required) {
  if (!text.includes(line)) {
    text = `${text.trimEnd()}\n${line}\n`;
  }
}

fs.writeFileSync(indexFile, text);
NODE

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  SCOREBOARD_DEVICE_PROTOCOL_VERSION,
  SCOREBOARD_MQTT_ROOT,
  buildScoreboardMqttCommandEnvelope,
  scoreboardMqttTopics,
  validateScoreboardDeviceCommand,
  type ScoreboardDeviceCommand,
  type ScoreboardDeviceSnapshot,
  type ScoreboardMqttAcknowledgement,
  type ScoreboardMqttPresence,
  type ScoreboardMqttTelemetry,
} from "../src/index.js";

describe("Milestone 10.4 core public scoreboard exports", () => {
  it("exports the physical scoreboard protocol", () => {
    expect(SCOREBOARD_DEVICE_PROTOCOL_VERSION).toBe(1);

    const command: ScoreboardDeviceCommand = {
      protocolVersion: 1,
      commandId: "cmd-public",
      type: "SET_SCORE",
      homeScore: 1,
      awayScore: 0,
    };

    expect(
      validateScoreboardDeviceCommand(command),
    ).toEqual(command);
  });

  it("exports the MQTT transport contract", () => {
    expect(SCOREBOARD_MQTT_ROOT).toBe(
      "sportsos/scoreboards",
    );

    expect(
      scoreboardMqttTopics("scoreboard-1").command,
    ).toBe(
      "sportsos/scoreboards/scoreboard-1/command",
    );

    expect(
      buildScoreboardMqttCommandEnvelope(
        "scoreboard-1",
        {
          protocolVersion: 1,
          commandId: "cmd-mqtt-public",
          type: "HORN",
          active: true,
        },
      ).deviceId,
    ).toBe("scoreboard-1");
  });

  it("exports all gateway-facing scoreboard types", () => {
    const snapshot: ScoreboardDeviceSnapshot = {
      protocolVersion: 1,
      deviceId: "scoreboard-1",
      gameId: null,
      connectionState: "ONLINE",
      homeScore: 0,
      awayScore: 0,
      period: null,
      clock: {
        remainingMs: 0,
        running: false,
      },
      hornActive: false,
      updatedAt: new Date(0).toISOString(),
    };

    const ack: ScoreboardMqttAcknowledgement = {
      deviceId: "scoreboard-1",
      commandId: "cmd-1",
      status: "APPLIED",
      message: null,
      acknowledgedAt: new Date(0).toISOString(),
    };

    const presence: ScoreboardMqttPresence = {
      deviceId: "scoreboard-1",
      online: true,
      reportedAt: new Date(0).toISOString(),
    };

    const telemetry: ScoreboardMqttTelemetry = {
      deviceId: "scoreboard-1",
      firmwareVersion: null,
      ipAddress: null,
      wifiRssi: null,
      uptimeSeconds: 0,
      freeHeapBytes: null,
      reportedAt: new Date(0).toISOString(),
    };

    expect(snapshot.deviceId).toBe("scoreboard-1");
    expect(ack.status).toBe("APPLIED");
    expect(presence.online).toBe(true);
    expect(telemetry.uptimeSeconds).toBe(0);
  });
});
EOF

echo
echo "============================================================"
echo " Inspecting @sportsos/core package resolution"
echo "============================================================"

node <<'NODE'
const fs = require("fs");
const pkg = JSON.parse(
  fs.readFileSync("packages/core/package.json", "utf8"),
);

console.log("name:", pkg.name ?? "(none)");
console.log("type:", pkg.type ?? "(none)");
console.log("main:", pkg.main ?? "(none)");
console.log("types:", pkg.types ?? "(none)");
console.log(
  "exports:",
  JSON.stringify(pkg.exports ?? null),
);
console.log(
  "build script:",
  pkg.scripts?.build ?? "(none)",
);
NODE

echo
echo "============================================================"
echo " Refreshing public @sportsos/core output"
echo "============================================================"

BUILD_SCRIPT="$(
  node -e '
    const p=require("./packages/core/package.json");
    process.stdout.write(p.scripts?.build ? "yes" : "no");
  '
)"

if [[ "$BUILD_SCRIPT" == "yes" ]]; then
  echo "Running core workspace build..."
  npm run build --workspace @sportsos/core
else
  echo "No core build script exists; source entrypoint is expected to be consumed directly."
fi

echo
echo "Verifying TypeScript can see the new public exports..."

TMP_CHECK="packages/core/.scoreboard-public-export-check.ts"
trap 'rm -f "$TMP_CHECK"' EXIT

cat > "$TMP_CHECK" <<'EOF'
import {
  SCOREBOARD_DEVICE_PROTOCOL_VERSION,
  SCOREBOARD_MQTT_ROOT,
  buildScoreboardMqttCommandEnvelope,
  scoreboardMqttTopics,
  validateScoreboardDeviceCommand,
  type ScoreboardDeviceCommand,
  type ScoreboardDeviceSnapshot,
  type ScoreboardMqttAcknowledgement,
  type ScoreboardMqttPresence,
  type ScoreboardMqttTelemetry,
} from "./src/index.js";

void SCOREBOARD_DEVICE_PROTOCOL_VERSION;
void SCOREBOARD_MQTT_ROOT;
void buildScoreboardMqttCommandEnvelope;
void scoreboardMqttTopics;
void validateScoreboardDeviceCommand;

const command: ScoreboardDeviceCommand | null = null;
const snapshot: ScoreboardDeviceSnapshot | null = null;
const ack: ScoreboardMqttAcknowledgement | null = null;
const presence: ScoreboardMqttPresence | null = null;
const telemetry: ScoreboardMqttTelemetry | null = null;

void command;
void snapshot;
void ack;
void presence;
void telemetry;
EOF

npm run typecheck --workspace @sportsos/core

echo
echo "============================================================"
echo " SportsOS-Next Milestone 10.4 public export repair complete"
echo "============================================================"
echo
echo "Fixed:"
echo "  - physical scoreboard contract is exported from core"
echo "  - MQTT transport contract is exported from core"
echo "  - NodeNext .js export extensions enforced"
echo "  - core build output refreshed when a build script exists"
echo "  - regression coverage added for API-facing public symbols"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Now run:"
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo "  docker compose up -d --build api"
