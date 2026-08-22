#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10.2-mqtt-device-transport-contract"
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

DEVICE_CONTRACT="packages/core/src/scoreboard-device-contract.ts"
MQTT_CONTRACT="packages/core/src/scoreboard-mqtt-contract.ts"
INDEX="packages/core/src/index.ts"
TEST="packages/core/test/scoreboard-mqtt-contract-10.2.test.ts"

for file in "$DEVICE_CONTRACT" "$INDEX"; do
  [[ -f "$file" ]] || {
    echo "ERROR: required prerequisite missing: $file" >&2
    exit 1
  }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$MQTT_CONTRACT")" \
  "$BACKUP_DIR/$(dirname "$INDEX")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$TEST")"

for file in "$MQTT_CONTRACT" "$INDEX" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$MQTT_CONTRACT" <<'EOF'
import type {
  ScoreboardDeviceCommand,
  ScoreboardDeviceSnapshot,
} from "./scoreboard-device-contract.js";

export const SCOREBOARD_MQTT_ROOT = "sportsos/scoreboards";

export type ScoreboardMqttTopicSet = {
  command: string;
  acknowledgement: string;
  state: string;
  telemetry: string;
  presence: string;
};

export type ScoreboardMqttCommandEnvelope = {
  deviceId: string;
  sentAt: string;
  command: ScoreboardDeviceCommand;
};

export type ScoreboardMqttAcknowledgementStatus =
  | "ACCEPTED"
  | "REJECTED"
  | "APPLIED";

export type ScoreboardMqttAcknowledgement = {
  deviceId: string;
  commandId: string;
  status: ScoreboardMqttAcknowledgementStatus;
  message: string | null;
  acknowledgedAt: string;
};

export type ScoreboardMqttTelemetry = {
  deviceId: string;
  firmwareVersion: string | null;
  ipAddress: string | null;
  wifiRssi: number | null;
  uptimeSeconds: number;
  freeHeapBytes: number | null;
  reportedAt: string;
};

export type ScoreboardMqttPresence = {
  deviceId: string;
  online: boolean;
  reportedAt: string;
};

export type ScoreboardMqttPublication =
  | {
      topicKind: "command";
      topic: string;
      qos: 1;
      retain: false;
      payload: ScoreboardMqttCommandEnvelope;
    }
  | {
      topicKind: "acknowledgement";
      topic: string;
      qos: 1;
      retain: false;
      payload: ScoreboardMqttAcknowledgement;
    }
  | {
      topicKind: "state";
      topic: string;
      qos: 1;
      retain: true;
      payload: ScoreboardDeviceSnapshot;
    }
  | {
      topicKind: "telemetry";
      topic: string;
      qos: 0;
      retain: false;
      payload: ScoreboardMqttTelemetry;
    }
  | {
      topicKind: "presence";
      topic: string;
      qos: 1;
      retain: true;
      payload: ScoreboardMqttPresence;
    };

function assertDeviceId(deviceId: string): string {
  const normalized = deviceId.trim();

  if (!normalized) {
    throw new Error("deviceId is required.");
  }

  if (!/^[A-Za-z0-9._-]+$/.test(normalized)) {
    throw new Error(
      "deviceId contains unsupported MQTT topic characters.",
    );
  }

  return normalized;
}

function assertCommandId(commandId: string): string {
  const normalized = commandId.trim();

  if (!normalized) {
    throw new Error("commandId is required.");
  }

  return normalized;
}

export function scoreboardMqttTopics(
  deviceId: string,
): ScoreboardMqttTopicSet {
  const id = assertDeviceId(deviceId);
  const base = `${SCOREBOARD_MQTT_ROOT}/${id}`;

  return {
    command: `${base}/command`,
    acknowledgement: `${base}/ack`,
    state: `${base}/state`,
    telemetry: `${base}/telemetry`,
    presence: `${base}/presence`,
  };
}

export function buildScoreboardMqttCommandEnvelope(
  deviceId: string,
  command: ScoreboardDeviceCommand,
  sentAt = new Date(),
): ScoreboardMqttCommandEnvelope {
  return {
    deviceId: assertDeviceId(deviceId),
    sentAt: sentAt.toISOString(),
    command,
  };
}

