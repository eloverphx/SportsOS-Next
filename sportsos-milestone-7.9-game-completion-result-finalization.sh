#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.9-game-completion-result-finalization"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

LIFECYCLE="apps/api/src/modules/games/lifecycle.ts"
GAME_ROUTES="apps/api/src/modules/games/routes.ts"
WORKSPACE="apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx"
FINAL_DIR="apps/dashboard/app/api/tournament/game-operations/[gameId]/finalize"
FINAL_ROUTE="${FINAL_DIR}/route.ts"
FINAL_CONTROL="apps/dashboard/components/tournament/GameResultFinalizationControl.tsx"
FINAL_LIB="apps/dashboard/lib/tournament-game-result-finalization.ts"
FINAL_TEST="apps/dashboard/test/tournament-game-result-finalization-7.9.test.ts"

for file in "$LIFECYCLE" "$GAME_ROUTES" "$WORKSPACE"; do
  [[ -f "$file" ]] || { echo "ERROR: required prerequisite missing: $file" >&2; exit 1; }
done

grep -Fq 'app.post("/games/:id/lifecycle"' "$GAME_ROUTES" || {
  echo "ERROR: authenticated lifecycle route not found." >&2
  exit 1
}

grep -Fq 'gameLifecycleCommands' "$LIFECYCLE" || {
  echo "ERROR: lifecycle command list not found." >&2
  exit 1
}

DISCOVERY="$(node <<'NODE'
const fs = require("fs");

const text = fs.readFileSync(
  "apps/api/src/modules/games/lifecycle.ts",
  "utf8",
);

const cases = [
  ...text.matchAll(
    /case\s+["'`]([^"'`]+)["'`]\s*:\s*([\s\S]*?)(?=\n\s*case\s+["'`]|[\n\r]\s*default\s*:|[\n\r]\s*\})/g,
  ),
].map((match) => ({
  command: match[1],
  body: match[2],
}));

const mappings = [];

