export const scoreboardDeviceStatuses = ["OFFLINE", "ONLINE"] as const;

export type ScoreboardDeviceStatus = (typeof scoreboardDeviceStatuses)[number];

export interface ScoreboardDevice {
  id: number;
  organizationId: number;
  organizationName: string;
  gameId: number | null;
  gameLabel: string | null;
  name: string;
  location: string | null;
  deviceKey: string;
  status: ScoreboardDeviceStatus;
  lastSeenAt: Date | string | null;
  createdAt: Date | string;
  updatedAt: Date | string;
}

export interface ScoreboardDeviceInput {
  organizationId: number;
  gameId: number | null;
  name: string;
  location: string | null;
}
