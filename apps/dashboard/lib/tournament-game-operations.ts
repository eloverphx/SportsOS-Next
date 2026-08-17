export type TournamentGameOperationsStatus =
  | "SCHEDULED"
  | "PREGAME"
  | "READY"
  | "LIVE"
  | "FINAL"
  | "CANCELED"
  | "UNKNOWN";

export type TournamentGameOperationsGame = {
  id: string;
  homeTeamName: string;
  awayTeamName: string;
  venueName: string | null;
  rinkName: string | null;
  scheduledStart: string | null;
  status: TournamentGameOperationsStatus;
  scoringStatus: string;
  readiness: {
    teamsAssigned: boolean;
    rinkAssigned: boolean;
    scheduledStartAssigned: boolean;
  };
};

type UnknownRecord = Record<string, unknown>;

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function firstRecord(...values: unknown[]): UnknownRecord | null {
  for (const value of values) {
    if (isRecord(value)) return value;
  }
  return null;
}

function firstString(...values: unknown[]): string | null {
  for (const value of values) {
    if (typeof value === "string" && value.trim().length > 0) {
      return value.trim();
    }
    if (typeof value === "number" && Number.isFinite(value)) {
      return String(value);
    }
  }
  return null;
}

function normalizeStatus(value: unknown): TournamentGameOperationsStatus {
  const candidate = firstString(value)?.toUpperCase() ?? "UNKNOWN";
  switch (candidate) {
    case "SCHEDULED":
    case "PREGAME":
    case "READY":
    case "LIVE":
    case "FINAL":
    case "CANCELED":
      return candidate;
    default:
      return "UNKNOWN";
  }
}

function teamName(value: unknown, fallback: string): string {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (!isRecord(value)) return fallback;
  return (
    firstString(
      value.name,
      value.displayName,
      value.shortName,
      value.teamName,
      value.abbreviation,
    ) ?? fallback
  );
}

export function normalizeTournamentGame(
  value: unknown,
): TournamentGameOperationsGame | null {
  if (!isRecord(value)) return null;

  const homeTeam = firstRecord(value.homeTeam, value.home_team);
  const awayTeam = firstRecord(value.awayTeam, value.away_team);
  const venue = firstRecord(value.venue);
  const rink = firstRecord(value.rink);

  const id = firstString(value.id, value.gameId, value.game_id);
  if (!id) return null;

  const homeTeamName = teamName(
    homeTeam ?? value.homeTeamName ?? value.home_team_name,
    "Home team unassigned",
  );
  const awayTeamName = teamName(
    awayTeam ?? value.awayTeamName ?? value.away_team_name,
    "Away team unassigned",
  );

  const venueName = firstString(
    venue?.name,
    value.venueName,
    value.venue_name,
  );
  const rinkName = firstString(
    rink?.name,
    value.rinkName,
    value.rink_name,
    value.rink,
  );
  const scheduledStart = firstString(
    value.scheduledStart,
    value.scheduled_start,
    value.scheduledAt,
    value.scheduled_at,
    value.startTime,
    value.start_time,
  );
  const status = normalizeStatus(value.status);

  const scoringStatus =
    firstString(
      value.scoringStatus,
      value.scoring_status,
      isRecord(value.scoring) ? value.scoring.status : null,
    ) ?? (status === "LIVE" ? "ACTIVE" : "NOT_STARTED");

  return {
    id,
    homeTeamName,
    awayTeamName,
    venueName,
    rinkName,
    scheduledStart,
    status,
    scoringStatus,
    readiness: {
      teamsAssigned:
        homeTeamName !== "Home team unassigned" &&
        awayTeamName !== "Away team unassigned",
      rinkAssigned: Boolean(rinkName),
      scheduledStartAssigned: Boolean(scheduledStart),
    },
  };
}

export function extractTournamentGameList(
  payload: unknown,
): TournamentGameOperationsGame[] {
  let candidates: unknown[] = [];

  if (Array.isArray(payload)) {
    candidates = payload;
  } else if (isRecord(payload)) {
    if (Array.isArray(payload.games)) {
      candidates = payload.games;
    } else if (isRecord(payload.data) && Array.isArray(payload.data.games)) {
      candidates = payload.data.games;
    } else if (Array.isArray(payload.data)) {
      candidates = payload.data;
    }
  }

  return candidates
    .map(normalizeTournamentGame)
    .filter((game): game is TournamentGameOperationsGame => game !== null)
    .filter((game) => game.status !== "CANCELED");
}

export function extractTournamentGame(
  payload: unknown,
): TournamentGameOperationsGame | null {
  if (isRecord(payload)) {
    if ("game" in payload) {
      const game = normalizeTournamentGame(payload.game);
      if (game) return game;
    }
    if (isRecord(payload.data) && "game" in payload.data) {
      const game = normalizeTournamentGame(payload.data.game);
      if (game) return game;
    }
    if ("data" in payload) {
      const game = normalizeTournamentGame(payload.data);
      if (game) return game;
    }
  }

  return normalizeTournamentGame(payload);
}

export function readinessCount(game: TournamentGameOperationsGame): {
  passed: number;
  total: number;
} {
  const checks = Object.values(game.readiness);
  return {
    passed: checks.filter(Boolean).length,
    total: checks.length,
  };
}
