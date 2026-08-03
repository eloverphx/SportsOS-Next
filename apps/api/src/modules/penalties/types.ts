export type PenaltySide = "home" | "away";

export interface ActivePenalty {
  id: number;
  gameEventId: number;
  gameId: number;
  side: PenaltySide;
  playerName: string | null;
  jerseyNumber: number | null;
  infraction: string;
  originalDurationMs: number;
  remainingMs: number;
  running: boolean;
  startedAt: string | null;
  createdAt: string;
}
