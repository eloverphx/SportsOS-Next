#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="8.2-tournament-standings-api-ui"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

ENGINE="apps/dashboard/lib/tournament-standings.ts"
PAGE="apps/dashboard/app/tournament/standings/page.tsx"
ROUTE="apps/dashboard/app/api/tournament/standings/route.ts"
COMPONENT="apps/dashboard/components/tournament/TournamentStandingsTable.tsx"
TEST="apps/dashboard/test/tournament-standings-8.2.test.ts"

[[ -f "$ENGINE" ]] || {
  echo "ERROR: Milestone 8.1 standings engine missing: $ENGINE" >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$PAGE")" \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$COMPONENT")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$PAGE")" \
  "$(dirname "$ROUTE")" \
  "$(dirname "$COMPONENT")"

for file in "$PAGE" "$ROUTE" "$COMPONENT" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$ROUTE" <<'EOF'
import { NextResponse } from "next/server";
import {
  buildTournamentStandings,
  type TournamentStandingGame,
  type TournamentStandingTeam,
} from "../../../../lib/tournament-standings";

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

  return NextResponse.json({
    teams,
    games,
    standings: buildTournamentStandings(teams, games),
  });
}
EOF

cat > "$COMPONENT" <<'EOF'
"use client";

import { useEffect, useState } from "react";
import type {
  TournamentStandingRow,
} from "../../lib/tournament-standings";

type StandingsResponse = {
  standings?: TournamentStandingRow[];
  error?: string;
};

export function TournamentStandingsTable() {
  const [rows, setRows] = useState<TournamentStandingRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    const load = async () => {
      try {
        const response = await fetch("/api/tournament/standings", {
          cache: "no-store",
        });

        const payload = (await response.json()) as StandingsResponse;

        if (!response.ok) {
          throw new Error(
            payload.error ?? "Unable to load standings.",
          );
        }

        if (active) {
          setRows(payload.standings ?? []);
        }
      } catch (cause) {
        if (active) {
          setError(
            cause instanceof Error
              ? cause.message
              : "Unable to load standings.",
          );
        }
      } finally {
        if (active) {
          setLoading(false);
        }
      }
    };

    void load();

    return () => {
      active = false;
    };
  }, []);

  if (loading) {
    return (
      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5 text-sm text-slate-400">
        Loading tournament standings...
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-xl border border-red-900/60 bg-red-950/20 p-5 text-sm text-red-300">
        {error}
      </div>
    );
  }

  return (
    <section
      data-testid="tournament-standings-table"
      className="overflow-hidden rounded-xl border border-slate-800 bg-slate-950/40"
    >
      <div className="border-b border-slate-800 px-5 py-4">
        <h2 className="font-semibold text-slate-100">
          Current standings
        </h2>
        <p className="mt-1 text-xs text-slate-500">
          Finalized games only. Ranking: points, wins, goal differential,
          goals for, then team name.
        </p>
      </div>

      {rows.length === 0 ? (
        <div className="p-5 text-sm text-slate-400">
          No tournament games are available for standings yet.
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-slate-950/80 text-left text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-4 py-3">Rank</th>
                <th className="px-4 py-3">Team</th>
                <th className="px-4 py-3 text-center">GP</th>
                <th className="px-4 py-3 text-center">W</th>
                <th className="px-4 py-3 text-center">L</th>
                <th className="px-4 py-3 text-center">T</th>
                <th className="px-4 py-3 text-center">GF</th>
                <th className="px-4 py-3 text-center">GA</th>
                <th className="px-4 py-3 text-center">GD</th>
                <th className="px-4 py-3 text-center">PTS</th>
              </tr>
            </thead>

            <tbody>
              {rows.map((row) => (
                <tr
                  key={row.teamId}
                  data-testid={`standings-row-${row.teamId}`}
                  className="border-t border-slate-900 text-slate-200"
                >
                  <td className="px-4 py-3 font-bold">
                    {row.rank}
                  </td>
                  <td className="px-4 py-3 font-semibold">
                    {row.teamName}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {row.gamesPlayed}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {row.wins}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {row.losses}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {row.ties}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {row.goalsFor}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {row.goalsAgainst}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {row.goalDifferential}
                  </td>
                  <td className="px-4 py-3 text-center font-bold">
                    {row.points}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
EOF

cat > "$PAGE" <<'EOF'
import { TournamentStandingsTable } from "../../../components/tournament/TournamentStandingsTable";

export default function TournamentStandingsPage() {
  return (
    <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
      <div className="mb-6">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          SportsOS Tournament Operations
        </div>

        <h1 className="mt-2 text-3xl font-bold text-slate-100">
          Tournament Standings
        </h1>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Standings are calculated from authoritative SportsOS game results.
          Games that are not finalized do not affect the table.
        </p>
      </div>

      <TournamentStandingsTable />
    </main>
  );
}
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 8.2 standings API / UI integration", () => {
  it("exposes a tournament standings API route", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/standings/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain('fetch(`${API_BASE_URL}/games`');
    expect(route).toContain("buildTournamentStandings");
  });

  it("keeps standings calculation in the shared 8.1 engine", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/standings/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain(
      'from "../../../../lib/tournament-standings"',
    );
  });

  it("renders the tournament standings table", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentStandingsTable.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="tournament-standings-table"',
    );
    expect(component).toContain("gamesPlayed");
    expect(component).toContain("goalDifferential");
    expect(component).toContain("points");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 8.2 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - GET /api/tournament/standings"
echo "  - tournament field derived from authoritative game data"
echo "  - standings calculated by shared 8.1 engine"
echo "  - /tournament/standings page"
echo "  - responsive standings table"
echo "  - Milestone 8.2 integration tests"
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
echo "  Milestone 8.3 - Tournament Pools / Divisions"
