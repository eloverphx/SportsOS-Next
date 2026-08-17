#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="8.9-bracket-result-integration-persistence"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

SEEDING_LIB="apps/dashboard/lib/tournament-bracket-seeding.ts"
ADVANCE_LIB="apps/dashboard/lib/tournament-bracket-advancement.ts"
RESULT_LIB="apps/dashboard/lib/tournament-bracket-results.ts"
RESULT_ROUTE="apps/dashboard/app/api/tournament/bracket/results/route.ts"
TEST="apps/dashboard/test/tournament-bracket-results-8.9.test.ts"

for file in "$SEEDING_LIB" "$ADVANCE_LIB"; do
  [[ -f "$file" ]] || {
    echo "ERROR: required prerequisite missing: $file" >&2
    exit 1
  }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$RESULT_LIB")" \
  "$BACKUP_DIR/$(dirname "$RESULT_ROUTE")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$RESULT_ROUTE")"

for file in "$RESULT_LIB" "$RESULT_ROUTE" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$RESULT_LIB" <<'EOF'
import type {
  BracketMatchup,
} from "./tournament-bracket-seeding";
import type {
  BracketMatchupResult,
} from "./tournament-bracket-advancement";

export type AuthoritativeTournamentGame = {
  id: string;
  homeTeamId: string;
  awayTeamId: string;
  homeScore: number;
  awayScore: number;
  status: string;
};

function isFinalStatus(status: string): boolean {
  const normalized = status.trim().toUpperCase();

  return (
    normalized === "FINAL" ||
    normalized === "COMPLETE" ||
    normalized === "COMPLETED"
  );
}

function samePair(
  matchup: BracketMatchup,
  game: AuthoritativeTournamentGame,
): boolean {
  if (!matchup.homeSeed || !matchup.awaySeed) {
    return false;
  }

  const bracketHome = matchup.homeSeed.teamId;
  const bracketAway = matchup.awaySeed.teamId;

  return (
    (game.homeTeamId === bracketHome &&
      game.awayTeamId === bracketAway) ||
    (game.homeTeamId === bracketAway &&
      game.awayTeamId === bracketHome)
  );
}

function normalizeScoreOrientation(
  matchup: BracketMatchup,
  game: AuthoritativeTournamentGame,
): {
  homeScore: number;
  awayScore: number;
} {
  if (!matchup.homeSeed || !matchup.awaySeed) {
    return {
      homeScore: 0,
      awayScore: 0,
    };
  }

  if (game.homeTeamId === matchup.homeSeed.teamId) {
    return {
      homeScore: game.homeScore,
      awayScore: game.awayScore,
    };
  }

  return {
    homeScore: game.awayScore,
    awayScore: game.homeScore,
  };
}

export function deriveBracketResultsFromGames(
  matchups: BracketMatchup[],
  games: AuthoritativeTournamentGame[],
): BracketMatchupResult[] {
  const finalizedGames = games.filter((game) =>
    isFinalStatus(game.status),
  );

  return matchups.flatMap((matchup) => {
    if (matchup.bye || !matchup.homeSeed || !matchup.awaySeed) {
      return [];
    }

    const matches = finalizedGames.filter((game) =>
      samePair(matchup, game),
    );

    if (matches.length === 0) {
      return [];
    }

    if (matches.length > 1) {
      throw new Error(
        `Multiple finalized games match bracket matchup ${matchup.id}.`,
      );
    }

    const game = matches[0];

    if (!game) {
      return [];
    }

    if (
      !Number.isFinite(game.homeScore) ||
      !Number.isFinite(game.awayScore)
    ) {
      throw new Error(
        `Invalid authoritative score for game ${game.id}.`,
      );
    }

    const oriented = normalizeScoreOrientation(
      matchup,
      game,
    );

    return [
      {
        matchupId: matchup.id,
        homeScore: oriented.homeScore,
        awayScore: oriented.awayScore,
        status: game.status,
      },
    ];
  });
}
EOF

