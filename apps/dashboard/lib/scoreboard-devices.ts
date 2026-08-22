export type ScoreboardDeviceRuntime = {
  deviceId: string;
  state: {
    gameId: string | null;
    homeScore: number;
    awayScore: number;
    period: number | null;
    clock: {
      remainingMs: number;
      running: boolean;
    };
    hornActive: boolean;
    updatedAt: string;
  } | null;
  presence: {
    online: boolean;
    reportedAt: string;
  } | null;
  telemetry: {
    firmwareVersion: string | null;
    ipAddress: string | null;
    wifiRssi: number | null;
    uptimeSeconds: number;
    freeHeapBytes: number | null;
    reportedAt: string;
  } | null;
  lastAcknowledgement: {
    commandId: string;
    status: "ACCEPTED" | "REJECTED" | "APPLIED";
    message: string | null;
    acknowledgedAt: string;
  } | null;
};

export type ScoreboardDevicesResponse = {
  success: boolean;
  data?: {
    devices: ScoreboardDeviceRuntime[];
  };
};

export function formatScoreboardClock(
  remainingMs: number,
): string {
  const totalSeconds = Math.max(
    0,
    Math.floor(remainingMs / 1000),
  );
  const minutes = Math.floor(
    totalSeconds / 60,
  );
  const seconds = totalSeconds % 60;

  return `${minutes}:${seconds
    .toString()
    .padStart(2, "0")}`;
}

export function scoreboardDeviceHealth(
  device: ScoreboardDeviceRuntime,
): "ONLINE" | "OFFLINE" | "UNKNOWN" {
  if (!device.presence) {
    return "UNKNOWN";
  }

  return device.presence.online
    ? "ONLINE"
    : "OFFLINE";
}
