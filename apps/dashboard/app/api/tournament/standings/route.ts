import { NextResponse } from "next/server";
import {
  buildTournamentStandings,
  type TournamentStandingGame,
  type TournamentStandingTeam,
} from "../../../../lib/tournament-standings";
import {
  buildTournamentPoolStandings,
  deriveDefaultPools,
} from "../../../../lib/tournament-pools";

const API_BASE_URL =
  process.env.SPORTSOS_API_URL ??
  process.env.API_URL ??
  process.env.NEXT_PUBLIC_API_URL ??
  "http://api:4001";

type UnknownRecord = Record<string, unknown>;

function record(value: unknown): UnknownRecord | null {
  return value && typeof value === "object"
    ? (value as UnknownRecord)
    : null;
}

function stringValue(
  value: unknown,
  fallback = "",
): string {
  return typeof value === "string" ? value : fallback;
}

function numberValue(
  value: unknown,
  fallback = 0,
): number {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : fallback;
}

function gamesFromPayload(payload: unknown): unknown[] {
  if (Array.isArray(payload)) {
    return payload;
  }

  const root = record(payload);

  if (!root) {
    return [];
  }

  if (Array.isArray(root.games)) {
    return root.games;
  }

  const data = record(root.data);

  if (data && Array.isArray(data.games)) {
    return data.games;
  }

  return [];
}

function normalizeGame(
  value: unknown,
): {
  game: TournamentStandingGame;
  home: TournamentStandingTeam;
  away: TournamentStandingTeam;
} | null {
  const input = record(value);

  if (!input) {
    return null;
  }

  const id = stringValue(input.id);
  const homeTeamId = stringValue(input.homeTeamId);
  const awayTeamId = stringValue(input.awayTeamId);

  if (!id || !homeTeamId || !awayTeamId) {
    return null;
  }

  const homeTeamName =
    stringValue(input.homeTeamName) ||
    stringValue(record(input.homeTeam)?.name) ||
    homeTeamId;

  const awayTeamName =
    stringValue(input.awayTeamName) ||
    stringValue(record(input.awayTeam)?.name) ||
    awayTeamId;

  return {
    game: {
      id,
      homeTeamId,
      awayTeamId,
      homeScore: numberValue(input.homeScore),
      awayScore: numberValue(input.awayScore),
      status: stringValue(input.status),
    },
    home: {
      id: homeTeamId,
      name: homeTeamName,
    },
    away: {
      id: awayTeamId,
      name: awayTeamName,
    },
  };
}

export async function GET() {
  const response = await fetch(`${API_BASE_URL}/games`, {
    cache: "no-store",
  });

  if (!response.ok) {
    return NextResponse.json(
      {
        error: "Unable to load tournament games.",
        upstreamStatus: response.status,
      },
      {
        status: 502,
      },
    );
  }

  const payload = (await response.json()) as unknown;
  const normalized = gamesFromPayload(payload)
    .map(normalizeGame)
    .filter(
      (
        value,
      ): value is NonNullable<ReturnType<typeof normalizeGame>> =>
        value !== null,
    );

  const teamsById = new Map<string, TournamentStandingTeam>();

  for (const item of normalized) {
    teamsById.set(item.home.id, item.home);
    teamsById.set(item.away.id, item.away);
  }

  const teams = [...teamsById.values()];
  const games = normalized.map((item) => item.game);
  const pools = deriveDefaultPools(teams);

  return NextResponse.json({
    teams,
    games,
    pools,
    standings: buildTournamentStandings(teams, games),
    poolStandings: buildTournamentPoolStandings(
      pools,
      teams,
      games,
    ),
  });
}
