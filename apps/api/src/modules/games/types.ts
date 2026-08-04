export const gameStatuses = ["SCHEDULED", "LIVE", "FINAL", "POSTPONED", "CANCELED"] as const;

export type GameStatus = (typeof gameStatuses)[number];

export interface Game {
  id: number;
  organizationId: number;
  organizationName: string;
  organizationLogoUrl: string | null;
  organizationPrimaryColor: string;
  organizationSecondaryColor: string;
  seasonId: number;
  seasonName: string;
  homeTeamId: number | null;
  homeTeamName: string;
  homeTeamLogoUrl: string | null;
  homeTeamPrimaryColor: string;
  homeTeamSecondaryColor: string;
  homeTeamOrganizationName: string | null;
  homeExternalName: string | null;
  awayTeamId: number | null;
  awayTeamName: string;
  awayTeamLogoUrl: string | null;
  awayTeamPrimaryColor: string;
  awayTeamSecondaryColor: string;
  awayTeamOrganizationName: string | null;
  awayExternalName: string | null;
  scheduledStart: string;
  timezone: string;
  venue: string | null;
  status: GameStatus;
  homeScore: number;
  awayScore: number;
  period: number;
  periodLengthMs: number;
  clockRemainingMs: number;
  clockRunning: boolean;
  clockStartedAt: string | null;
  regulationPeriods: number;
  regulationPeriodLengthMs: number;
  intermissionLengthMs: number;
  intermissionRemainingMs: number;
  intermissionRunning: boolean;
  intermissionStartedAt: string | null;
  intermissionReady: boolean;
  overtimeEnabled: boolean;
  overtimeLengthMs: number;
  periodLabel: string;
  canAdvancePeriod: boolean;
  notes: string | null;
  createdAt: Date | string;
  updatedAt: Date | string;
}

export interface GameTeamOption {
  id: number;
  organizationId: number;
  organizationName: string;
  name: string;
}
