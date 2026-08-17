#!/usr/bin/env bash
set -euo pipefail

MILESTONE="7.1"
ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

echo "============================================================"
echo " SportsOS-Next Milestone ${MILESTONE}"
echo " Tournament Game Operations Workspace"
echo "============================================================"
echo "Root:   $ROOT"
echo "Backup: $BACKUP_DIR"
echo

require_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "ERROR: required file not found: $file" >&2
    exit 1
  fi
}

require_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "ERROR: required directory not found: $dir" >&2
    exit 1
  fi
}

require_grep() {
  local pattern="$1"
  local file="$2"
  if ! grep -Eq "$pattern" "$file"; then
    echo "ERROR: prerequisite check failed." >&2
    echo "Expected pattern: $pattern" >&2
    echo "In file:          $file" >&2
    exit 1
  fi
}

require_dir "apps/dashboard"
require_file "package.json"
require_file "apps/dashboard/package.json"
require_grep '"next"' "apps/dashboard/package.json"

mkdir -p "$BACKUP_DIR"

backup_if_exists() {
  local file="$1"
  if [[ -e "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
  fi
}

FILES=(
  "apps/dashboard/app/tournament/game-operations/page.tsx"
  "apps/dashboard/app/api/tournament/game-operations/route.ts"
  "apps/dashboard/app/api/tournament/game-operations/[gameId]/route.ts"
  "apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx"
  "apps/dashboard/lib/tournament-game-operations.ts"
  "apps/dashboard/test/tournament-game-operations-7.1.test.ts"
  "apps/dashboard/e2e/tournament-game-operations.spec.ts"
)

for file in "${FILES[@]}"; do
  backup_if_exists "$file"
done

mkdir -p \
  "apps/dashboard/app/tournament/game-operations" \
  "apps/dashboard/app/api/tournament/game-operations" \
  "apps/dashboard/app/api/tournament/game-operations/[gameId]" \
  "apps/dashboard/components/tournament" \
  "apps/dashboard/lib" \
  "apps/dashboard/test" \
  "apps/dashboard/e2e"

cat > "apps/dashboard/lib/tournament-game-operations.ts" <<'EOF'
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
EOF

cat > "apps/dashboard/app/api/tournament/game-operations/route.ts" <<'EOF'
import { NextResponse } from "next/server";

function apiBaseUrl(): string {
  return (
    process.env.SPORTSOS_API_URL ??
    process.env.API_URL ??
    process.env.NEXT_PUBLIC_API_URL ??
    "http://api:4001"
  ).replace(/\/+$/, "");
}

export async function GET() {
  const upstream = new URL("/games", apiBaseUrl());
  upstream.searchParams.set("limit", "100");

  try {
    const response = await fetch(upstream, {
      cache: "no-store",
      headers: {
        accept: "application/json",
      },
    });

    const text = await response.text();

    return new NextResponse(text, {
      status: response.status,
      headers: {
        "content-type":
          response.headers.get("content-type") ?? "application/json",
      },
    });
  } catch (error) {
    return NextResponse.json(
      {
        success: false,
        error: "GAME_OPERATIONS_UPSTREAM_UNAVAILABLE",
        message:
          error instanceof Error
            ? error.message
            : "Unable to reach the SportsOS API.",
      },
      { status: 502 },
    );
  }
}
EOF

cat > "apps/dashboard/app/api/tournament/game-operations/[gameId]/route.ts" <<'EOF'
import { NextResponse } from "next/server";

function apiBaseUrl(): string {
  return (
    process.env.SPORTSOS_API_URL ??
    process.env.API_URL ??
    process.env.NEXT_PUBLIC_API_URL ??
    "http://api:4001"
  ).replace(/\/+$/, "");
}

export async function GET(
  _request: Request,
  context: { params: Promise<{ gameId: string }> },
) {
  const { gameId } = await context.params;
  const normalizedGameId = gameId.trim();

  if (!normalizedGameId) {
    return NextResponse.json(
      {
        success: false,
        error: "INVALID_GAME_ID",
      },
      { status: 400 },
    );
  }

  const upstream = new URL(
    `/games/${encodeURIComponent(normalizedGameId)}`,
    apiBaseUrl(),
  );

  try {
    const response = await fetch(upstream, {
      cache: "no-store",
      headers: {
        accept: "application/json",
      },
    });

    const text = await response.text();

    return new NextResponse(text, {
      status: response.status,
      headers: {
        "content-type":
          response.headers.get("content-type") ?? "application/json",
      },
    });
  } catch (error) {
    return NextResponse.json(
      {
        success: false,
        error: "GAME_OPERATIONS_UPSTREAM_UNAVAILABLE",
        message:
          error instanceof Error
            ? error.message
            : "Unable to reach the SportsOS API.",
      },
      { status: 502 },
    );
  }
}
EOF

cat > "apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx" <<'EOF'
"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  extractTournamentGame,
  extractTournamentGameList,
  readinessCount,
  type TournamentGameOperationsGame,
} from "@/lib/tournament-game-operations";

type LoadState = "idle" | "loading" | "ready" | "error";

function formatStart(value: string | null): string {
  if (!value) return "Not scheduled";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return parsed.toLocaleString();
}

function StatusBadge({ value }: { value: string }) {
  return (
    <span className="rounded-full border border-slate-700 bg-slate-900 px-2.5 py-1 text-xs font-semibold uppercase tracking-wide text-slate-200">
      {value}
    </span>
  );
}

function ReadinessRow({
  label,
  ready,
}: {
  label: string;
  ready: boolean;
}) {
  return (
    <div className="flex items-center justify-between rounded-lg border border-slate-800 bg-slate-950/60 px-3 py-2">
      <span className="text-sm text-slate-300">{label}</span>
      <span
        className={
          ready
            ? "text-sm font-semibold text-emerald-400"
            : "text-sm font-semibold text-amber-400"
        }
      >
        {ready ? "Ready" : "Needs attention"}
      </span>
    </div>
  );
}

function FutureAction({
  title,
  milestone,
  description,
}: {
  title: string;
  milestone: string;
  description: string;
}) {
  return (
    <div className="rounded-xl border border-slate-800 bg-slate-950/50 p-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="font-semibold text-slate-100">{title}</h3>
          <p className="mt-1 text-sm text-slate-400">{description}</p>
        </div>
        <span className="whitespace-nowrap rounded-full border border-slate-700 px-2 py-1 text-xs text-slate-400">
          {milestone}
        </span>
      </div>
      <button
        type="button"
        disabled
        className="mt-4 w-full cursor-not-allowed rounded-lg border border-slate-800 bg-slate-900 px-3 py-2 text-sm font-semibold text-slate-500"
      >
        Not enabled in 7.1
      </button>
    </div>
  );
}

export function TournamentGameOperationsWorkspace() {
  const [games, setGames] = useState<TournamentGameOperationsGame[]>([]);
  const [selectedGame, setSelectedGame] =
    useState<TournamentGameOperationsGame | null>(null);
  const [gameId, setGameId] = useState("");
  const [listState, setListState] = useState<LoadState>("idle");
  const [gameState, setGameState] = useState<LoadState>("idle");
  const [message, setMessage] = useState<string | null>(null);

  const loadGame = useCallback(async (requestedGameId: string) => {
    const normalized = requestedGameId.trim();
    if (!normalized) return;

    setGameState("loading");
    setMessage(null);

    try {
      const response = await fetch(
        `/api/tournament/game-operations/${encodeURIComponent(normalized)}`,
        { cache: "no-store" },
      );

      if (!response.ok) {
        throw new Error(`Game request failed with status ${response.status}.`);
      }

      const payload: unknown = await response.json();
      const game = extractTournamentGame(payload);

      if (!game) {
        throw new Error("The API response did not contain a recognizable game.");
      }

      setSelectedGame(game);
      setGameId(game.id);
      setGameState("ready");

      const url = new URL(window.location.href);
      url.searchParams.set("gameId", game.id);
      window.history.replaceState({}, "", url);
    } catch (error) {
      setSelectedGame(null);
      setGameState("error");
      setMessage(
        error instanceof Error ? error.message : "Unable to load the game.",
      );
    }
  }, []);

  useEffect(() => {
    let active = true;

    async function loadGames() {
      setListState("loading");

      try {
        const response = await fetch("/api/tournament/game-operations", {
          cache: "no-store",
        });

        if (!response.ok) {
          throw new Error(
            `Scheduled game request failed with status ${response.status}.`,
          );
        }

        const payload: unknown = await response.json();
        const normalizedGames = extractTournamentGameList(payload);

        if (!active) return;

        setGames(normalizedGames);
        setListState("ready");

        const initialGameId = new URL(window.location.href).searchParams.get(
          "gameId",
        );

        if (initialGameId) {
          setGameId(initialGameId);
          void loadGame(initialGameId);
        }
      } catch (error) {
        if (!active) return;
        setListState("error");
        setMessage(
          error instanceof Error
            ? error.message
            : "Unable to load scheduled games.",
        );
      }
    }

    void loadGames();

    return () => {
      active = false;
    };
  }, [loadGame]);

  const selectedReadiness = useMemo(
    () => (selectedGame ? readinessCount(selectedGame) : null),
    [selectedGame],
  );

  return (
    <section className="space-y-6" data-testid="game-operations-workspace">
      <header className="space-y-2">
        <div className="flex flex-wrap items-center gap-3">
          <h1 className="text-3xl font-bold tracking-tight text-slate-100">
            Tournament Game Operations
          </h1>
          <StatusBadge value="Milestone 7.1" />
        </div>
        <p className="max-w-3xl text-sm text-slate-400">
          Select a tournament game and review the operational context that will
          drive pregame readiness, game start authorization, live scoring, and
          finalization in the remaining Milestone 7 work.
        </p>
      </header>

      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
        <label
          htmlFor="game-operations-select"
          className="text-sm font-semibold text-slate-200"
        >
          Scheduled game
        </label>

        <div className="mt-2 flex flex-col gap-2 lg:flex-row">
          <select
            id="game-operations-select"
            data-testid="game-operations-select"
            value={gameId}
            onChange={(event) => {
              const value = event.target.value;
              setGameId(value);
              if (value) void loadGame(value);
            }}
            className="min-h-10 flex-1 rounded-lg border border-slate-700 bg-slate-950 px-3 text-sm text-slate-100"
          >
            <option value="">
              {listState === "loading"
                ? "Loading scheduled games..."
                : "Select a game"}
            </option>
            {games.map((game) => (
              <option key={game.id} value={game.id}>
                {game.homeTeamName} vs {game.awayTeamName} —{" "}
                {formatStart(game.scheduledStart)}
              </option>
            ))}
          </select>

          <div className="flex min-w-0 flex-1 gap-2">
            <input
              aria-label="Game ID"
              data-testid="game-operations-game-id"
              value={gameId}
              onChange={(event) => setGameId(event.target.value)}
              placeholder="Or enter game ID"
              className="min-h-10 min-w-0 flex-1 rounded-lg border border-slate-700 bg-slate-950 px-3 text-sm text-slate-100"
            />
            <button
              type="button"
              data-testid="game-operations-load"
              disabled={!gameId.trim() || gameState === "loading"}
              onClick={() => void loadGame(gameId)}
              className="rounded-lg bg-slate-100 px-4 py-2 text-sm font-semibold text-slate-950 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {gameState === "loading" ? "Loading..." : "Load"}
            </button>
          </div>
        </div>

        {message ? (
          <p
            role="alert"
            className="mt-3 rounded-lg border border-amber-800/60 bg-amber-950/20 px-3 py-2 text-sm text-amber-300"
          >
            {message}
          </p>
        ) : null}
      </div>

      {!selectedGame ? (
        <div className="rounded-xl border border-dashed border-slate-700 p-8 text-center text-slate-400">
          Select a scheduled game to open its operations workspace.
        </div>
      ) : (
        <>
          <div className="grid gap-4 xl:grid-cols-3">
            <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5 xl:col-span-2">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                    Selected game
                  </p>
                  <h2
                    data-testid="game-operations-matchup"
                    className="mt-1 text-2xl font-bold text-slate-100"
                  >
                    {selectedGame.homeTeamName} vs{" "}
                    {selectedGame.awayTeamName}
                  </h2>
                </div>
                <StatusBadge value={selectedGame.status} />
              </div>

              <dl className="mt-5 grid gap-4 sm:grid-cols-2">
                <div>
                  <dt className="text-xs uppercase tracking-wide text-slate-500">
                    Game ID
                  </dt>
                  <dd className="mt-1 break-all text-sm text-slate-200">
                    {selectedGame.id}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs uppercase tracking-wide text-slate-500">
                    Scheduled start
                  </dt>
                  <dd className="mt-1 text-sm text-slate-200">
                    {formatStart(selectedGame.scheduledStart)}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs uppercase tracking-wide text-slate-500">
                    Venue
                  </dt>
                  <dd className="mt-1 text-sm text-slate-200">
                    {selectedGame.venueName ?? "Not assigned"}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs uppercase tracking-wide text-slate-500">
                    Rink
                  </dt>
                  <dd className="mt-1 text-sm text-slate-200">
                    {selectedGame.rinkName ?? "Not assigned"}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs uppercase tracking-wide text-slate-500">
                    Scoring status
                  </dt>
                  <dd className="mt-1 text-sm text-slate-200">
                    {selectedGame.scoringStatus}
                  </dd>
                </div>
              </dl>
            </div>

            <aside className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
              <div className="flex items-center justify-between gap-3">
                <h2 className="font-semibold text-slate-100">
                  Readiness summary
                </h2>
                <span
                  data-testid="game-operations-readiness-count"
                  className="text-sm font-semibold text-slate-300"
                >
                  {selectedReadiness?.passed}/{selectedReadiness?.total}
                </span>
              </div>

              <div className="mt-4 space-y-2">
                <ReadinessRow
                  label="Teams assigned"
                  ready={selectedGame.readiness.teamsAssigned}
                />
                <ReadinessRow
                  label="Rink assigned"
                  ready={selectedGame.readiness.rinkAssigned}
                />
                <ReadinessRow
                  label="Scheduled start assigned"
                  ready={selectedGame.readiness.scheduledStartAssigned}
                />
              </div>

              <p className="mt-4 text-xs leading-5 text-slate-500">
                Milestone 7.1 only reports context that can be derived from the
                selected game. Roster, scoreboard, operator, stream, check-in,
                officials, and authorization rules are added by later
                milestones.
              </p>
            </aside>
          </div>

          <div>
            <h2 className="text-lg font-semibold text-slate-100">
              Operator actions
            </h2>
            <p className="mt-1 text-sm text-slate-400">
              Action surfaces are visible now so the workspace structure is
              stable, but mutations remain disabled until their owning
              milestones implement authorization, validation, and auditing.
            </p>

            <div className="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
              <FutureAction
                title="Pregame readiness"
                milestone="7.2"
                description="Roster, scoreboard, scoring operator, stream, and required-condition checks."
              />
              <FutureAction
                title="Team check-in"
                milestone="7.3"
                description="Track home and away arrival and readiness."
              />
              <FutureAction
                title="Roster & officials"
                milestone="7.4–7.5"
                description="Lock active rosters and assign game officials."
              />
              <FutureAction
                title="Authorize game start"
                milestone="7.6"
                description="Gate transition to LIVE behind readiness or an audited override."
              />
            </div>
          </div>
        </>
      )}
    </section>
  );
}
EOF

cat > "apps/dashboard/app/tournament/game-operations/page.tsx" <<'EOF'
import { TournamentGameOperationsWorkspace } from "@/components/tournament/TournamentGameOperationsWorkspace";

export default function TournamentGameOperationsPage() {
  return (
    <main className="mx-auto w-full max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
      <TournamentGameOperationsWorkspace />
    </main>
  );
}
EOF

cat > "apps/dashboard/test/tournament-game-operations-7.1.test.ts" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  extractTournamentGame,
  extractTournamentGameList,
  normalizeTournamentGame,
  readinessCount,
} from "../lib/tournament-game-operations";

