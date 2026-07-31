export const gameStatuses = ["SCHEDULED", "LIVE", "FINAL", "POSTPONED", "CANCELED"] as const;

export type GameStatus = (typeof gameStatuses)[number];

export interface Game {
  id: number;
  organizationId: number;
  organizationName: string;
  seasonId: number;
  seasonName: string;
  homeTeamId: number;
  homeTeamName: string;
  awayTeamId: number;
  awayTeamName: string;
  scheduledStart: string;
  timezone: string;
  venue: string | null;
  status: GameStatus;
  homeScore: number;
  awayScore: number;
  notes: string | null;
  createdAt: Date | string;
  updatedAt: Date | string;
}
