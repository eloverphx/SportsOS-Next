#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10.4-api-scoreboard-device-gateway-repair"
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
  exit 1
fi

for required in "$ROOT/.git" "$ROOT/package.json" "$ROOT/apps" "$ROOT/apps/api"; do
  [[ -e "$required" ]] || {
    echo "ERROR: repository safety marker missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

API_DIR="apps/api"
PKG="$API_DIR/package.json"
GATEWAY="$API_DIR/src/services/scoreboardDeviceGateway.ts"
ROUTE="$API_DIR/src/routes/scoreboardDevices.ts"
TEST="$API_DIR/test/scoreboard-device-gateway-10.4.test.ts"

[[ -f "$PKG" ]] || {
  echo "ERROR: required API package missing: $PKG" >&2
  exit 1
}

mapfile -t CANDIDATES < <(
  grep -RIl \
    --include='*.ts' \
    --exclude='scoreboardDevices.ts' \
    -E '([A-Za-z_$][A-Za-z0-9_$]*)\.register\s*\(' \
    "$API_DIR/src" 2>/dev/null || true
)

if [[ "${#CANDIDATES[@]}" -eq 0 ]]; then
  echo "ERROR: could not discover a Fastify registration file under $API_DIR/src." >&2
  echo "No repository files were modified." >&2
  exit 1
fi

REG_FILE=""
for preferred in \
  "$API_DIR/src/app.ts" \
  "$API_DIR/src/server.ts" \
  "$API_DIR/src/index.ts" \
  "$API_DIR/src/routes/index.ts"
do
  if [[ -f "$preferred" ]] && grep -Eq '\.register\s*\(' "$preferred"; then
    REG_FILE="$preferred"
    break
  fi
done

if [[ -z "$REG_FILE" ]]; then
  REG_FILE="${CANDIDATES[0]}"
fi

echo "Discovered API registration file:"
echo "  $REG_FILE"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$PKG")" \
  "$BACKUP_DIR/$(dirname "$GATEWAY")" \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$REG_FILE")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$GATEWAY")" \
  "$(dirname "$ROUTE")" \
  "$(dirname "$TEST")"

for file in "$PKG" "$GATEWAY" "$ROUTE" "$REG_FILE" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

node <<'NODE'
const fs = require("fs");
const file = "apps/api/package.json";
const pkg = JSON.parse(fs.readFileSync(file, "utf8"));
pkg.dependencies ??= {};
pkg.dependencies.mqtt ??= "^5.10.4";
fs.writeFileSync(file, JSON.stringify(pkg, null, 2) + "\n");
NODE

cat > "$GATEWAY" <<'EOF'
import mqtt, {
  type IClientOptions,
  type MqttClient,
} from "mqtt";
import {
  buildScoreboardMqttCommandEnvelope,
  scoreboardMqttTopics,
  type ScoreboardDeviceCommand,
  type ScoreboardDeviceSnapshot,
  type ScoreboardMqttAcknowledgement,
  type ScoreboardMqttPresence,
  type ScoreboardMqttTelemetry,
} from "@sportsos/core";

export type ScoreboardDeviceRuntime = {
  deviceId: string;
  state: ScoreboardDeviceSnapshot | null;
  presence: ScoreboardMqttPresence | null;
  telemetry: ScoreboardMqttTelemetry | null;
  lastAcknowledgement: ScoreboardMqttAcknowledgement | null;
};

export class ScoreboardDeviceGateway {
  private readonly client: MqttClient;
  private readonly devices =
    new Map<string, ScoreboardDeviceRuntime>();

  public constructor(options: {
    mqttUrl?: string;
    mqttOptions?: IClientOptions;
  } = {}) {
    const mqttUrl =
      options.mqttUrl ??
      process.env.MQTT_URL ??
      "mqtt://sportsos_mqtt:1883";

    this.client = mqtt.connect(mqttUrl, options.mqttOptions);

    this.client.on("connect", () => {
      this.client.subscribe([
        "sportsos/scoreboards/+/state",
        "sportsos/scoreboards/+/presence",
        "sportsos/scoreboards/+/telemetry",
        "sportsos/scoreboards/+/ack",
      ]);
    });

    this.client.on("message", (topic, payloadBuffer) => {
      this.handleMessage(topic, payloadBuffer.toString("utf8"));
    });
  }

  public listDevices(): ScoreboardDeviceRuntime[] {
    return Array.from(
      this.devices.values(),
      (device) => structuredClone(device),
    );
  }

  public getDevice(deviceId: string): ScoreboardDeviceRuntime | null {
    const device = this.devices.get(deviceId);
    return device ? structuredClone(device) : null;
  }

  public async sendCommand(
    deviceId: string,
    command: ScoreboardDeviceCommand,
  ): Promise<void> {
    const mqttTopics = scoreboardMqttTopics(deviceId);
    const envelope =
      buildScoreboardMqttCommandEnvelope(deviceId, command);

    await new Promise<void>((resolve, reject) => {
      this.client.publish(
        mqttTopics.command,
        JSON.stringify(envelope),
        { qos: 1, retain: false },
        (error) => {
          if (error) {
            reject(error);
            return;
          }
          resolve();
        },
      );
    });
  }

  private ensureDevice(deviceId: string): ScoreboardDeviceRuntime {
    const current = this.devices.get(deviceId);
    if (current) {
      return current;
    }

    const created: ScoreboardDeviceRuntime = {
      deviceId,
      state: null,
      presence: null,
      telemetry: null,
      lastAcknowledgement: null,
    };

    this.devices.set(deviceId, created);
    return created;
  }

