#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="8.10-tournament-standings-bracket-operations-dashboard"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

STANDINGS_COMPONENT="apps/dashboard/components/tournament/TournamentStandingsTable.tsx"
BRACKET_COMPONENT="apps/dashboard/components/tournament/TournamentBracketView.tsx"
OPS_PAGE="apps/dashboard/app/tournament/operations/page.tsx"
OPS_COMPONENT="apps/dashboard/components/tournament/TournamentCompetitionOperationsDashboard.tsx"
OPS_LIB="apps/dashboard/lib/tournament-competition-operations.ts"
OPS_TEST="apps/dashboard/test/tournament-competition-operations-8.10.test.ts"

for file in \
  "$STANDINGS_COMPONENT" \
  "$BRACKET_COMPONENT"
do
  [[ -f "$file" ]] || {
    echo "ERROR: required prerequisite missing: $file" >&2
    exit 1
  }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$OPS_PAGE")" \
  "$BACKUP_DIR/$(dirname "$OPS_COMPONENT")" \
  "$BACKUP_DIR/$(dirname "$OPS_LIB")" \
  "$BACKUP_DIR/$(dirname "$OPS_TEST")" \
  "$(dirname "$OPS_PAGE")" \
  "$(dirname "$OPS_COMPONENT")"

for file in \
  "$OPS_PAGE" \
  "$OPS_COMPONENT" \
  "$OPS_LIB" \
  "$OPS_TEST"
do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$OPS_LIB" <<'EOF'
export type TournamentCompetitionStage =
  | "NOT_STARTED"
  | "POOL_PLAY"
  | "BRACKET_READY"
  | "BRACKET_ACTIVE"
  | "COMPLETE";

export type TournamentCompetitionOperationsInput = {
  totalTeams: number;
  finalizedGames: number;
  scheduledGames: number;
  seededTeams: number;
  resolvedBracketMatchups: number;
  totalBracketMatchups: number;
  championResolved: boolean;
};

export type TournamentCompetitionOperationsSummary = {
  stage: TournamentCompetitionStage;
  progressPercent: number;
  alerts: string[];
};

export function buildTournamentCompetitionOperationsSummary(
  input: TournamentCompetitionOperationsInput,
): TournamentCompetitionOperationsSummary {
  const alerts: string[] = [];

  if (input.totalTeams === 0) {
    alerts.push("No tournament teams are available.");
  }

  if (input.scheduledGames === 0) {
    alerts.push("No tournament games are scheduled.");
  }

  if (
    input.seededTeams > 0 &&
    input.seededTeams < input.totalTeams
  ) {
    alerts.push("Bracket seeding is incomplete.");
  }

  if (
    input.totalBracketMatchups > 0 &&
    input.resolvedBracketMatchups <
      input.totalBracketMatchups &&
    input.finalizedGames > 0
  ) {
    alerts.push("Bracket progression is still active.");
  }

  let stage: TournamentCompetitionStage =
    "NOT_STARTED";

  if (input.championResolved) {
    stage = "COMPLETE";
  } else if (
    input.totalBracketMatchups > 0 &&
    input.resolvedBracketMatchups > 0
  ) {
    stage = "BRACKET_ACTIVE";
  } else if (
    input.seededTeams > 0 &&
    input.seededTeams === input.totalTeams
  ) {
    stage = "BRACKET_READY";
  } else if (input.finalizedGames > 0) {
    stage = "POOL_PLAY";
  }

  const gameProgress =
    input.scheduledGames > 0
      ? Math.min(
          1,
          input.finalizedGames / input.scheduledGames,
        )
      : 0;

  const bracketProgress =
    input.totalBracketMatchups > 0
      ? Math.min(
          1,
          input.resolvedBracketMatchups /
            input.totalBracketMatchups,
        )
      : 0;

  const progressPercent = input.championResolved
    ? 100
    : Math.round(
        Math.max(gameProgress, bracketProgress) * 100,
      );

  return {
    stage,
    progressPercent,
    alerts,
  };
}
EOF

cat > "$OPS_COMPONENT" <<'EOF'
"use client";

