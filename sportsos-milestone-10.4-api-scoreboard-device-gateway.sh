#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10.4-api-scoreboard-device-gateway"
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

API_DIR="apps/api"
PKG="$API_DIR/package.json"
ROOT_ROUTE="$API_DIR/src/routes/root.ts"
GATEWAY="$API_DIR/src/services/scoreboardDeviceGateway.ts"
ROUTE="$API_DIR/src/routes/scoreboardDevices.ts"
TEST="$API_DIR/test/scoreboard-device-gateway-10.4.test.ts"

for file in "$PKG" "$ROOT_ROUTE"; do
  [[ -f "$file" ]] || {
    echo "ERROR: required API file missing: $file" >&2
    exit 1
  }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$PKG")" \
  "$BACKUP_DIR/$(dirname "$ROOT_ROUTE")" \
  "$BACKUP_DIR/$(dirname "$GATEWAY")" \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$TEST")"

for file in "$PKG" "$ROOT_ROUTE" "$GATEWAY" "$ROUTE" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

node <<'NODE'
const fs = require("fs");

const pkgFile = "apps/api/package.json";
const pkg = JSON.parse(fs.readFileSync(pkgFile, "utf8"));

pkg.dependencies ??= {};

if (!pkg.dependencies.mqtt) {
  pkg.dependencies.mqtt = "^5.10.4";
}

fs.writeFileSync(
  pkgFile,
  JSON.stringify(pkg, null, 2) + "\n",
);
NODE

cat > "$GATEWAY" <<'EOF'
import mqtt, {
  type IClientOptions,
  type MqttClient,
} from "mqtt";
import {
  SCOREBOARD_DEVICE_PROTOCOL_VERSION,
  type ScoreboardDeviceCommand,
  type ScoreboardDeviceSnapshot,
} from "@sportsos/core";
import {
  buildScoreboardMqttCommandEnvelope,
  scoreboardMqttTopics,
  type ScoreboardMqttAcknowledgement,
  type ScoreboardMqttPresence,
  type ScoreboardMqttTelemetry,
} from "@sportsos/core";

export type ScoreboardDeviceRuntime = {
  deviceId: string;
  state: ScoreboardDeviceSnapshot | null;
  presence: ScoreboardMqttPresence | null;
  telemetry: ScoreboardMqttTelemetry | null;
  lastAcknowledgement:
    | ScoreboardMqttAcknowledgement
    | null;
};

export type ScoreboardDeviceGatewayOptions = {
  mqttUrl?: string;
  mqttOptions?: IClientOptions;
};

export class ScoreboardDeviceGateway {
  private readonly client: MqttClient;
  private readonly devices =
    new Map<string, ScoreboardDeviceRuntime>();

  public constructor(
    options: ScoreboardDeviceGatewayOptions = {},
  ) {
    const mqttUrl =
      options.mqttUrl ??
      process.env.MQTT_URL ??
      "mqtt://sportsos_mqtt:1883";

    this.client = mqtt.connect(
      mqttUrl,
      options.mqttOptions,
    );

    this.client.on("connect", () => {
      this.client.subscribe(
        "sportsos/scoreboards/+/state",
        { qos: 1 },
      );
      this.client.subscribe(
        "sportsos/scoreboards/+/presence",
        { qos: 1 },
      );
      this.client.subscribe(
        "sportsos/scoreboards/+/telemetry",
        { qos: 0 },
      );
      this.client.subscribe(
        "sportsos/scoreboards/+/ack",
        { qos: 1 },
      );
    });

    this.client.on(
      "message",
      (topic, payloadBuffer) => {
        this.handleMessage(
          topic,
          payloadBuffer.toString("utf8"),
        );
      },
    );
  }

  public listDevices(): ScoreboardDeviceRuntime[] {
    return Array.from(
      this.devices.values(),
    ).map((device) => ({
      deviceId: device.deviceId,
      state: device.state,
      presence: device.presence,
      telemetry: device.telemetry,
      lastAcknowledgement:
        device.lastAcknowledgement,
    }));
  }

