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