describe("Milestone 7.1 tournament game operations normalization", () => {
  it("normalizes a scheduled tournament game", () => {
    const game = normalizeTournamentGame({
      id: "game-701",
      homeTeam: { name: "Lakers" },
      awayTeam: { name: "Bears" },
      venue: { name: "Community Arena" },
      rink: { name: "Rink 1" },
      scheduledStart: "2026-08-11T18:00:00.000Z",
      status: "SCHEDULED",
    });

    expect(game).toEqual({
      id: "game-701",
      homeTeamName: "Lakers",
      awayTeamName: "Bears",
      venueName: "Community Arena",
      rinkName: "Rink 1",
      scheduledStart: "2026-08-11T18:00:00.000Z",
      status: "SCHEDULED",
      scoringStatus: "NOT_STARTED",
      readiness: {
        teamsAssigned: true,
        rinkAssigned: true,
        scheduledStartAssigned: true,
      },
    });
  });

  it("marks missing operational context as not ready", () => {
    const game = normalizeTournamentGame({
      gameId: 42,
      homeTeamName: "Lakers",
      status: "pregame",
    });

    expect(game).not.toBeNull();
    expect(game?.readiness).toEqual({
      teamsAssigned: false,
      rinkAssigned: false,
      scheduledStartAssigned: false,
    });
    expect(game ? readinessCount(game) : null).toEqual({
      passed: 0,
      total: 3,
    });
  });

  it("extracts list payloads and excludes canceled games", () => {
    const games = extractTournamentGameList({
      success: true,
      data: {
        games: [
          {
            id: "scheduled-1",
            homeTeamName: "A",
            awayTeamName: "B",
            rinkName: "1",
            scheduledStart: "2026-08-11T18:00:00Z",
            status: "SCHEDULED",
          },
          {
            id: "canceled-1",
            homeTeamName: "C",
            awayTeamName: "D",
            rinkName: "2",
            scheduledStart: "2026-08-11T19:00:00Z",
            status: "CANCELED",
          },
        ],
      },
    });

    expect(games.map((game) => game.id)).toEqual(["scheduled-1"]);
  });

  it("extracts a detail payload", () => {
    const game = extractTournamentGame({
      success: true,
      data: {
        game: {
          id: "game-detail-1",
          home_team: { displayName: "Home" },
          away_team: { displayName: "Away" },
          rink_name: "North",
          scheduled_at: "2026-08-11T20:00:00Z",
          status: "READY",
          scoring_status: "ARMED",
        },
      },
    });

    expect(game?.id).toBe("game-detail-1");
    expect(game?.homeTeamName).toBe("Home");
    expect(game?.awayTeamName).toBe("Away");
    expect(game?.status).toBe("READY");
    expect(game?.scoringStatus).toBe("ARMED");
  });
});
EOF