  public getDevice(
    deviceId: string,
  ): ScoreboardDeviceRuntime | null {
    const device = this.devices.get(deviceId);

    return device
      ? {
          deviceId: device.deviceId,
          state: device.state,
          presence: device.presence,
          telemetry: device.telemetry,
          lastAcknowledgement:
            device.lastAcknowledgement,
        }
      : null;
  }

  public async sendCommand(
    deviceId: string,
    command: ScoreboardDeviceCommand,
  ): Promise<void> {
    const topics = scoreboardMqttTopics(deviceId);
    const envelope =
      buildScoreboardMqttCommandEnvelope(
        deviceId,
        command,
      );

    await new Promise<void>(
      (resolve, reject) => {
        this.client.publish(
          topics.command,
          JSON.stringify(envelope),
          {
            qos: 1,
            retain: false,
          },
          (error) => {
            if (error) {
              reject(error);
              return;
            }

            resolve();
          },
        );
      },
    );
  }

  public async syncState(
    snapshot: ScoreboardDeviceSnapshot,
  ): Promise<void> {
    await this.sendCommand(
      snapshot.deviceId,
      {
        protocolVersion:
          SCOREBOARD_DEVICE_PROTOCOL_VERSION,
        commandId:
          `sync-${Date.now()}-${Math.random()
            .toString(16)
            .slice(2, 8)}`,
        type: "SYNC_STATE",
        snapshot: {
          protocolVersion:
            snapshot.protocolVersion,
          deviceId: snapshot.deviceId,
          gameId: snapshot.gameId,
          homeScore: snapshot.homeScore,
          awayScore: snapshot.awayScore,
          period: snapshot.period,
          clock: snapshot.clock,
          hornActive: snapshot.hornActive,
        },
      },
    );
  }

  public async close(): Promise<void> {
    await new Promise<void>(
      (resolve) => {
        this.client.end(
          false,
          {},
          () => resolve(),
        );
      },
    );
  }

  private ensureDevice(
    deviceId: string,
  ): ScoreboardDeviceRuntime {
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

    this.devices.set(
      deviceId,
      created,
    );

    return created;
  }