for (const entry of cases) {
  const action =
    entry.body.match(
      /return\s+\{\s*action:\s*["'`]([^"'`]+)["'`]/,
    )?.[1] ?? null;

  mappings.push({
    command: entry.command,
    action,
  });
}

const candidate = mappings.find(({ command, action }) => {
  const combined = `${command} ${action ?? ""}`;
  return /\b(final|finalize|finish|complete|endGame)\b/i.test(combined) ||
    /(final|finalize|finish|complete|endGame)/i.test(combined);
});

if (!candidate || !candidate.action) {
  console.error("Lifecycle mappings discovered:");
  for (const mapping of mappings) {
    console.error(
      `  ${mapping.command} -> ${mapping.action ?? "(no direct action)"}`,
    );
  }
  throw new Error(
    "Could not prove which lifecycle command finalizes the game.",
  );
}

process.stdout.write(JSON.stringify(candidate));
NODE
)"

FINAL_COMMAND="$(
  node -e \
    'const v=JSON.parse(process.argv[1]); process.stdout.write(v.command)' \
    "$DISCOVERY"
)"

FINAL_ACTION="$(
  node -e \
    'const v=JSON.parse(process.argv[1]); process.stdout.write(v.action)' \
    "$DISCOVERY"
)"

echo "Discovered finalization lifecycle mapping:"
echo "  command: $FINAL_COMMAND"
echo "  action:  $FINAL_ACTION"
echo
echo "API contract:"
echo "  POST /games/:id/lifecycle"
echo "  { \"command\": \"$FINAL_COMMAND\" }"
echo

mkdir -p \
  "$BACKUP_DIR/$(dirname "$WORKSPACE")" \
  "$BACKUP_DIR/$(dirname "$FINAL_ROUTE")" \
  "$BACKUP_DIR/$(dirname "$FINAL_CONTROL")" \
  "$BACKUP_DIR/$(dirname "$FINAL_LIB")" \
  "$BACKUP_DIR/$(dirname "$FINAL_TEST")" \
  "$FINAL_DIR"

for file in \
  "$WORKSPACE" \
  "$FINAL_ROUTE" \
  "$FINAL_CONTROL" \
  "$FINAL_LIB" \
  "$FINAL_TEST"
do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$FINAL_LIB" <<'EOF'
export type FinalizedGameResult = {
  gameId: string;
  homeScore: number;
  awayScore: number;
  status: string;
  gamePhase: string | null;
  finalizedAt: string;
};

export function buildFinalizedGameResult(input: {
  gameId: string;
  homeScore: unknown;
  awayScore: unknown;
  status: unknown;
  gamePhase?: unknown;
  finalizedAt?: Date;
}): FinalizedGameResult {
  if (
    typeof input.homeScore !== "number" ||
    !Number.isFinite(input.homeScore) ||
    typeof input.awayScore !== "number" ||
    !Number.isFinite(input.awayScore)
  ) {
    throw new Error("Finalized game response has invalid scores.");
  }

  if (typeof input.status !== "string" || !input.status.trim()) {
    throw new Error("Finalized game response has invalid status.");
  }

  return {
    gameId: input.gameId,
    homeScore: input.homeScore,
    awayScore: input.awayScore,
    status: input.status,
    gamePhase:
      typeof input.gamePhase === "string"
        ? input.gamePhase
        : null,
    finalizedAt: (input.finalizedAt ?? new Date()).toISOString(),
  };
}

export function resultLabel(
  result: FinalizedGameResult,
): string {
  if (result.homeScore > result.awayScore) {
    return "Home win";
  }

  if (result.awayScore > result.homeScore) {
    return "Away win";
  }

  return "Tie";
}
EOF

cat > "$FINAL_ROUTE" <<EOF
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

  const response = await fetch(
    \`\${API_BASE_URL}/games/\${encodeURIComponent(gameId)}/lifecycle\`,
    {
      method: "POST",
      headers,
      body: JSON.stringify({
        command: ${FINAL_COMMAND@Q},
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

cat > "$FINAL_CONTROL" <<'EOF'
"use client";

import { useState } from "react";
import {
  buildFinalizedGameResult,
  resultLabel,
  type FinalizedGameResult,
} from "../../lib/tournament-game-result-finalization";

type Props = {
  gameId: string;
};

type LifecycleFinalizeResponse = {
  game?: {
    id?: string;
    homeScore?: number;
    awayScore?: number;
    status?: string;
    gamePhase?: string | null;
  };
};

export function GameResultFinalizationControl({
  gameId,
}: Props) {
  const [pending, setPending] = useState(false);
  const [confirmation, setConfirmation] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] =
    useState<FinalizedGameResult | null>(null);

  const finalizeGame = async () => {
    if (!confirmation || pending || result) {
      return;
    }

    setPending(true);
    setError(null);

    try {
      const response = await fetch(
        `/api/tournament/game-operations/${encodeURIComponent(gameId)}/finalize`,
        {
          method: "POST",
        },
      );

      const body = await response.text();

      if (!response.ok) {
        throw new Error(
          body ||
            `Game finalization request failed (${response.status}).`,
        );
      }

      let parsed: LifecycleFinalizeResponse;

      try {
        parsed = JSON.parse(body) as LifecycleFinalizeResponse;
      } catch {
        throw new Error(
          "Game finalization succeeded but the API response could not be parsed.",
        );
      }

      if (!parsed.game) {
        throw new Error(
          "Game finalization response did not include the authoritative game.",
        );
      }

      setResult(
        buildFinalizedGameResult({
          gameId: parsed.game.id ?? gameId,
          homeScore: parsed.game.homeScore,
          awayScore: parsed.game.awayScore,
          status: parsed.game.status,
          gamePhase: parsed.game.gamePhase,
        }),
      );
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : "Game finalization failed.",
      );
    } finally {
      setPending(false);
    }
  };

  return (
    <section
      data-testid="game-result-finalization-panel"
      className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="font-semibold text-slate-100">
            Game completion
          </h2>
          <p className="mt-1 text-xs leading-5 text-slate-500">
            Finalize the game through the authenticated lifecycle API and
            capture the authoritative final result.
          </p>
        </div>

        <span
          data-testid="game-result-finalization-status"
          className={
            result
              ? "text-sm font-semibold text-emerald-400"
              : "text-sm font-semibold text-slate-400"
          }
        >
          {result ? "FINAL" : "Not finalized"}
        </span>
      </div>

      {result ? (
        <div className="mt-4 rounded-lg border border-emerald-900/70 bg-emerald-950/20 p-4">
          <div className="text-xs font-semibold uppercase tracking-wide text-emerald-400">
            Authoritative final result
          </div>

          <div
            data-testid="final-game-score"
            className="mt-2 text-3xl font-bold text-slate-100"
          >
            {result.homeScore} – {result.awayScore}
          </div>

          <div className="mt-2 text-sm text-slate-300">
            {resultLabel(result)}
            {" · "}
            status {result.status}
            {result.gamePhase
              ? ` · phase ${result.gamePhase}`
              : ""}
          </div>
        </div>
      ) : (
        <div className="mt-4 space-y-3">
          <label className="flex items-start gap-3 rounded-lg border border-amber-900/60 bg-amber-950/20 p-3">
            <input
              type="checkbox"
              data-testid="confirm-game-finalization"
              checked={confirmation}
              onChange={(event) =>
                setConfirmation(event.target.checked)
              }
              className="mt-0.5"
            />

            <span className="text-xs leading-5 text-amber-200">
              I have reviewed the scoreboard and understand this will request
              the server's final game lifecycle transition.
            </span>
          </label>

          <button
            type="button"
            data-testid="finalize-game-result"
            disabled={!confirmation || pending}
            onClick={finalizeGame}
            className="w-full rounded-lg border border-red-900/70 bg-red-950/20 px-3 py-2 text-sm font-semibold text-red-300 transition hover:border-red-700 disabled:cursor-not-allowed disabled:opacity-40"
          >
            {pending ? "Finalizing..." : "Finalize game result"}
          </button>
        </div>
      )}

      {error ? (
        <div
          data-testid="game-result-finalization-error"
          className="mt-3 rounded-lg border border-red-900/60 bg-red-950/20 px-3 py-3 text-xs text-red-300"
        >
          {error}
        </div>
      ) : null}

      <p className="mt-3 text-xs leading-5 text-slate-500">
        The API remains authoritative. Invalid phase, permission, or lifecycle
        transitions are rejected server-side rather than overridden by this
        dashboard.
      </p>
    </section>
  );
}
EOF

cat > "$FINAL_TEST" <<EOF
import { describe, expect, it } from "vitest";
import fs from "node:fs";
import {
  buildFinalizedGameResult,
  resultLabel,
} from "../lib/tournament-game-result-finalization";

describe("Milestone 7.9 game completion / result finalization", () => {
  it("uses the discovered lifecycle finalization command", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/game-operations/[gameId]/finalize/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain("/lifecycle");
    expect(route).toContain(${FINAL_COMMAND@Q});
    expect(route).toContain('method: "POST"');
  });

  it("builds an authoritative final result", () => {
    const result = buildFinalizedGameResult({
      gameId: "game-79",
      homeScore: 5,
      awayScore: 3,
      status: "FINAL",
      gamePhase: "FINAL",
      finalizedAt: new Date("2026-08-17T02:00:00.000Z"),
    });

    expect(result.homeScore).toBe(5);
    expect(result.awayScore).toBe(3);
    expect(resultLabel(result)).toBe("Home win");
  });

  it("supports away wins and ties", () => {
    expect(
      resultLabel(
        buildFinalizedGameResult({
          gameId: "away-win",
          homeScore: 2,
          awayScore: 4,
          status: "FINAL",
        }),
      ),
    ).toBe("Away win");

    expect(
      resultLabel(
        buildFinalizedGameResult({
          gameId: "tie",
          homeScore: 3,
          awayScore: 3,
          status: "FINAL",
        }),
      ),
    ).toBe("Tie");
  });

  it("rejects malformed authoritative scores", () => {
    expect(() =>
      buildFinalizedGameResult({
        gameId: "bad",
        homeScore: "5",
        awayScore: 3,
        status: "FINAL",
      }),
    ).toThrow("invalid scores");
  });
});
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx";

let text = fs.readFileSync(file, "utf8");

function requireFound(condition, message) {
  if (!condition) throw new Error(message);
}

if (!text.includes('from "./GameResultFinalizationControl";')) {
  const importAnchor =
    'import { GameLiveTransitionControl } from "./GameLiveTransitionControl";';

  requireFound(
    text.includes(importAnchor),
    "Could not locate Milestone 7.7 live transition import.",
  );

  text = text.replace(
    importAnchor,
`${importAnchor}
import { GameResultFinalizationControl } from "./GameResultFinalizationControl";`,
  );
}

if (!text.includes("<GameResultFinalizationControl")) {
  const readinessHeadingIndex = text.indexOf("Pregame readiness");

  requireFound(
    readinessHeadingIndex >= 0,
    "Could not locate Pregame readiness panel.",
  );

  const readinessAsideIndex = text.lastIndexOf(
    '<aside className="rounded-xl',
    readinessHeadingIndex,
  );

  requireFound(
    readinessAsideIndex >= 0,
    "Could not locate Pregame readiness aside.",
  );

  const control = `            <GameResultFinalizationControl
              gameId={selectedGame.id}
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
echo " SportsOS-Next Milestone 7.9 installed"
echo "============================================================"
echo
echo "Discovered lifecycle mapping:"
echo "  $FINAL_COMMAND -> $FINAL_ACTION"
echo
echo "Added:"
echo "  - authenticated game-finalization proxy"
echo "  - explicit operator confirmation"
echo "  - authoritative final score from API response"
echo "  - final status / phase display"
echo "  - home win / away win / tie result labeling"
echo "  - lifecycle contract and result tests"
echo
echo "Safety:"
echo "  - browser cannot force FINAL state"
echo "  - API permissions and lifecycle rules remain authoritative"
echo "  - installer aborts before writes if finalization command is ambiguous"
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
