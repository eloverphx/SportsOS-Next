#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10.3-scoreboard-simulator-mqtt-adapter"
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

for required in "$ROOT/.git" "$ROOT/package.json" "$ROOT/apps"; do
  [[ -e "$required" ]] || {
    echo "ERROR: repository safety marker missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

SIM_DIR="apps/scoreboard-simulator"
SRC="$SIM_DIR/src/index.js"
PKG="$SIM_DIR/package.json"
ADAPTER="$SIM_DIR/src/mqtt-adapter.js"
TEST="$SIM_DIR/test/mqtt-adapter-10.3.test.js"

for file in "$SRC" "$PKG"; do
  [[ -f "$file" ]] || {
    echo "ERROR: required simulator file missing: $file" >&2
    exit 1
  }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$SRC")" \
  "$BACKUP_DIR/$(dirname "$PKG")" \
  "$BACKUP_DIR/$(dirname "$ADAPTER")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$TEST")"

for file in "$SRC" "$PKG" "$ADAPTER" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

node <<'NODE'
const fs = require("fs");

const pkgFile = "apps/scoreboard-simulator/package.json";
const pkg = JSON.parse(fs.readFileSync(pkgFile, "utf8"));

pkg.dependencies ??= {};

if (!pkg.dependencies.mqtt) {
  pkg.dependencies.mqtt = "^5.10.4";
}

pkg.scripts ??= {};
pkg.scripts.test ??= "node --test test/*.test.js";

fs.writeFileSync(
  pkgFile,
  JSON.stringify(pkg, null, 2) + "\n",
);
NODE

cat > "$ADAPTER" <<'EOF'
import mqtt from "mqtt";

const MQTT_ROOT = "sportsos/scoreboards";
const PROTOCOL_VERSION = 1;

function topics(deviceId) {
  const base = `${MQTT_ROOT}/${deviceId}`;

  return {
    command: `${base}/command`,
    acknowledgement: `${base}/ack`,
    state: `${base}/state`,
    telemetry: `${base}/telemetry`,
    presence: `${base}/presence`,
  };
}

export function createInitialSimulatorState(deviceId) {
  return {
    protocolVersion: PROTOCOL_VERSION,
    deviceId,
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
    updatedAt: new Date().toISOString(),
  };
}

export function applySimulatorCommand(state, envelope) {
  if (!envelope || typeof envelope !== "object") {
    throw new Error("Invalid command envelope.");
  }

  if (envelope.deviceId !== state.deviceId) {
    throw new Error("Command deviceId does not match simulator.");
  }

  const command = envelope.command;

  if (
    !command ||
    command.protocolVersion !== PROTOCOL_VERSION
  ) {
    throw new Error("Unsupported command protocol version.");
  }

  if (!command.commandId) {
    throw new Error("commandId is required.");
  }

  const next = structuredClone(state);

  switch (command.type) {
    case "SET_GAME":
      next.gameId = command.gameId ?? null;
      break;

    case "SET_SCORE":
      if (
        !Number.isInteger(command.homeScore) ||
        command.homeScore < 0 ||
        !Number.isInteger(command.awayScore) ||
        command.awayScore < 0
      ) {
        throw new Error("Invalid score command.");
      }

      next.homeScore = command.homeScore;
      next.awayScore = command.awayScore;
      break;

    case "SET_CLOCK":
      if (
        !Number.isFinite(command.remainingMs) ||
        command.remainingMs < 0
      ) {
        throw new Error("Invalid clock command.");
      }

      next.clock = {
        remainingMs: command.remainingMs,
        running: Boolean(command.running),
      };
      break;

    case "SET_PERIOD":
      if (
        command.period !== null &&
        (
          !Number.isInteger(command.period) ||
          command.period < 1
        )
      ) {
        throw new Error("Invalid period command.");
      }

      next.period = command.period;
      break;

    case "HORN":
      next.hornActive = Boolean(command.active);
      break;

    case "SYNC_STATE":
      next.gameId = command.snapshot.gameId ?? null;
      next.homeScore = command.snapshot.homeScore;
      next.awayScore = command.snapshot.awayScore;
      next.period = command.snapshot.period;
      next.clock = {
        remainingMs: command.snapshot.clock.remainingMs,
        running: Boolean(
          command.snapshot.clock.running,
        ),
      };
      next.hornActive = Boolean(
        command.snapshot.hornActive,
      );
      break;

    default:
      throw new Error(
        `Unsupported simulator command: ${command.type}`,
      );
  }

  next.updatedAt = new Date().toISOString();

  return next;
}