export function buildScoreboardMqttAcknowledgement(
  input: Omit<
    ScoreboardMqttAcknowledgement,
    "acknowledgedAt"
  > & {
    acknowledgedAt?: Date;
  },
): ScoreboardMqttAcknowledgement {
  return {
    deviceId: assertDeviceId(input.deviceId),
    commandId: assertCommandId(input.commandId),
    status: input.status,
    message: input.message,
    acknowledgedAt: (
      input.acknowledgedAt ?? new Date()
    ).toISOString(),
  };
}

export function buildScoreboardMqttPresence(
  deviceId: string,
  online: boolean,
  reportedAt = new Date(),
): ScoreboardMqttPresence {
  return {
    deviceId: assertDeviceId(deviceId),
    online,
    reportedAt: reportedAt.toISOString(),
  };
}

export function buildScoreboardMqttTelemetry(
  input: Omit<
    ScoreboardMqttTelemetry,
    "reportedAt"
  > & {
    reportedAt?: Date;
  },
): ScoreboardMqttTelemetry {
  if (
    !Number.isFinite(input.uptimeSeconds) ||
    input.uptimeSeconds < 0
  ) {
    throw new Error(
      "uptimeSeconds must be a non-negative number.",
    );
  }

  if (
    input.wifiRssi !== null &&
    !Number.isFinite(input.wifiRssi)
  ) {
    throw new Error(
      "wifiRssi must be null or a finite number.",
    );
  }

  if (
    input.freeHeapBytes !== null &&
    (
      !Number.isFinite(input.freeHeapBytes) ||
      input.freeHeapBytes < 0
    )
  ) {
    throw new Error(
      "freeHeapBytes must be null or a non-negative number.",
    );
  }

  return {
    deviceId: assertDeviceId(input.deviceId),
    firmwareVersion: input.firmwareVersion,
    ipAddress: input.ipAddress,
    wifiRssi: input.wifiRssi,
    uptimeSeconds: input.uptimeSeconds,
    freeHeapBytes: input.freeHeapBytes,
    reportedAt: (
      input.reportedAt ?? new Date()
    ).toISOString(),
  };
}

export function buildScoreboardMqttPublications(input: {
  deviceId: string;
  command?: ScoreboardMqttCommandEnvelope;
  acknowledgement?: ScoreboardMqttAcknowledgement;
  state?: ScoreboardDeviceSnapshot;
  telemetry?: ScoreboardMqttTelemetry;
  presence?: ScoreboardMqttPresence;
}): ScoreboardMqttPublication[] {
  const topics = scoreboardMqttTopics(input.deviceId);
  const publications: ScoreboardMqttPublication[] = [];

  if (input.command) {
    publications.push({
      topicKind: "command",
      topic: topics.command,
      qos: 1,
      retain: false,
      payload: input.command,
    });
  }

  if (input.acknowledgement) {
    publications.push({
      topicKind: "acknowledgement",
      topic: topics.acknowledgement,
      qos: 1,
      retain: false,
      payload: input.acknowledgement,
    });
  }

  if (input.state) {
    publications.push({
      topicKind: "state",
      topic: topics.state,
      qos: 1,
      retain: true,
      payload: input.state,
    });
  }

  if (input.telemetry) {
    publications.push({
      topicKind: "telemetry",
      topic: topics.telemetry,
      qos: 0,
      retain: false,
      payload: input.telemetry,
    });
  }

  if (input.presence) {
    publications.push({
      topicKind: "presence",
      topic: topics.presence,
      qos: 1,
      retain: true,
      payload: input.presence,
    });
  }

  return publications;
}
EOF

node <<'NODE'
const fs = require("fs");

const file = "packages/core/src/index.ts";
let text = fs.readFileSync(file, "utf8");

const badLine =
  'export * from "./scoreboard-mqtt-contract";';
const goodLine =
  'export * from "./scoreboard-mqtt-contract.js";';

text = text.replaceAll(badLine, goodLine);

if (!text.includes(goodLine)) {
  text = `${text.trimEnd()}\n${goodLine}\n`;
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  SCOREBOARD_DEVICE_PROTOCOL_VERSION,
} from "../src/scoreboard-device-contract.js";
import {
  SCOREBOARD_MQTT_ROOT,
  buildScoreboardMqttAcknowledgement,
  buildScoreboardMqttCommandEnvelope,
  buildScoreboardMqttPresence,
  buildScoreboardMqttPublications,
  buildScoreboardMqttTelemetry,
  scoreboardMqttTopics,
} from "../src/scoreboard-mqtt-contract.js";

