import type {
  ScoreboardDeviceRuntime,
} from "./scoreboard-devices";

export type ScoreboardAssignment = {
  gameId: string;
  deviceId: string;
  assignedAt: string;
};

export type ScoreboardHardwareStage =
  | "NO_DEVICES"
  | "DEGRADED"
  | "READY"
  | "ACTIVE";

export type ScoreboardHardwareOperationsSummary = {
  stage: ScoreboardHardwareStage;
  discovered: number;
  online: number;
  assigned: number;
  activeGames: number;
  alerts: string[];
  readinessPercent: number;
};

export function buildScoreboardHardwareOperationsSummary(
  devices: ScoreboardDeviceRuntime[],
  assignments: ScoreboardAssignment[],
): ScoreboardHardwareOperationsSummary {
  const discovered = devices.length;

  const online = devices.filter(
    (device) =>
      device.presence?.online === true,
  ).length;

  const assigned = assignments.length;

  const activeGames = assignments.filter(
    (assignment) =>
      devices.some(
        (device) =>
          device.deviceId ===
            assignment.deviceId &&
          device.presence?.online === true &&
          device.state?.gameId ===
            assignment.gameId,
      ),
  ).length;

  const alerts: string[] = [];

  if (discovered === 0) {
    alerts.push(
      "No scoreboard devices have reported through MQTT.",
    );
  }

  if (
    discovered > 0 &&
    online < discovered
  ) {
    alerts.push(
      `${discovered - online} scoreboard device(s) are offline.`,
    );
  }

  for (const assignment of assignments) {
    const device = devices.find(
      (candidate) =>
        candidate.deviceId ===
        assignment.deviceId,
    );

    if (!device) {
      alerts.push(
        `Assigned device ${assignment.deviceId} has not been discovered.`,
      );
      continue;
    }

    if (!device.presence?.online) {
      alerts.push(
        `Assigned device ${assignment.deviceId} is offline.`,
      );
    }
  }

  let stage: ScoreboardHardwareStage =
    "NO_DEVICES";

  if (discovered > 0) {
    stage =
      online === discovered
        ? "READY"
        : "DEGRADED";
  }

  if (
    assigned > 0 &&
    activeGames === assigned &&
    online > 0
  ) {
    stage = "ACTIVE";
  }

  const checks = [
    discovered > 0,
    discovered > 0 && online === discovered,
    assigned === 0 || activeGames === assigned,
    alerts.length === 0,
  ];

  const readinessPercent =
    Math.round(
      (checks.filter(Boolean).length /
        checks.length) *
        100,
    );

  return {
    stage,
    discovered,
    online,
    assigned,
    activeGames,
    alerts,
    readinessPercent,
  };
}
