export const playerPositions = ["Goalie", "Defense", "Left Wing", "Center", "Right Wing"] as const;
export const playerStatuses = ["ACTIVE", "INACTIVE", "INJURED", "SUSPENDED"] as const;
export const playerShoots = ["L", "R"] as const;

export type PlayerPosition = (typeof playerPositions)[number];
export type PlayerStatus = (typeof playerStatuses)[number];
export type PlayerShoots = (typeof playerShoots)[number];

export interface Player {
  id: number;
  organizationId: number;
  organizationName: string;
  teamId: number | null;
  teamName: string | null;
  firstName: string;
  lastName: string;
  preferredName: string | null;
  jerseyNumber: number | null;
  position: PlayerPosition;
  shoots: PlayerShoots | null;
  birthDate: string | null;
  heightCm: number | null;
  weightKg: number | null;
  email: string | null;
  phone: string | null;
  photoAssetId: number | null;
  photoUrl: string | null;
  status: PlayerStatus;
  createdAt: Date | string;
  updatedAt: Date | string;
}