cat > "$RESULT_ROUTE" <<'EOF'
import { NextResponse } from "next/server";
import {
  seedBracket,
} from "../../../../../lib/tournament-bracket-seeding";
import {
  deriveBracketResultsFromGames,
  type AuthoritativeTournamentGame,
} from "../../../../../lib/tournament-bracket-results";
import {
  buildTournamentStandings,
  type TournamentStandingGame,
  type TournamentStandingTeam,
} from "../../../../../lib/tournament-standings";

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
  standingGame: TournamentStandingGame;
  authoritativeGame: AuthoritativeTournamentGame;
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

  const standingGame: TournamentStandingGame = {
    id,
    homeTeamId,
    awayTeamId,
    homeScore: numberValue(input.homeScore),
    awayScore: numberValue(input.awayScore),
    status: stringValue(input.status),
  };

  return {
    standingGame,
    authoritativeGame: {
      ...standingGame,
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
        error: "Unable to load authoritative SportsOS games.",
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
  const standingGames = normalized.map(
    (item) => item.standingGame,
  );

  const standings = buildTournamentStandings(
    teams,
    standingGames,
  );

  const seeded = seedBracket(standings);

  const results = deriveBracketResultsFromGames(
    seeded.firstRound,
    normalized.map(
      (item) => item.authoritativeGame,
    ),
  );

  return NextResponse.json({
    source: "sportsos-authoritative-games",
    results,
  });
}
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  deriveBracketResultsFromGames,
} from "../lib/tournament-bracket-results";
import type {
  BracketMatchup,
} from "../lib/tournament-bracket-seeding";

const matchup: BracketMatchup = {
  id: "round-1-slot-1",
  round: 1,
  slot: 1,
  homeSeed: {
    seed: 1,
    teamId: "a",
    teamName: "Lakers",
  },
  awaySeed: {
    seed: 4,
    teamId: "d",
    teamName: "Wolves",
  },
  bye: false,
};

describe("Milestone 8.9 bracket result integration / persistence", () => {
  it("derives bracket results from finalized authoritative games", () => {
    const results = deriveBracketResultsFromGames(
      [matchup],
      [
        {
          id: "game-1",
          homeTeamId: "a",
          awayTeamId: "d",
          homeScore: 5,
          awayScore: 2,
          status: "FINAL",
        },
      ],
    );

    expect(results).toEqual([
      {
        matchupId: "round-1-slot-1",
        homeScore: 5,
        awayScore: 2,
        status: "FINAL",
      },
    ]);
  });

  it("normalizes score orientation when API home/away is reversed", () => {
    const results = deriveBracketResultsFromGames(
      [matchup],
      [
        {
          id: "game-2",
          homeTeamId: "d",
          awayTeamId: "a",
          homeScore: 1,
          awayScore: 4,
          status: "FINAL",
        },
      ],
    );

    expect(results[0]).toMatchObject({
      homeScore: 4,
      awayScore: 1,
    });
  });

  it("ignores unfinished games", () => {
    expect(
      deriveBracketResultsFromGames(
        [matchup],
        [
          {
            id: "game-live",
            homeTeamId: "a",
            awayTeamId: "d",
            homeScore: 3,
            awayScore: 2,
            status: "LIVE",
          },
        ],
      ),
    ).toEqual([]);
  });

  it("ignores unrelated games", () => {
    expect(
      deriveBracketResultsFromGames(
        [matchup],
        [
          {
            id: "other",
            homeTeamId: "a",
            awayTeamId: "b",
            homeScore: 3,
            awayScore: 0,
            status: "FINAL",
          },
        ],
      ),
    ).toEqual([]);
  });

  it("does not create a result for a bye", () => {
    expect(
      deriveBracketResultsFromGames(
        [
          {
            ...matchup,
            awaySeed: null,
            bye: true,
          },
        ],
        [],
      ),
    ).toEqual([]);
  });

  it("rejects ambiguous duplicate finalized games", () => {
    expect(() =>
      deriveBracketResultsFromGames(
        [matchup],
        [
          {
            id: "game-1",
            homeTeamId: "a",
            awayTeamId: "d",
            homeScore: 2,
            awayScore: 1,
            status: "FINAL",
          },
          {
            id: "game-2",
            homeTeamId: "a",
            awayTeamId: "d",
            homeScore: 4,
            awayScore: 3,
            status: "FINAL",
          },
        ],
      ),
    ).toThrow(
      "Multiple finalized games match bracket matchup",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 8.9 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - authoritative bracket-result adapter"
echo "  - bracket results derived from persisted SportsOS games"
echo "  - no duplicate local bracket-result datastore"
echo "  - reversed home/away score normalization"
echo "  - unfinished games excluded"
echo "  - ambiguity protection for duplicate matching finals"
echo "  - GET /api/tournament/bracket/results"
echo "  - Milestone 8.9 tests"
echo
echo "Authoritative source:"
echo "  SportsOS /games records"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo "  npm run build && \\"
echo "  docker compose up -d --build dashboard && \\"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 8.10 - Tournament Standings / Bracket Operations Dashboard"