describe("Milestone 10.2 MQTT device transport contract", () => {
  it("builds stable per-device MQTT topics", () => {
    expect(
      scoreboardMqttTopics("scoreboard-1"),
    ).toEqual({
      command:
        `${SCOREBOARD_MQTT_ROOT}/scoreboard-1/command`,
      acknowledgement:
        `${SCOREBOARD_MQTT_ROOT}/scoreboard-1/ack`,
      state:
        `${SCOREBOARD_MQTT_ROOT}/scoreboard-1/state`,
      telemetry:
        `${SCOREBOARD_MQTT_ROOT}/scoreboard-1/telemetry`,
      presence:
        `${SCOREBOARD_MQTT_ROOT}/scoreboard-1/presence`,
    });
  });

  it("rejects unsafe device ids for MQTT topics", () => {
    expect(() =>
      scoreboardMqttTopics("scoreboard/1"),
    ).toThrow(
      "deviceId contains unsupported MQTT topic characters.",
    );
  });

  it("wraps commands in a transport envelope", () => {
    const envelope =
      buildScoreboardMqttCommandEnvelope(
        "scoreboard-1",
        {
          protocolVersion:
            SCOREBOARD_DEVICE_PROTOCOL_VERSION,
          commandId: "cmd-1",
          type: "HORN",
          active: true,
        },
        new Date("2026-08-17T20:00:00.000Z"),
      );

    expect(envelope).toMatchObject({
      deviceId: "scoreboard-1",
      sentAt: "2026-08-17T20:00:00.000Z",
      command: {
        commandId: "cmd-1",
        type: "HORN",
      },
    });
  });

  it("builds command acknowledgements", () => {
    expect(
      buildScoreboardMqttAcknowledgement({
        deviceId: "scoreboard-1",
        commandId: "cmd-1",
        status: "APPLIED",
        message: null,
        acknowledgedAt: new Date(
          "2026-08-17T20:00:01.000Z",
        ),
      }),
    ).toMatchObject({
      deviceId: "scoreboard-1",
      commandId: "cmd-1",
      status: "APPLIED",
    });
  });

  it("builds presence and telemetry payloads", () => {
    expect(
      buildScoreboardMqttPresence(
        "scoreboard-1",
        true,
        new Date("2026-08-17T20:00:02.000Z"),
      ),
    ).toEqual({
      deviceId: "scoreboard-1",
      online: true,
      reportedAt: "2026-08-17T20:00:02.000Z",
    });

    expect(
      buildScoreboardMqttTelemetry({
        deviceId: "scoreboard-1",
        firmwareVersion: "1.0.0",
        ipAddress: "192.168.5.50",
        wifiRssi: -55,
        uptimeSeconds: 3600,
        freeHeapBytes: 120000,
        reportedAt: new Date(
          "2026-08-17T20:00:03.000Z",
        ),
      }),
    ).toMatchObject({
      firmwareVersion: "1.0.0",
      wifiRssi: -55,
      uptimeSeconds: 3600,
    });
  });

  it("uses retained state/presence and ephemeral command/telemetry", () => {
    const command =
      buildScoreboardMqttCommandEnvelope(
        "scoreboard-1",
        {
          protocolVersion:
            SCOREBOARD_DEVICE_PROTOCOL_VERSION,
          commandId: "cmd-2",
          type: "SET_SCORE",
          homeScore: 2,
          awayScore: 1,
        },
      );

    const presence =
      buildScoreboardMqttPresence(
        "scoreboard-1",
        true,
      );

    const publications =
      buildScoreboardMqttPublications({
        deviceId: "scoreboard-1",
        command,
        presence,
      });

    expect(publications).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          topicKind: "command",
          qos: 1,
          retain: false,
        }),
        expect.objectContaining({
          topicKind: "presence",
          qos: 1,
          retain: true,
        }),
      ]),
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 10.2 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - .git / package.json / apps verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - stable per-device MQTT topic contract"
echo "  - command envelopes"
echo "  - ACCEPTED / REJECTED / APPLIED acknowledgements"
echo "  - retained device state"
echo "  - retained online/offline presence"
echo "  - telemetry payloads"
echo "  - QoS / retain publication policy"
echo "  - NodeNext-safe .js imports/exports"
echo "  - Milestone 10.2 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Next after green:"
echo "  Milestone 10.3 - Scoreboard Simulator MQTT Adapter"
