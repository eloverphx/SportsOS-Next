export const gameEventTypes = ["GOAL", "PENALTY"] as const;
export const gameEventSides = ["home", "away"] as const;

export type GameEventType = (typeof gameEventTypes)[number];
export type GameEventSide = (typeof gameEventSides)[number];

export interface GameEvent {
  id: number;
  gameId: number;
  organizationId: number;
  type: GameEventType;
  side: GameEventSide;
  period: number;
  clockRemainingMs: number;
  playerId: number | null;
  playerName: string | null;
  playerJerseyNumber: number | null;
  assist1PlayerId: number | null;
  assist1PlayerName: string | null;
  assist2PlayerId: number | null;
  assist2PlayerName: string | null;
  penaltyCode: string | null;
  penaltyMinutes: number | null;
  notes: string | null;
  voidedAt: string | null;
  createdAt: string;
}

export interface GameEventPlayerOption {
  id: number;
  teamId: number;
  firstName: string;
  lastName: string;
  preferredName: string | null;
  jerseyNumber: number | null;
}
