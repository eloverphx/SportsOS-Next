import type { PlayerPosition, PlayerStatus } from "../players/types.js";

export const rosterRoles = ["PLAYER", "CAPTAIN", "ALTERNATE"] as const;
export type RosterRole = (typeof rosterRoles)[number];

export interface RosterEntry {
  id: number;
  seasonId: number;
  seasonName: string;
  teamId: number;
  teamName: string;
  organizationId: number;
  playerId: number;
  firstName: string;
  lastName: string;
  preferredName: string | null;
  playerStatus: PlayerStatus;
  photoUrl: string | null;
  jerseyNumber: number | null;
  position: PlayerPosition;
  role: RosterRole;
  active: boolean;
  createdAt: Date | string;
  updatedAt: Date | string;
}
