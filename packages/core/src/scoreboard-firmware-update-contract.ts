export const SCOREBOARD_FIRMWARE_UPDATE_PROTOCOL_VERSION =
  1 as const;

export type FirmwareReleaseChannel =
  | "stable"
  | "beta"
  | "development";

export type FirmwareReleaseTarget =
  "esp32dev";

export type ScoreboardFirmwareRelease = {
  protocolVersion:
    typeof SCOREBOARD_FIRMWARE_UPDATE_PROTOCOL_VERSION;
  releaseId: string;
  version: string;
  channel: FirmwareReleaseChannel;
  target: FirmwareReleaseTarget;
  createdAt: string;
  firmwareFile: string;
  firmwareSha256: string;
  firmwareSizeBytes: number;
  minimumCurrentVersion: string | null;
  mandatory: boolean;
};

export type ScoreboardFirmwareUpdateOffer = {
  deviceId: string;
  currentVersion: string;
  release: ScoreboardFirmwareRelease;
};

export type ScoreboardFirmwareUpdateStatus =
  | "IDLE"
  | "AVAILABLE"
  | "DOWNLOADING"
  | "VERIFYING"
  | "READY_TO_INSTALL"
  | "INSTALLING"
  | "REBOOTING"
  | "SUCCEEDED"
  | "FAILED";

export type ScoreboardFirmwareUpdateReport = {
  deviceId: string;
  releaseId: string;
  previousVersion: string;
  targetVersion: string;
  status: ScoreboardFirmwareUpdateStatus;
  progressPercent: number | null;
  error: string | null;
  reportedAt: string;
};

export function isTerminalFirmwareUpdateStatus(
  status: ScoreboardFirmwareUpdateStatus,
): boolean {
  return (
    status === "SUCCEEDED" ||
    status === "FAILED"
  );
}