cat > "apps/dashboard/e2e/tournament-game-operations.spec.ts" <<'EOF'
import { expect, test } from "@playwright/test";

test.describe("Milestone 7.1 tournament game operations workspace", () => {
  test("loads a scheduled game and exposes non-mutating operations context", async ({
    page,
  }) => {
    await page.route("**/api/tournament/game-operations", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          success: true,
          data: {
            games: [
              {
                id: "game-701",
                homeTeam: { name: "Prior Lake Lakers" },
                awayTeam: { name: "Edina" },
                venue: { name: "Sports Arena" },
                rink: { name: "Rink A" },
                scheduledStart: "2026-08-11T18:00:00.000Z",
                status: "SCHEDULED",
              },
            ],
          },
        }),
      });
    });

    await page.route(
      "**/api/tournament/game-operations/game-701",
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            success: true,
            data: {
              game: {
                id: "game-701",
                homeTeam: { name: "Prior Lake Lakers" },
                awayTeam: { name: "Edina" },
                venue: { name: "Sports Arena" },
                rink: { name: "Rink A" },
                scheduledStart: "2026-08-11T18:00:00.000Z",
                status: "SCHEDULED",
                scoringStatus: "NOT_STARTED",
              },
            },
          }),
        });
      },
    );

    await page.goto("/tournament/game-operations");

    await expect(
      page.getByTestId("game-operations-workspace"),
    ).toBeVisible();

    await page.getByTestId("game-operations-select").selectOption("game-701");

    await expect(page.getByTestId("game-operations-matchup")).toContainText(
      "Prior Lake Lakers vs Edina",
    );
    await expect(
      page.getByTestId("game-operations-readiness-count"),
    ).toHaveText("3/3");

    await expect(
      page.getByRole("button", { name: "Not enabled in 7.1" }),
    ).toHaveCount(4);

    await expect(page).toHaveURL(/gameId=game-701/);
  });
});
EOF