  private handleMessage(topic: string, payloadText: string): void {
    const match = topic.match(
      /^sportsos\/scoreboards\/([^/]+)\/(state|presence|telemetry|ack)$/,
    );

    if (!match) {
      return;
    }

    const deviceId = match[1];
    const kind = match[2];

    if (!deviceId || !kind) {
      return;
    }

    let payload: unknown;

    try {
      payload = JSON.parse(payloadText);
    } catch {
      return;
    }

    const device = this.ensureDevice(deviceId);

    switch (kind) {
      case "state":
        device.state = payload as ScoreboardDeviceSnapshot;
        break;
      case "presence":
        device.presence = payload as ScoreboardMqttPresence;
        break;
      case "telemetry":
        device.telemetry = payload as ScoreboardMqttTelemetry;
        break;
      case "ack":
        device.lastAcknowledgement =
          payload as ScoreboardMqttAcknowledgement;
        break;
    }
  }
}
EOF

cat > "$ROUTE" <<'EOF'
import type { FastifyInstance } from "fastify";
import {
  validateScoreboardDeviceCommand,
  type ScoreboardDeviceCommand,
} from "@sportsos/core";
import {
  ScoreboardDeviceGateway,
} from "../services/scoreboardDeviceGateway.js";

const gateway = new ScoreboardDeviceGateway();

export async function scoreboardDevicesRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.get("/scoreboard-devices", async () => ({
    success: true,
    data: { devices: gateway.listDevices() },
  }));

  app.get<{
    Params: { deviceId: string };
  }>(
    "/scoreboard-devices/:deviceId",
    async (request, reply) => {
      const device = gateway.getDevice(request.params.deviceId);

      if (!device) {
        return reply.code(404).send({
          success: false,
          error: {
            code: "SCOREBOARD_DEVICE_NOT_FOUND",
            message: "Scoreboard device not found.",
          },
        });
      }

      return {
        success: true,
        data: { device },
      };
    },
  );

  app.post<{
    Params: { deviceId: string };
    Body: ScoreboardDeviceCommand;
  }>(
    "/scoreboard-devices/:deviceId/commands",
    async (request, reply) => {
      let command: ScoreboardDeviceCommand;

      try {
        command = validateScoreboardDeviceCommand(request.body);
      } catch (error) {
        return reply.code(400).send({
          success: false,
          error: {
            code: "INVALID_SCOREBOARD_COMMAND",
            message:
              error instanceof Error
                ? error.message
                : "Invalid scoreboard command.",
          },
        });
      }

      await gateway.sendCommand(request.params.deviceId, command);

      return reply.code(202).send({
        success: true,
        data: {
          accepted: true,
          deviceId: request.params.deviceId,
          commandId: command.commandId,
        },
      });
    },
  );
}
EOF

REG_FILE="$REG_FILE" node <<'NODE'
const fs = require("fs");
const path = require("path");

const file = process.env.REG_FILE;
let text = fs.readFileSync(file, "utf8");

if (!text.includes("scoreboardDevicesRoutes")) {
  const routeAbs =
    path.resolve("apps/api/src/routes/scoreboardDevices.ts");
  const regDir = path.dirname(path.resolve(file));

  let relative = path
    .relative(regDir, routeAbs)
    .replaceAll("\\", "/")
    .replace(/\.ts$/, ".js");

  if (!relative.startsWith(".")) {
    relative = `./${relative}`;
  }

  const importLine =
    `import { scoreboardDevicesRoutes } from "${relative}";`;

  const importMatches = [...text.matchAll(/^import[\s\S]*?;\s*$/gm)];

  if (importMatches.length > 0) {
    const last = importMatches[importMatches.length - 1];
    const pos = last.index + last[0].length;
    text =
      text.slice(0, pos) +
      "\n" +
      importLine +
      "\n" +
      text.slice(pos);
  } else {
    text = importLine + "\n" + text;
  }

  const registerMatch =
    text.match(/([A-Za-z_$][A-Za-z0-9_$]*)\.register\s*\(/);

  if (!registerMatch) {
    throw new Error(
      "Could not identify Fastify instance from registration calls.",
    );
  }

  const instance = registerMatch[1];
  const registerIndex = text.indexOf(registerMatch[0]);
  const lineStart = text.lastIndexOf("\n", registerIndex) + 1;
  const existingIndent =
    text.slice(lineStart, registerIndex).match(/^\s*/)?.[0] ?? "";

  const registration =
    `${existingIndent}await ${instance}.register(scoreboardDevicesRoutes);\n`;

  text =
    text.slice(0, lineStart) +
    registration +
    text.slice(lineStart);
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<EOF
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 10.4 API scoreboard device gateway", () => {
  it("defines the MQTT-backed scoreboard gateway", () => {
    const source = fs.readFileSync(
      new URL(
        "../src/services/scoreboardDeviceGateway.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain("class ScoreboardDeviceGateway");
    expect(source).toContain("sportsos/scoreboards/+/state");
    expect(source).toContain("sportsos/scoreboards/+/presence");
    expect(source).toContain("sportsos/scoreboards/+/telemetry");
    expect(source).toContain("sportsos/scoreboards/+/ack");
  });

  it("exposes device HTTP routes", () => {
    const route = fs.readFileSync(
      new URL(
        "../src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain('"/scoreboard-devices"');
    expect(route).toContain('"/scoreboard-devices/:deviceId"');
    expect(route).toContain(
      '"/scoreboard-devices/:deviceId/commands"',
    );
  });

  it("registers the device routes in the discovered API file", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../${REG_FILE#apps/api/}",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain("scoreboardDevicesRoutes");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 10.4 repair installed"
echo "============================================================"
echo
echo "Discovered registration file:"
echo "  $REG_FILE"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm install"
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo "  docker compose up -d --build api"