function publishJson(
  client,
  topic,
  payload,
  options,
) {
  client.publish(
    topic,
    JSON.stringify(payload),
    options,
  );
}

export function startScoreboardMqttAdapter(options = {}) {
  const deviceId =
    options.deviceId ??
    process.env.SCOREBOARD_DEVICE_ID ??
    "scoreboard-simulator-1";

  const mqttUrl =
    options.mqttUrl ??
    process.env.MQTT_URL ??
    "mqtt://sportsos_mqtt:1883";

  const mqttTopics = topics(deviceId);

  let state = createInitialSimulatorState(deviceId);

  const client = mqtt.connect(mqttUrl, {
    clientId: `${deviceId}-${Math.random()
      .toString(16)
      .slice(2, 10)}`,
    reconnectPeriod: 2000,
    will: {
      topic: mqttTopics.presence,
      payload: JSON.stringify({
        deviceId,
        online: false,
        reportedAt: new Date().toISOString(),
      }),
      qos: 1,
      retain: true,
    },
  });

  const publishState = () => {
    publishJson(
      client,
      mqttTopics.state,
      state,
      {
        qos: 1,
        retain: true,
      },
    );
  };

  const publishPresence = (online) => {
    publishJson(
      client,
      mqttTopics.presence,
      {
        deviceId,
        online,
        reportedAt: new Date().toISOString(),
      },
      {
        qos: 1,
        retain: true,
      },
    );
  };

  const publishTelemetry = () => {
    publishJson(
      client,
      mqttTopics.telemetry,
      {
        deviceId,
        firmwareVersion: "simulator-10.3",
        ipAddress: null,
        wifiRssi: null,
        uptimeSeconds: Math.floor(
          process.uptime(),
        ),
        freeHeapBytes:
          process.memoryUsage().heapUsed,
        reportedAt: new Date().toISOString(),
      },
      {
        qos: 0,
        retain: false,
      },
    );
  };

  client.on("connect", () => {
    state.connectionState = "ONLINE";
    state.updatedAt = new Date().toISOString();

    client.subscribe(
      mqttTopics.command,
      {
        qos: 1,
      },
    );

    publishPresence(true);
    publishState();
    publishTelemetry();
  });

  client.on("reconnect", () => {
    state.connectionState = "CONNECTING";
    state.updatedAt = new Date().toISOString();
  });

  client.on("offline", () => {
    state.connectionState = "OFFLINE";
    state.updatedAt = new Date().toISOString();
  });

  client.on(
    "message",
    (topic, payloadBuffer) => {
      if (topic !== mqttTopics.command) {
        return;
      }

      let envelope;

      try {
        envelope = JSON.parse(
          payloadBuffer.toString("utf8"),
        );

        publishJson(
          client,
          mqttTopics.acknowledgement,
          {
            deviceId,
            commandId:
              envelope?.command?.commandId ??
              "unknown",
            status: "ACCEPTED",
            message: null,
            acknowledgedAt:
              new Date().toISOString(),
          },
          {
            qos: 1,
            retain: false,
          },
        );

        state = applySimulatorCommand(
          state,
          envelope,
        );

        publishState();

        publishJson(
          client,
          mqttTopics.acknowledgement,
          {
            deviceId,
            commandId:
              envelope.command.commandId,
            status: "APPLIED",
            message: null,
            acknowledgedAt:
              new Date().toISOString(),
          },
          {
            qos: 1,
            retain: false,
          },
        );
      } catch (error) {
        publishJson(
          client,
          mqttTopics.acknowledgement,
          {
            deviceId,
            commandId:
              envelope?.command?.commandId ??
              "unknown",
            status: "REJECTED",
            message:
              error instanceof Error
                ? error.message
                : "Unknown simulator command error.",
            acknowledgedAt:
              new Date().toISOString(),
          },
          {
            qos: 1,
            retain: false,
          },
        );
      }
    },
  );

  const telemetryTimer = setInterval(
    publishTelemetry,
    30000,
  );

  return {
    client,
    deviceId,
    topics: mqttTopics,
    getState: () => structuredClone(state),
    stop: async () => {
      clearInterval(telemetryTimer);
      publishPresence(false);

      await new Promise((resolve) => {
        client.end(
          false,
          {},
          resolve,
        );
      });
    },
  };
}
EOF

node <<'NODE'
const fs = require("fs");

const file = "apps/scoreboard-simulator/src/index.js";
let text = fs.readFileSync(file, "utf8");