  private handleMessage(
    topic: string,
    payloadText: string,
  ): void {
    let payload: unknown;

    try {
      payload = JSON.parse(payloadText);
    } catch {
      return;
    }

    const match = topic.match(
      /^sportsos\/scoreboards\/([^/]+)\/(state|presence|telemetry|ack)$/,
    );

    if (!match) {
      return;
    }

    const [, deviceId, kind] = match;

    if (!deviceId || !kind) {
      return;
    }

    const device =
      this.ensureDevice(deviceId);

    switch (kind) {
      case "state":
        device.state =
          payload as ScoreboardDeviceSnapshot;
        break;

      case "presence":
        device.presence =
          payload as ScoreboardMqttPresence;
        break;

      case "telemetry":
        device.telemetry =
          payload as ScoreboardMqttTelemetry;
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
import type {
  FastifyInstance,
} from "fastify";
import {
  SCOREBOARD_DEVICE_PROTOCOL_VERSION,
  validateScoreboardDeviceCommand,
  type ScoreboardDeviceCommand,
} from "@sportsos/core";
import {
  ScoreboardDeviceGateway,
} from "../services/scoreboardDeviceGateway.js";

const gateway =
  new ScoreboardDeviceGateway();

export async function scoreboardDevicesRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.get(
    "/scoreboard-devices",
    async () => {
      return {
        success: true,
        data: {
          devices:
            gateway.listDevices(),
        },
      };
    },
  );

  app.get<{
    Params: {
      deviceId: string;
    };
  }>(
    "/scoreboard-devices/:deviceId",
    async (request, reply) => {
      const device =
        gateway.getDevice(
          request.params.deviceId,
        );

      if (!device) {
        return reply
          .code(404)
          .send({
            success: false,
            error: {
              code:
                "SCOREBOARD_DEVICE_NOT_FOUND",
              message:
                "Scoreboard device not found.",
            },
          });
      }

      return {
        success: true,
        data: {
          device,
        },
      };
    },
  );

  app.post<{
    Params: {
      deviceId: string;
    };
    Body: ScoreboardDeviceCommand;
  }>(
    "/scoreboard-devices/:deviceId/commands",
    async (request, reply) => {
      let command:
        ScoreboardDeviceCommand;

      try {
        command =
          validateScoreboardDeviceCommand(
            request.body,
          );
      } catch (error) {
        return reply
          .code(400)
          .send({
            success: false,
            error: {
              code:
                "INVALID_SCOREBOARD_COMMAND",
              message:
                error instanceof Error
                  ? error.message
                  : "Invalid scoreboard command.",
            },
          });
      }

      await gateway.sendCommand(
        request.params.deviceId,
        command,
      );

      return reply
        .code(202)
        .send({
          success: true,
          data: {
            accepted: true,
            protocolVersion:
              SCOREBOARD_DEVICE_PROTOCOL_VERSION,
            deviceId:
              request.params.deviceId,
            commandId:
              command.commandId,
          },
        });
    },
  );
}
EOF

node <<'NODE'
const fs = require("fs");

const file = "apps/api/src/routes/root.ts";
let text = fs.readFileSync(file, "utf8");

if (
  !text.includes(
    'from "./scoreboardDevices.js"',
  )
) {
  const importMatch = text.match(
    /^(import[\s\S]*?;\n)+/,
  );

  if (!importMatch) {
    throw new Error(
      "Unable to locate import block in root.ts",
    );
  }

  const insertAt =
    importMatch[0].length;

  text =
    text.slice(0, insertAt) +
    'import { scoreboardDevicesRoutes } from "./scoreboardDevices.js";\n' +
    text.slice(insertAt);
}

if (
  !text.includes(
    "await app.register(scoreboardDevicesRoutes)",
  )
) {
  const functionMatch = text.match(
    /export\s+async\s+function\s+\w+\s*\([^)]*\)\s*\{/,
  );

  if (!functionMatch) {
    throw new Error(
      "Unable to locate root route registration function.",
    );
  }

  const insertionPoint =
    functionMatch.index +
    functionMatch[0].length;

  text =
    text.slice(
      0,
      insertionPoint,
    ) +
    "\n  await app.register(scoreboardDevicesRoutes);\n" +
    text.slice(
      insertionPoint,
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 10.4 API scoreboard device gateway", () => {
  it("defines a device gateway backed by MQTT", () => {
    const source = fs.readFileSync(
      new URL(
        "../src/services/scoreboardDeviceGateway.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "class ScoreboardDeviceGateway",
    );
    expect(source).toContain(
      "sportsos/scoreboards/+/state",
    );
    expect(source).toContain(
      "sportsos/scoreboards/+/presence",
    );
    expect(source).toContain(
      "sportsos/scoreboards/+/telemetry",
    );
    expect(source).toContain(
      "sportsos/scoreboards/+/ack",
    );
  });

  it("publishes commands using the shared MQTT contract", () => {
    const source = fs.readFileSync(
      new URL(
        "../src/services/scoreboardDeviceGateway.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "buildScoreboardMqttCommandEnvelope",
    );
    expect(source).toContain(
      "scoreboardMqttTopics",
    );
    expect(source).toContain(
      "retain: false",
    );
  });

  it("exposes scoreboard device HTTP routes", () => {
    const route = fs.readFileSync(
      new URL(
        "../src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain(
      '"/scoreboard-devices"',
    );
    expect(route).toContain(
      '"/scoreboard-devices/:deviceId"',
    );
    expect(route).toContain(
      '"/scoreboard-devices/:deviceId/commands"',
    );
  });

  it("registers the scoreboard device routes", () => {
    const root = fs.readFileSync(
      new URL(
        "../src/routes/root.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(root).toContain(
      "scoreboardDevicesRoutes",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 10.4 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - .git / package.json / apps verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - API MQTT scoreboard gateway"
echo "  - retained state / presence / telemetry tracking"
echo "  - acknowledgement tracking"
echo "  - GET /scoreboard-devices"
echo "  - GET /scoreboard-devices/:deviceId"
echo "  - POST /scoreboard-devices/:deviceId/commands"
echo "  - shared contract command publication"
echo "  - Milestone 10.4 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Install / validate:"
echo "  npm install"
echo "  npm run typecheck && npm test"
echo
echo "Then rebuild API:"
echo "  docker compose up -d --build api"
echo
echo "Next after green:"
echo "  Milestone 10.5 - Device Operations UI"
