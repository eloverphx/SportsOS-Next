import { listScoreboardDevices } from "../modules/scoreboard-devices/repository.js";

export type ScoreboardControlReadinessDecision = {
  ready: boolean;
  deviceId: string;
  lastHeartbeatAt: string | null;
  heartbeatAgeMs: number | null;
  thresholdMs: number;
  reason: string | null;
};

const DEFAULT_THRESHOLD_MS =
  Number.parseInt(
    process.env.SPORTSOS_CONTROL_HEARTBEAT_MAX_AGE_MS ??
      "30000",
    10,
  );

function heartbeatTimestamp(
  device: unknown,
): string | null {
  if (
    typeof device !== "object" ||
    device === null
  ) {
    return null;
  }

  const record =
    device as Record<string, unknown>;

  const candidates = [
    record.lastHeartbeatAt,
    record.lastSeenAt,
    record.heartbeatAt,
    record.updatedAt,
  ];

  for (const candidate of candidates) {
    if (
      typeof candidate === "string" &&
      candidate.trim()
    ) {
      return candidate.trim();
    }
  }

  return null;
}

export async function evaluateScoreboardControlReadiness(
  deviceId: string,
): Promise<ScoreboardControlReadinessDecision> {
  const devices =
    await listScoreboardDevices();

  const device =
    devices.find(
      (candidate) => {
        const record =
          candidate as unknown as
            Record<string, unknown>;

        return [
          record.deviceId,
          record.externalId,
          record.hardwareId,
          record.identifier,
          record.key,
          record.serialNumber,
        ].some(
          (value) =>
            typeof value ===
              "string" &&
            value ===
              deviceId,
        );
      },
    ) ?? null;

  const thresholdMs =
    Number.isFinite(
      DEFAULT_THRESHOLD_MS,
    ) &&
    DEFAULT_THRESHOLD_MS > 0
      ? DEFAULT_THRESHOLD_MS
      : 30000;

  if (!device) {
    return {
      ready: false,
      deviceId,
      lastHeartbeatAt: null,
      heartbeatAgeMs: null,
      thresholdMs,
      reason:
        "Scoreboard device record was not found.",
    };
  }

  const lastHeartbeatAt =
    heartbeatTimestamp(
      device,
    );

  if (!lastHeartbeatAt) {
    return {
      ready: false,
      deviceId,
      lastHeartbeatAt: null,
      heartbeatAgeMs: null,
      thresholdMs,
      reason:
        "Scoreboard device heartbeat is unavailable.",
    };
  }

  const heartbeatMs =
    Date.parse(
      lastHeartbeatAt,
    );

  if (
    !Number.isFinite(
      heartbeatMs,
    )
  ) {
    return {
      ready: false,
      deviceId,
      lastHeartbeatAt,
      heartbeatAgeMs: null,
      thresholdMs,
      reason:
        "Scoreboard device heartbeat timestamp is invalid.",
    };
  }

  const heartbeatAgeMs =
    Math.max(
      0,
      Date.now() -
        heartbeatMs,
    );

  if (
    heartbeatAgeMs >
    thresholdMs
  ) {
    return {
      ready: false,
      deviceId,
      lastHeartbeatAt,
      heartbeatAgeMs,
      thresholdMs,
      reason:
        `Scoreboard device heartbeat is stale (${heartbeatAgeMs}ms old).`,
    };
  }

  return {
    ready: true,
    deviceId,
    lastHeartbeatAt,
    heartbeatAgeMs,
    thresholdMs,
    reason: null,
  };
}
