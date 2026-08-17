#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.7-live-game-state-integration"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

GAME_ROUTES="apps/api/src/modules/games/routes.ts"
WORKSPACE="apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx"
AUTH_LIB="apps/dashboard/lib/tournament-game-start-authorization.ts"
PROXY_DIR="apps/dashboard/app/api/tournament/game-operations/[gameId]/start"
PROXY_FILE="${PROXY_DIR}/route.ts"
CONTROL="apps/dashboard/components/tournament/GameLiveTransitionControl.tsx"
TEST_FILE="apps/dashboard/test/tournament-live-game-state-7.7.test.ts"

for file in "$GAME_ROUTES" "$WORKSPACE" "$AUTH_LIB"; do
  [[ -f "$file" ]] || { echo "ERROR: required prerequisite missing: $file" >&2; exit 1; }
done

grep -Fq 'game.lifecycle' "$GAME_ROUTES" || {
  echo "ERROR: existing authenticated game lifecycle route could not be identified." >&2
  exit 1
}

grep -Fq 'game-start-authorization-panel' "$WORKSPACE" || {
  echo "ERROR: Milestone 7.6 authorization UI not found." >&2
  exit 1
}

# Discover the existing authenticated lifecycle endpoint and its start action
# before modifying anything. We intentionally refuse to invent this contract.
DISCOVERY="$(node <<'NODE'
const fs = require("fs");

const file = "apps/api/src/modules/games/routes.ts";
const text = fs.readFileSync(file, "utf8");
const marker = text.indexOf('"game.lifecycle"') >= 0
  ? text.indexOf('"game.lifecycle"')
  : text.indexOf("'game.lifecycle'");

if (marker < 0) {
  throw new Error("game.lifecycle audit marker not found");
}

const before = text.slice(Math.max(0, marker - 10000), marker + 3000);

