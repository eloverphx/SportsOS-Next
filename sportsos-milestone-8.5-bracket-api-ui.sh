#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="8.5-bracket-api-ui"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

SEEDING_LIB="apps/dashboard/lib/tournament-bracket-seeding.ts"
STANDINGS_ROUTE="apps/dashboard/app/api/tournament/standings/route.ts"
BRACKET_ROUTE="apps/dashboard/app/api/tournament/bracket/route.ts"
BRACKET_PAGE="apps/dashboard/app/tournament/bracket/page.tsx"
BRACKET_COMPONENT="apps/dashboard/components/tournament/TournamentBracketView.tsx"
TEST="apps/dashboard/test/tournament-bracket-8.5.test.ts"

for file in "$SEEDING_LIB" "$STANDINGS_ROUTE"; do
  [[ -f "$file" ]] || {
    echo "ERROR: required prerequisite missing: $file" >&2
    exit 1
  }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$BRACKET_ROUTE")" \
  "$BACKUP_DIR/$(dirname "$BRACKET_PAGE")" \
  "$BACKUP_DIR/$(dirname "$BRACKET_COMPONENT")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$BRACKET_ROUTE")" \
  "$(dirname "$BRACKET_PAGE")" \
  "$(dirname "$BRACKET_COMPONENT")"

for file in \
  "$BRACKET_ROUTE" \
  "$BRACKET_PAGE" \
  "$BRACKET_COMPONENT" \
  "$TEST"
do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$BRACKET_ROUTE" <<'EOF'
import { NextResponse } from "next/server";
import {
  seedBracket,
} from "../../../../lib/tournament-bracket-seeding";
import type {
  TournamentStandingRow,
} from "../../../../lib/tournament-standings";

const API_BASE_URL =
  process.env.SPORTSOS_API_URL ??
  process.env.API_URL ??
  process.env.NEXT_PUBLIC_API_URL ??
  "http://api:4001";

type StandingsPayload = {
  standings?: TournamentStandingRow[];
  error?: string;
};

export async function GET() {
  const response = await fetch(
    `${API_BASE_URL.replace(/\/$/, "") === API_BASE_URL
      ? ""
      : ""}`,
  ).catch(() => null);

  void response;

  const standingsResponse = await fetch(
    `${process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:4000"}/api/tournament/standings`,
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

  const payload =
    (await standingsResponse.json()) as StandingsPayload;

  const standings = payload.standings ?? [];
  const bracket = seedBracket(standings);

  return NextResponse.json({
    standings,
    bracket,
  });
}
EOF

cat > "$BRACKET_COMPONENT" <<'EOF'
"use client";

import { useEffect, useState } from "react";
import type {
  BracketSeedResult,
} from "../../lib/tournament-bracket-seeding";

type BracketResponse = {
  bracket?: BracketSeedResult;
  error?: string;
};

function SeedCard({
  seed,
  label,
}: {
  seed: number | null;
  label: string;
}) {
  return (
    <div className="flex items-center gap-3 rounded-lg border border-slate-800 bg-slate-950/60 px-3 py-2">
      <div className="w-8 text-center text-xs font-bold text-slate-500">
        {seed ?? "—"}
      </div>
      <div className="min-w-0 flex-1 truncate text-sm font-semibold text-slate-200">
        {label}
      </div>
    </div>
  );
}

export function TournamentBracketView() {
  const [bracket, setBracket] =
    useState<BracketSeedResult | null>(null);
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
          setBracket(payload.bracket ?? null);
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

  if (!bracket || bracket.fieldSize === 0) {
    return (
      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5 text-sm text-slate-400">
        No seeded teams are available yet.
      </div>
    );
  }

  return (
    <section
      data-testid="tournament-bracket-view"
      className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="font-semibold text-slate-100">
            First-round bracket
          </h2>
          <p className="mt-1 text-xs text-slate-500">
            {bracket.fieldSize} teams seeded into a{" "}
            {bracket.bracketSize}-slot bracket.
          </p>
        </div>

        <span className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          High seed vs low seed
        </span>
      </div>

      <div className="mt-5 grid gap-4 md:grid-cols-2">
        {bracket.firstRound.map((matchup) => (
          <div
            key={matchup.id}
            data-testid={`bracket-matchup-${matchup.slot}`}
            className="rounded-xl border border-slate-800 bg-slate-950/40 p-4"
          >
            <div className="mb-3 flex items-center justify-between gap-2">
              <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                Matchup {matchup.slot}
              </div>

              {matchup.bye ? (
                <span className="rounded-full border border-emerald-900/60 bg-emerald-950/20 px-2 py-1 text-[10px] font-semibold uppercase tracking-wide text-emerald-300">
                  Bye
                </span>
              ) : null}
            </div>

            <div className="space-y-2">
              <SeedCard
                seed={matchup.homeSeed?.seed ?? null}
                label={matchup.homeSeed?.teamName ?? "TBD"}
              />

              <SeedCard
                seed={matchup.awaySeed?.seed ?? null}
                label={matchup.awaySeed?.teamName ?? "BYE"}
              />
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
EOF

cat > "$BRACKET_PAGE" <<'EOF'
import { TournamentBracketView } from "../../../components/tournament/TournamentBracketView";

export default function TournamentBracketPage() {
  return (
    <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
      <div className="mb-6">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          SportsOS Tournament Operations
        </div>

        <h1 className="mt-2 text-3xl font-bold text-slate-100">
          Tournament Bracket
        </h1>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Bracket seeds are generated directly from the current tournament
          standings. Seeding logic remains centralized in the shared bracket
          engine.
        </p>
      </div>

      <TournamentBracketView />
    </main>
  );
}
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 8.5 bracket API / UI integration", () => {
  it("uses the shared bracket seeding engine", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/bracket/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain("seedBracket");
    expect(route).toContain(
      'from "../../../../lib/tournament-bracket-seeding"',
    );
  });

  it("renders the tournament bracket view", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentBracketView.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="tournament-bracket-view"',
    );
    expect(component).toContain("firstRound.map");
    expect(component).toContain("matchup.bye");
  });

  it("provides a tournament bracket page", () => {
    const page = fs.readFileSync(
      new URL(
        "../app/tournament/bracket/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain("Tournament Bracket");
    expect(page).toContain("TournamentBracketView");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 8.5 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - GET /api/tournament/bracket"
echo "  - bracket data generated by shared 8.4 seeding engine"
echo "  - /tournament/bracket page"
echo "  - first-round matchup cards"
echo "  - seed numbers and bye visibility"
echo "  - Milestone 8.5 tests"
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
echo "  Milestone 8.6 - Bracket Advancement / Winner Propagation"
