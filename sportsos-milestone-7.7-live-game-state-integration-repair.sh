#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.7-live-game-state-integration-repair"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

GAME_ROUTES="apps/api/src/modules/games/routes.ts"
LIFECYCLE="apps/api/src/modules/games/lifecycle.ts"
WORKSPACE="apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx"
AUTH_LIB="apps/dashboard/lib/tournament-game-start-authorization.ts"
PROXY_DIR="apps/dashboard/app/api/tournament/game-operations/[gameId]/start"
PROXY_FILE="${PROXY_DIR}/route.ts"
CONTROL="apps/dashboard/components/tournament/GameLiveTransitionControl.tsx"
TEST_FILE="apps/dashboard/test/tournament-live-game-state-7.7.test.ts"

for file in "$GAME_ROUTES" "$LIFECYCLE" "$WORKSPACE" "$AUTH_LIB"; do
  [[ -f "$file" ]] || { echo "ERROR: required prerequisite missing: $file" >&2; exit 1; }
done

grep -Fq 'app.post("/games/:id/lifecycle"' "$GAME_ROUTES" || {
  echo "ERROR: expected lifecycle route not found." >&2
  exit 1
}

grep -Fq 'command: z.enum(gameLifecycleCommands)' "$LIFECYCLE" || {
  echo "ERROR: lifecycle command schema not found." >&2
  exit 1
}

grep -Fq '"startGame"' "$LIFECYCLE" || {
  echo "ERROR: startGame lifecycle command not found." >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$WORKSPACE")" \
  "$BACKUP_DIR/$(dirname "$PROXY_FILE")" \
  "$BACKUP_DIR/$(dirname "$CONTROL")" \
  "$BACKUP_DIR/$(dirname "$TEST_FILE")" \
  "$PROXY_DIR"

for file in "$WORKSPACE" "$PROXY_FILE" "$CONTROL" "$TEST_FILE"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$PROXY_FILE" <<'EOF'
import { NextRequest, NextResponse } from "next/server";

const API_BASE_URL =
  process.env.SPORTSOS_API_URL ??
  process.env.API_URL ??
  process.env.NEXT_PUBLIC_API_URL ??
  "http://api:4001";

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
   * - Forward the user's existing auth context to the real API lifecycle route.
   * - Never send browser testing-override/localStorage state as authority.
   * - The API decides permission and whether startGame is valid.
   */
  const response = await fetch(
    `${API_BASE_URL}/games/${encodeURIComponent(gameId)}/lifecycle`,
    {
      method: "POST",
      headers,
      body: JSON.stringify({
        command: "startGame",
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
    if (!authorization || pending || started) {
      return;
    }

    setPending(true);
    setError(null);

    try {
      const response = await fetch(
        `/api/tournament/game-operations/${encodeURIComponent(gameId)}/start`,
        {
          method: "POST",
        },
      );

      const body = await response.text();

      if (!response.ok) {
        throw new Error(
          body || `Game start request failed (${response.status}).`,
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
            Start the game through the authenticated SportsOS lifecycle API.
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
          Game-start authorization is required before a live transition can be
          requested.
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
        The dashboard sends only the lifecycle command. Authentication,
        permission checks, current game state, and lifecycle validity remain
        authoritative on the API.
      </p>
    </section>
  );
}
EOF

cat > "$TEST_FILE" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 7.7 live game state integration", () => {
  it("uses the real lifecycle endpoint and startGame command", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/game-operations/[gameId]/start/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain("/games/${encodeURIComponent(gameId)}/lifecycle");
    expect(route).toContain('command: "startGame"');
    expect(route).toContain('method: "POST"');
  });

  it("forwards authentication context", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/game-operations/[gameId]/start/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain('request.headers.get("authorization")');
    expect(route).toContain('request.headers.get("cookie")');
  });

  it("does not forward testing override as server authority", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/game-operations/[gameId]/start/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).not.toContain("testingOverrideEnabled");
    expect(route).not.toContain("x-sportsos-testing-override");
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
echo " SportsOS-Next Milestone 7.7 repair installed"
echo "============================================================"
echo
echo "Wired to existing API contract:"
echo "  POST /games/:id/lifecycle"
echo '  { "command": "startGame" }'
echo
echo "Added:"
echo "  - authenticated dashboard start bridge"
echo "  - game-start authorization UI gate"
echo "  - live transition status/error UI"
echo "  - contract regression tests"
echo
echo "Security preserved:"
echo "  - testing override is not sent to API as authority"
echo "  - API enforces GAME_SCORE permission and lifecycle validity"
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