cat <<'EOF'

Milestone 7.1 files written:
  - apps/dashboard/app/tournament/game-operations/page.tsx
  - apps/dashboard/app/api/tournament/game-operations/route.ts
  - apps/dashboard/app/api/tournament/game-operations/[gameId]/route.ts
  - apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx
  - apps/dashboard/lib/tournament-game-operations.ts
  - apps/dashboard/test/tournament-game-operations-7.1.test.ts
  - apps/dashboard/e2e/tournament-game-operations.spec.ts

Milestone boundary:
  - Read-only game operations workspace
  - Scheduled-game picker + direct game ID loading
  - Matchup, venue/rink, scheduled start, game status, scoring status
  - Initial readiness summary from already-known game context
  - Future operator action surfaces are visible but deliberately disabled
  - No Milestone 6 audit/handoff files are modified
  - No game mutations are introduced in 7.1

Upstream compatibility:
  - Dashboard proxy reads GET /games
  - Dashboard proxy reads GET /games/:gameId
  - API base URL resolution:
      SPORTSOS_API_URL
      API_URL
      NEXT_PUBLIC_API_URL
      fallback http://api:4001

If your existing game read endpoints use a different URL shape, the validation
gate will identify that during runtime testing; adjust only the two dashboard
proxy route handlers rather than the workspace itself.

Run the small green gate first:

  npm run typecheck && npm test

If green, run the full project gate:

  npm run typecheck && \
  npm test && \
  npm run build && \
  docker compose up -d --build api dashboard && \
  npm run test:e2e:docker

Then open:

  http://<YOUR-UNRAID-IP>:4000/tournament/game-operations

EOF
