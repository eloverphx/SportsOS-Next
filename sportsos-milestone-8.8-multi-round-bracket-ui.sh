#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="8.8-multi-round-bracket-ui"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

SEEDING_LIB="apps/dashboard/lib/tournament-bracket-seeding.ts"
ADVANCE_LIB="apps/dashboard/lib/tournament-bracket-advancement.ts"
ROUNDS_LIB="apps/dashboard/lib/tournament-bracket-rounds.ts"
BRACKET_ROUTE="apps/dashboard/app/api/tournament/bracket/route.ts"
BRACKET_COMPONENT="apps/dashboard/components/tournament/TournamentBracketView.tsx"
TEST="apps/dashboard/test/tournament-bracket-ui-8.8.test.ts"

for file in \
  "$SEEDING_LIB" \
  "$ADVANCE_LIB" \
  "$ROUNDS_LIB" \
  "$BRACKET_ROUTE" \
  "$BRACKET_COMPONENT"
do
  [[ -f "$file" ]] || {
    echo "ERROR: required prerequisite missing: $file" >&2
    exit 1
  }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$BRACKET_ROUTE")" \
  "$BACKUP_DIR/$(dirname "$BRACKET_COMPONENT")" \
  "$BACKUP_DIR/$(dirname "$TEST")"

for file in "$BRACKET_ROUTE" "$BRACKET_COMPONENT" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$BRACKET_ROUTE" <<'EOF'
import { NextResponse } from "next/server";
import {
  seedBracket,
} from "../../../../lib/tournament-bracket-seeding";
import {
  buildTournamentBracketTree,
} from "../../../../lib/tournament-bracket-rounds";
import type {
  BracketMatchupResult,
} from "../../../../lib/tournament-bracket-advancement";
import type {
  TournamentStandingRow,
} from "../../../../lib/tournament-standings";

const SITE_BASE_URL =
  process.env.SPORTSOS_DASHBOARD_URL ??
  process.env.NEXT_PUBLIC_SITE_URL ??
  "http://localhost:4000";

type StandingsPayload = {
  standings?: TournamentStandingRow[];
  error?: string;
};

type UnknownRecord = Record<string, unknown>;