if (!text.includes('from "./mqtt-adapter.js"')) {
  text =
`import {
  startScoreboardMqttAdapter,
} from "./mqtt-adapter.js";
` + text;
}

if (!text.includes("startScoreboardMqttAdapter();")) {
  text += `

const mqttAdapter = startScoreboardMqttAdapter();

process.on("SIGTERM", async () => {
  await mqttAdapter.stop();
  process.exit(0);
});

process.on("SIGINT", async () => {
  await mqttAdapter.stop();
  process.exit(0);
});
`;
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import {
  applySimulatorCommand,
  createInitialSimulatorState,
} from "../src/mqtt-adapter.js";

test("10.3 applies SET_SCORE commands", () => {
  const state =
    createInitialSimulatorState(
      "scoreboard-simulator-1",
    );

  const next = applySimulatorCommand(
    state,
    {
      deviceId: "scoreboard-simulator-1",
      sentAt: new Date().toISOString(),
      command: {
        protocolVersion: 1,
        commandId: "cmd-score",
        type: "SET_SCORE",
        homeScore: 3,
        awayScore: 2,
      },
    },
  );

  assert.equal(next.homeScore, 3);
  assert.equal(next.awayScore, 2);
});

test("10.3 applies clock and period commands", () => {
  let state =
    createInitialSimulatorState(
      "scoreboard-simulator-1",
    );

  state = applySimulatorCommand(
    state,
    {
      deviceId: "scoreboard-simulator-1",
      sentAt: new Date().toISOString(),
      command: {
        protocolVersion: 1,
        commandId: "cmd-clock",
        type: "SET_CLOCK",
        remainingMs: 90000,
        running: true,
      },
    },
  );

  state = applySimulatorCommand(
    state,
    {
      deviceId: "scoreboard-simulator-1",
      sentAt: new Date().toISOString(),
      command: {
        protocolVersion: 1,
        commandId: "cmd-period",
        type: "SET_PERIOD",
        period: 2,
      },
    },
  );

  assert.deepEqual(
    state.clock,
    {
      remainingMs: 90000,
      running: true,
    },
  );
  assert.equal(state.period, 2);
});

test("10.3 rejects commands for another device", () => {
  const state =
    createInitialSimulatorState(
      "scoreboard-simulator-1",
    );

  assert.throws(
    () =>
      applySimulatorCommand(
        state,
        {
          deviceId: "another-device",
          sentAt: new Date().toISOString(),
          command: {
            protocolVersion: 1,
            commandId: "cmd-1",
            type: "HORN",
            active: true,
          },
        },
      ),
    /deviceId does not match/,
  );
});

test("10.3 applies full SYNC_STATE", () => {
  const state =
    createInitialSimulatorState(
      "scoreboard-simulator-1",
    );

  const next = applySimulatorCommand(
    state,
    {
      deviceId: "scoreboard-simulator-1",
      sentAt: new Date().toISOString(),
      command: {
        protocolVersion: 1,
        commandId: "cmd-sync",
        type: "SYNC_STATE",
        snapshot: {
          protocolVersion: 1,
          deviceId: "scoreboard-simulator-1",
          gameId: "game-42",
          homeScore: 5,
          awayScore: 4,
          period: 3,
          clock: {
            remainingMs: 45000,
            running: false,
          },
          hornActive: false,
        },
      },
    },
  );

  assert.equal(next.gameId, "game-42");
  assert.equal(next.homeScore, 5);
  assert.equal(next.awayScore, 4);
  assert.equal(next.period, 3);
  assert.equal(
    next.clock.remainingMs,
    45000,
  );
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 10.3 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - .git / package.json / apps verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - simulator MQTT client"
echo "  - command topic subscription"
echo "  - ACCEPTED / APPLIED / REJECTED acknowledgements"
echo "  - retained simulated device state"
echo "  - retained presence + MQTT last-will"
echo "  - 30-second telemetry publication"
echo "  - SET_GAME / SET_SCORE / SET_CLOCK / SET_PERIOD / HORN / SYNC_STATE application"
echo "  - graceful MQTT shutdown"
echo "  - Milestone 10.3 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Install dependency / validate:"
echo "  npm install"
echo "  npm run typecheck && npm test"
echo
echo "Then rebuild simulator:"
echo "  docker compose up -d --build scoreboard-simulator"
echo
echo "Next after green:"
echo "  Milestone 10.4 - API Scoreboard Device Gateway"