const routeMatches = [...before.matchAll(
  /app\.(post|put|patch)\(\s*["'`]([^"'`]+)["'`]/g
)];

if (routeMatches.length === 0) {
  throw new Error("Could not discover lifecycle mutation route");
}

const route = routeMatches[routeMatches.length - 1];
const method = route[1].toUpperCase();
const path = route[2];

const routeStart = route.index ?? 0;
const block = before.slice(routeStart);

let actionKey = null;
if (
  /body\.action\b/.test(block) ||
  /\{\s*action\s*[,}]/.test(block) ||
  /action:\s*\{/.test(block)
) {
  actionKey = "action";
}

if (!actionKey) {
  throw new Error("Could not prove lifecycle request body uses an action field");
}

const startCandidates = [
  ...block.matchAll(/["'`]([A-Za-z0-9_-]*START[A-Za-z0-9_-]*)["'`]/gi),
].map((m) => m[1]);

const preferred =
  startCandidates.find((v) => /^START_GAME$/i.test(v)) ??
  startCandidates.find((v) => /^START$/i.test(v)) ??
  startCandidates.find((v) => /START/i.test(v));

if (!preferred) {
  throw new Error("Could not discover a start lifecycle action value");
}

process.stdout.write(
  JSON.stringify({
    method,
    path,
    actionKey,
    actionValue: preferred,
  })
);
NODE
)"

[[ -n "$DISCOVERY" ]] || {
  echo "ERROR: lifecycle discovery returned no result." >&2
  exit 1
}

METHOD="$(node -e 'const v=JSON.parse(process.argv[1]); process.stdout.write(v.method)' "$DISCOVERY")"
UPSTREAM_PATH="$(node -e 'const v=JSON.parse(process.argv[1]); process.stdout.write(v.path)' "$DISCOVERY")"
ACTION_KEY="$(node -e 'const v=JSON.parse(process.argv[1]); process.stdout.write(v.actionKey)' "$DISCOVERY")"
ACTION_VALUE="$(node -e 'const v=JSON.parse(process.argv[1]); process.stdout.write(v.actionValue)' "$DISCOVERY")"

echo "Discovered existing lifecycle contract:"
echo "  method: $METHOD"
echo "  path:   $UPSTREAM_PATH"
echo "  body:   { \"$ACTION_KEY\": \"$ACTION_VALUE\" }"
echo

mkdir -p \
  "$BACKUP_DIR/$(dirname "$WORKSPACE")" \
  "$BACKUP_DIR/$(dirname "$PROXY_FILE")" \
  "$BACKUP_DIR/$(dirname "$CONTROL")" \
  "$BACKUP_DIR/$(dirname "$TEST_FILE")" \
  "$PROXY_DIR"

for file in "$WORKSPACE" "$PROXY_FILE" "$CONTROL" "$TEST_FILE"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$PROXY_FILE" <<EOF
import { NextRequest, NextResponse } from "next/server";

const API_BASE_URL =
  process.env.SPORTSOS_API_URL ??
  process.env.API_URL ??
  process.env.NEXT_PUBLIC_API_URL ??
  "http://api:4001";

const UPSTREAM_PATH_TEMPLATE = ${UPSTREAM_PATH@Q};
const LIFECYCLE_METHOD = ${METHOD@Q};
const ACTION_KEY = ${ACTION_KEY@Q};
const ACTION_VALUE = ${ACTION_VALUE@Q};

function upstreamPath(gameId: string): string {
  return UPSTREAM_PATH_TEMPLATE
    .replace(":gameId", encodeURIComponent(gameId))
    .replace(":id", encodeURIComponent(gameId));
}

export async function POST(
  request: NextRequest,
  context: { params: Promise<{ gameId: string }> },
) {
  const { gameId } = await context.params;

  const headers = new Headers({
    "content-type": "application/json",
  });

  const authorization = request.headers.get("authorization");
  const cookie = request.headers.get("cookie");
  const requestId = request.headers.get("x-request-id");

  if (authorization) headers.set("authorization", authorization);
  if (cookie) headers.set("cookie", cookie);
  if (requestId) headers.set("x-request-id", requestId);

  /*
   * Security boundary:
   * - We forward authentication to the existing SportsOS API lifecycle route.
   * - We DO NOT forward browser testing-override/localStorage state.
   * - The API remains authoritative for permission and lifecycle validation.
   */
  const response = await fetch(
    \`\${API_BASE_URL}\${upstreamPath(gameId)}\`,
    {
      method: LIFECYCLE_METHOD,
      headers,
      body: JSON.stringify({
        [ACTION_KEY]: ACTION_VALUE,
      }),
      cache: "no-store",
    },
  );

  const contentType =
    response.headers.get("content-type") ?? "application/json";

  const body = await response.text();

  return new NextResponse(body, {
    status: response.status,
    headers: {
      "content-type": contentType,
    },
  });
}
EOF

cat > "$CONTROL" <<'EOF'
"use client";

import { useState } from "react";
import type { GameStartAuthorizationRecord } from "../../lib/tournament-game-start-authorization";

type Props = {
  gameId: string;
  authorization: GameStartAuthorizationRecord | null;
};

export function GameLiveTransitionControl({
  gameId,
  authorization,
}: Props) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [started, setStarted] = useState(false);

  const requestLiveTransition = async () => {
    if (!authorization || pending) {
      return;
    }

    setPending(true);
    setError(null);

    try {
      const response = await fetch(
        `/api/tournament/game-operations/${encodeURIComponent(gameId)}/start`,
        {
          method: "POST",
          headers: {
            "content-type": "application/json",
          },
        },
      );

      if (!response.ok) {
        const detail = await response.text();
        throw new Error(
          detail || `Game start request failed (${response.status}).`,
        );
      }

      setStarted(true);
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : "Game start request failed.",
      );
    } finally {
      setPending(false);
    }
  };

  return (
    <section
      data-testid="live-game-transition-panel"
      className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="font-semibold text-slate-100">
            Live game state
          </h2>
          <p className="mt-1 text-xs leading-5 text-slate-500">
            Request the authenticated SportsOS API lifecycle transition after
            game-start authorization.
          </p>
        </div>

        <span
          data-testid="live-game-transition-status"
          className={
            started
              ? "text-sm font-semibold text-emerald-400"
              : "text-sm font-semibold text-slate-400"
          }
        >
          {started ? "Start accepted" : "Awaiting start"}
        </span>
      </div>

      {!authorization ? (
        <div className="mt-4 rounded-lg border border-amber-900/60 bg-amber-950/20 px-3 py-3 text-sm text-amber-300">
          Game-start authorization is required before the dashboard will send
          a live transition request.
        </div>
      ) : (
        <div className="mt-4">
          <div className="rounded-lg border border-slate-800 bg-slate-950/60 px-3 py-3 text-xs text-slate-400">
            Authorized by{" "}
            <span className="font-semibold text-slate-200">
              {authorization.authorizedBy}
            </span>
            {" · "}
            {authorization.mode === "normal"
              ? "normal readiness"
              : "testing-override operations record"}
          </div>

          <button
            type="button"
            data-testid="request-live-game-transition"
            disabled={pending || started}
            onClick={requestLiveTransition}
            className="mt-3 w-full rounded-lg border border-emerald-800/70 bg-emerald-950/20 px-3 py-2 text-sm font-semibold text-emerald-300 transition hover:border-emerald-600 disabled:cursor-not-allowed disabled:opacity-40"
          >
            {pending
              ? "Requesting start..."
              : started
                ? "Start request accepted"
                : "Start live game"}
          </button>
        </div>
      )}

      {error ? (
        <div
          data-testid="live-game-transition-error"
          className="mt-3 rounded-lg border border-red-900/60 bg-red-950/20 px-3 py-3 text-xs text-red-300"
        >
          {error}
        </div>
      ) : null}

      <p className="mt-3 text-xs leading-5 text-slate-500">
        Local testing override is never sent as API authority. Authentication,
        permission checks, and lifecycle validation remain server-side.
      </p>
    </section>
  );
}
EOF

cat > "$TEST_FILE" <<EOF
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 7.7 live game state integration", () => {
  it("uses the discovered authenticated lifecycle API contract", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/game-operations/[gameId]/start/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain(${UPSTREAM_PATH@Q});
    expect(route).toContain(${ACTION_VALUE@Q});
    expect(route).toContain("authorization");
    expect(route).toContain("cookie");
  });

  it("does not forward local testing override as API authority", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/game-operations/[gameId]/start/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).not.toContain("x-sportsos-testing-override");
    expect(route).not.toContain("testingOverrideEnabled");
  });
});
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx";

let text = fs.readFileSync(file, "utf8");

function assertFound(condition, message) {
  if (!condition) throw new Error(message);
}

if (!text.includes('from "./GameLiveTransitionControl";')) {
  const importAnchor =
`} from "../../lib/tournament-game-start-authorization";`;

  assertFound(
    text.includes(importAnchor),
    "Could not locate game-start authorization import.",
  );

  text = text.replace(
    importAnchor,
`${importAnchor}
import { GameLiveTransitionControl } from "./GameLiveTransitionControl";`,
  );
}

if (!text.includes("<GameLiveTransitionControl")) {
  const readinessHeadingIndex = text.indexOf("Pregame readiness");

  assertFound(
    readinessHeadingIndex >= 0,
    "Could not locate Pregame readiness panel.",
  );

  const readinessAsideIndex = text.lastIndexOf(
    '<aside className="rounded-xl',
    readinessHeadingIndex,
  );

  assertFound(
    readinessAsideIndex >= 0,
    "Could not locate Pregame readiness aside.",
  );

  const control = `            <GameLiveTransitionControl
              gameId={selectedGame.id}
              authorization={gameStartAuthorization}
            />

`;

  text =
    text.slice(0, readinessAsideIndex) +
    control +
    text.slice(readinessAsideIndex);
}

fs.writeFileSync(file, text);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 7.7 installed"
echo "============================================================"
echo
echo "Discovered lifecycle contract:"
echo "  $METHOD $UPSTREAM_PATH"
echo "  { \"$ACTION_KEY\": \"$ACTION_VALUE\" }"
echo
echo "Added:"
echo "  - authenticated dashboard-to-API live-start bridge"
echo "  - forwards auth/cookies to the existing API lifecycle endpoint"
echo "  - game-start authorization UI gate"
echo "  - live transition status/error UI"
echo "  - API contract regression tests"
echo
echo "Security boundary preserved:"
echo "  - browser testing override is NOT forwarded as server authority"
echo "  - SportsOS API remains responsible for auth/permissions/lifecycle rules"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo "  npm run build && \\"
echo "  docker compose up -d --build api dashboard && \\"
echo "  npm run test:e2e:docker"