function record(value: unknown): UnknownRecord | null {
  return value && typeof value === "object"
    ? (value as UnknownRecord)
    : null;
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function numberValue(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : 0;
}

function normalizeBracketResults(
  payload: unknown,
): BracketMatchupResult[] {
  const root = record(payload);

  if (!root) {
    return [];
  }

  const candidates = Array.isArray(root.results)
    ? root.results
    : Array.isArray(record(root.data)?.results)
      ? (record(root.data)?.results as unknown[])
      : [];

  return candidates
    .map((value) => {
      const item = record(value);

      if (!item) {
        return null;
      }

      const matchupId =
        stringValue(item.matchupId) ||
        stringValue(item.id);

      if (!matchupId) {
        return null;
      }

      return {
        matchupId,
        homeScore: numberValue(item.homeScore),
        awayScore: numberValue(item.awayScore),
        status: stringValue(item.status),
      };
    })
    .filter(
      (
        value,
      ): value is BracketMatchupResult =>
        value !== null,
    );
}

export async function GET() {
  const standingsResponse = await fetch(
    `${SITE_BASE_URL}/api/tournament/standings`,
    {
      cache: "no-store",
    },
  ).catch(() => null);

  if (!standingsResponse || !standingsResponse.ok) {
    return NextResponse.json(
      {
        error: "Unable to load tournament standings for bracket seeding.",
      },
      {
        status: 502,
      },
    );
  }

  const standingsPayload =
    (await standingsResponse.json()) as StandingsPayload;

  const standings = standingsPayload.standings ?? [];
  const seeded = seedBracket(standings);

  const resultsResponse = await fetch(
    `${SITE_BASE_URL}/api/tournament/bracket/results`,
    {
      cache: "no-store",
    },
  ).catch(() => null);

  let results: BracketMatchupResult[] = [];

  if (resultsResponse?.ok) {
    results = normalizeBracketResults(
      await resultsResponse.json(),
    );
  }

  const tree = buildTournamentBracketTree(
    seeded,
    results,
  );

  return NextResponse.json({
    standings,
    bracket: seeded,
    results,
    tree,
  });
}
EOF

cat > "$BRACKET_COMPONENT" <<'EOF'
"use client";

import { useEffect, useState } from "react";
import type {
  TournamentBracketTree,
} from "../../lib/tournament-bracket-rounds";

type BracketResponse = {
  tree?: TournamentBracketTree;
  error?: string;
};

function TeamSlot({
  seed,
  name,
  emptyLabel,
}: {
  seed: number | null;
  name: string | null;
  emptyLabel: string;
}) {
  return (
    <div className="flex items-center gap-3 rounded-lg border border-slate-800 bg-slate-950/60 px-3 py-2">
      <div className="w-8 text-center text-xs font-bold text-slate-500">
        {seed ?? "—"}
      </div>

      <div className="min-w-0 flex-1 truncate text-sm font-semibold text-slate-200">
        {name ?? emptyLabel}
      </div>
    </div>
  );
}

export function TournamentBracketView() {
  const [tree, setTree] =
    useState<TournamentBracketTree | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    const load = async () => {
      try {
        const response = await fetch("/api/tournament/bracket", {
          cache: "no-store",
        });

        const payload = (await response.json()) as BracketResponse;

        if (!response.ok) {
          throw new Error(
            payload.error ?? "Unable to load tournament bracket.",
          );
        }

        if (active) {
          setTree(payload.tree ?? null);
        }
      } catch (cause) {
        if (active) {
          setError(
            cause instanceof Error
              ? cause.message
              : "Unable to load tournament bracket.",
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
        Loading tournament bracket...
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

  if (!tree || tree.fieldSize === 0) {
    return (
      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5 text-sm text-slate-400">
        No seeded teams are available yet.
      </div>
    );
  }

  return (
    <section
      data-testid="tournament-bracket-view"
      className="space-y-5"
    >
      {tree.champion ? (
        <div
          data-testid="tournament-bracket-champion"
          className="rounded-xl border border-emerald-900/60 bg-emerald-950/20 p-5"
        >
          <div className="text-xs font-semibold uppercase tracking-wide text-emerald-400">
            Tournament champion
          </div>

          <div className="mt-2 text-2xl font-bold text-slate-100">
            #{tree.champion.seed} {tree.champion.teamName}
          </div>
        </div>
      ) : null}

      <div className="overflow-x-auto pb-2">
        <div className="flex min-w-max gap-5">
          {tree.rounds.map((round) => (
            <section
              key={round.round}
              data-testid={`tournament-bracket-round-${round.round}`}
              className="w-[320px] shrink-0 rounded-xl border border-slate-800 bg-slate-950/40 p-4"
            >
              <div className="mb-4">
                <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Round {round.round}
                </div>
                <h2 className="mt-1 text-lg font-bold text-slate-100">
                  {round.name}
                </h2>
              </div>

              <div className="space-y-4">
                {round.matchups.map((matchup) => (
                  <div
                    key={matchup.id}
                    data-testid={`bracket-matchup-${matchup.id}`}
                    className="rounded-xl border border-slate-800 bg-slate-950/50 p-3"
                  >
                    <div className="mb-3 flex items-center justify-between gap-2">
                      <span className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                        Matchup {matchup.slot}
                      </span>

                      {matchup.bye ? (
                        <span className="rounded-full border border-emerald-900/60 bg-emerald-950/20 px-2 py-1 text-[10px] font-semibold uppercase tracking-wide text-emerald-300">
                          Bye
                        </span>
                      ) : null}
                    </div>

                    <div className="space-y-2">
                      <TeamSlot
                        seed={matchup.homeSeed?.seed ?? null}
                        name={matchup.homeSeed?.teamName ?? null}
                        emptyLabel="TBD"
                      />

                      <TeamSlot
                        seed={matchup.awaySeed?.seed ?? null}
                        name={matchup.awaySeed?.teamName ?? null}
                        emptyLabel={
                          matchup.bye ? "BYE" : "TBD"
                        }
                      />
                    </div>
                  </div>
                ))}
              </div>
            </section>
          ))}
        </div>
      </div>
    </section>
  );
}
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 8.8 multi-round bracket UI", () => {
  it("uses the multi-round bracket tree", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/bracket/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain("buildTournamentBracketTree");
    expect(route).toContain("tree");
  });

  it("renders all rounds from the bracket tree", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentBracketView.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain("tree.rounds.map");
    expect(component).toContain(
      "tournament-bracket-round-",
    );
    expect(component).toContain("TBD");
    expect(component).toContain("BYE");
  });

  it("renders a champion banner when the tree resolves one", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentBracketView.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain("tree.champion");
    expect(component).toContain(
      'data-testid="tournament-bracket-champion"',
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 8.8 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - multi-round bracket API payload"
echo "  - horizontal multi-round bracket UI"
echo "  - TBD slots for unresolved teams"
echo "  - BYE visibility"
echo "  - champion banner"
echo "  - Milestone 8.8 tests"
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
echo "  Milestone 8.9 - Bracket Result Integration / Persistence"