import { useEffect, useMemo, useState } from "react";
import {
  buildTournamentCompetitionOperationsSummary,
} from "../../lib/tournament-competition-operations";
import type {
  TournamentStandingRow,
} from "../../lib/tournament-standings";
import type {
  TournamentBracketTree,
} from "../../lib/tournament-bracket-rounds";

type StandingsPayload = {
  teams?: unknown[];
  games?: Array<{
    status?: string;
  }>;
  standings?: TournamentStandingRow[];
};

type BracketPayload = {
  tree?: TournamentBracketTree;
};

function isFinalStatus(status: string | undefined) {
  const normalized = (status ?? "").trim().toUpperCase();

  return (
    normalized === "FINAL" ||
    normalized === "COMPLETE" ||
    normalized === "COMPLETED"
  );
}

export function TournamentCompetitionOperationsDashboard() {
  const [standings, setStandings] =
    useState<StandingsPayload | null>(null);
  const [bracket, setBracket] =
    useState<BracketPayload | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    const load = async () => {
      try {
        const [standingsResponse, bracketResponse] =
          await Promise.all([
            fetch("/api/tournament/standings", {
              cache: "no-store",
            }),
            fetch("/api/tournament/bracket", {
              cache: "no-store",
            }),
          ]);

        if (!standingsResponse.ok) {
          throw new Error(
            "Unable to load tournament standings.",
          );
        }

        if (!bracketResponse.ok) {
          throw new Error(
            "Unable to load tournament bracket.",
          );
        }

        const standingsPayload =
          (await standingsResponse.json()) as StandingsPayload;

        const bracketPayload =
          (await bracketResponse.json()) as BracketPayload;

        if (active) {
          setStandings(standingsPayload);
          setBracket(bracketPayload);
        }
      } catch (cause) {
        if (active) {
          setError(
            cause instanceof Error
              ? cause.message
              : "Unable to load tournament operations.",
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

  const summary = useMemo(() => {
    const games = standings?.games ?? [];
    const tree = bracket?.tree;

    const totalBracketMatchups =
      tree?.rounds.reduce(
        (total, round) => total + round.matchups.length,
        0,
      ) ?? 0;

    const resolvedBracketMatchups =
      tree?.rounds.reduce(
        (total, round) =>
          total +
          round.matchups.filter(
            (matchup) =>
              matchup.bye ||
              Boolean(
                matchup.homeSeed &&
                  matchup.awaySeed,
              ),
          ).length,
        0,
      ) ?? 0;

    return buildTournamentCompetitionOperationsSummary({
      totalTeams: standings?.teams?.length ?? 0,
      finalizedGames: games.filter((game) =>
        isFinalStatus(game.status),
      ).length,
      scheduledGames: games.length,
      seededTeams:
        standings?.standings?.length ?? 0,
      resolvedBracketMatchups,
      totalBracketMatchups,
      championResolved: Boolean(tree?.champion),
    });
  }, [bracket, standings]);

  if (loading) {
    return (
      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5 text-sm text-slate-400">
        Loading tournament competition operations...
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
      data-testid="tournament-competition-operations-dashboard"
      className="space-y-5"
    >
      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
              Competition stage
            </div>

            <div className="mt-1 text-2xl font-bold text-slate-100">
              {summary.stage.replaceAll("_", " ")}
            </div>
          </div>

          <div className="text-right">
            <div className="text-3xl font-bold text-slate-100">
              {summary.progressPercent}%
            </div>
            <div className="text-xs text-slate-500">
              tournament progress
            </div>
          </div>
        </div>

        <div className="mt-4 h-2 overflow-hidden rounded-full bg-slate-900">
          <div
            className="h-full bg-slate-400 transition-all"
            style={{
              width: `${summary.progressPercent}%`,
            }}
          />
        </div>

        {summary.alerts.length > 0 ? (
          <div className="mt-4 grid gap-2 md:grid-cols-2">
            {summary.alerts.map((alert) => (
              <div
                key={alert}
                className="rounded-lg border border-amber-900/50 bg-amber-950/20 px-3 py-2 text-xs text-amber-200"
              >
                {alert}
              </div>
            ))}
          </div>
        ) : null}
      </div>

      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Teams
          </div>
          <div className="mt-2 text-2xl font-bold text-slate-100">
            {standings?.teams?.length ?? 0}
          </div>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Scheduled games
          </div>
          <div className="mt-2 text-2xl font-bold text-slate-100">
            {standings?.games?.length ?? 0}
          </div>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Seeded teams
          </div>
          <div className="mt-2 text-2xl font-bold text-slate-100">
            {standings?.standings?.length ?? 0}
          </div>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Champion
          </div>
          <div className="mt-2 truncate text-lg font-bold text-slate-100">
            {bracket?.tree?.champion?.teamName ?? "TBD"}
          </div>
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <a
          href="/tournament/standings"
          className="rounded-xl border border-slate-800 bg-slate-950/40 p-5 transition hover:border-slate-700"
        >
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            Standings
          </div>
          <div className="mt-2 text-lg font-bold text-slate-100">
            Open tournament standings
          </div>
        </a>

        <a
          href="/tournament/bracket"
          className="rounded-xl border border-slate-800 bg-slate-950/40 p-5 transition hover:border-slate-700"
        >
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            Bracket
          </div>
          <div className="mt-2 text-lg font-bold text-slate-100">
            Open tournament bracket
          </div>
        </a>
      </div>
    </section>
  );
}
EOF

cat > "$OPS_PAGE" <<'EOF'
import { TournamentCompetitionOperationsDashboard } from "../../../components/tournament/TournamentCompetitionOperationsDashboard";

export default function TournamentCompetitionOperationsPage() {
  return (
    <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
      <div className="mb-6">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          SportsOS Tournament Operations
        </div>

        <h1 className="mt-2 text-3xl font-bold text-slate-100">
          Tournament Competition Dashboard
        </h1>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Monitor standings, seeding, bracket progression, and tournament
          completion from one operational surface.
        </p>
      </div>

      <TournamentCompetitionOperationsDashboard />
    </main>
  );
}
EOF

cat > "$OPS_TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";
import {
  buildTournamentCompetitionOperationsSummary,
} from "../lib/tournament-competition-operations";

describe("Milestone 8.10 tournament standings / bracket operations dashboard", () => {
  it("reports tournament completion when a champion resolves", () => {
    const summary =
      buildTournamentCompetitionOperationsSummary({
        totalTeams: 8,
        finalizedGames: 12,
        scheduledGames: 12,
        seededTeams: 8,
        resolvedBracketMatchups: 7,
        totalBracketMatchups: 7,
        championResolved: true,
      });

    expect(summary.stage).toBe("COMPLETE");
    expect(summary.progressPercent).toBe(100);
  });

  it("reports active bracket progression", () => {
    const summary =
      buildTournamentCompetitionOperationsSummary({
        totalTeams: 8,
        finalizedGames: 10,
        scheduledGames: 12,
        seededTeams: 8,
        resolvedBracketMatchups: 4,
        totalBracketMatchups: 7,
        championResolved: false,
      });

    expect(summary.stage).toBe("BRACKET_ACTIVE");
  });

  it("renders the operations dashboard", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentCompetitionOperationsDashboard.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="tournament-competition-operations-dashboard"',
    );
    expect(component).toContain("/tournament/standings");
    expect(component).toContain("/tournament/bracket");
  });

  it("provides the tournament competition dashboard page", () => {
    const page = fs.readFileSync(
      new URL(
        "../app/tournament/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Tournament Competition Dashboard",
    );
    expect(page).toContain(
      "TournamentCompetitionOperationsDashboard",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 8.10 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - /tournament/operations"
echo "  - unified competition stage"
echo "  - tournament progress percentage"
echo "  - standings / seeding / bracket summary"
echo "  - champion state"
echo "  - operational alerts"
echo "  - links to standings and bracket workflows"
echo "  - Milestone 8.10 tests"
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
echo "After full green:"
echo "  Milestone 8 complete"
echo "  Next: Milestone 9 - Streaming / Broadcast Integration"
