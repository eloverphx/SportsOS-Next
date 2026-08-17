#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.8-delay-actual-start-tracking"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

WORKSPACE="apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx"
CONTROL="apps/dashboard/components/tournament/GameLiveTransitionControl.tsx"
TRACKING_LIB="apps/dashboard/lib/tournament-game-start-tracking.ts"
TRACKING_TEST="apps/dashboard/test/tournament-game-start-tracking-7.8.test.ts"
GAME_ROUTES="apps/api/src/modules/games/routes.ts"
GAME_REPOSITORY="apps/api/src/modules/games/repository.ts"

for file in "$WORKSPACE" "$CONTROL" "$GAME_ROUTES" "$GAME_REPOSITORY"; do
  [[ -f "$file" ]] || { echo "ERROR: required prerequisite missing: $file" >&2; exit 1; }
done

grep -Fq 'data-testid="live-game-transition-panel"' "$CONTROL" || {
  echo "ERROR: Milestone 7.7 live transition control not found." >&2
  exit 1
}

grep -Fq 'clockStartedAt' "$GAME_ROUTES" || {
  echo "ERROR: API game responses do not expose clockStartedAt." >&2
  exit 1
}

grep -Fq 'scheduledStart' "$GAME_REPOSITORY" || {
  echo "ERROR: scheduledStart is not available from the game model." >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$WORKSPACE")" \
  "$BACKUP_DIR/$(dirname "$CONTROL")" \
  "$BACKUP_DIR/$(dirname "$TRACKING_LIB")" \
  "$BACKUP_DIR/$(dirname "$TRACKING_TEST")"

for file in "$WORKSPACE" "$CONTROL" "$TRACKING_LIB" "$TRACKING_TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$TRACKING_LIB" <<'EOF'
export type GameStartTiming = {
  scheduledStart: string;
  actualStart: string | null;
  delayMs: number | null;
  delayMinutes: number | null;
  state: "NOT_STARTED" | "EARLY" | "ON_TIME" | "DELAYED";
};

export function computeGameStartTiming(
  scheduledStart: string,
  actualStart: string | null,
): GameStartTiming {
  const scheduledMs = new Date(scheduledStart).getTime();

  if (!Number.isFinite(scheduledMs)) {
    throw new Error("Invalid scheduled start timestamp.");
  }

  if (!actualStart) {
    return {
      scheduledStart,
      actualStart: null,
      delayMs: null,
      delayMinutes: null,
      state: "NOT_STARTED",
    };
  }

  const actualMs = new Date(actualStart).getTime();

  if (!Number.isFinite(actualMs)) {
    throw new Error("Invalid actual start timestamp.");
  }

  const delayMs = actualMs - scheduledMs;
  const delayMinutes = Math.round((delayMs / 60_000) * 10) / 10;

  let state: GameStartTiming["state"];

  if (Math.abs(delayMs) < 30_000) {
    state = "ON_TIME";
  } else if (delayMs < 0) {
    state = "EARLY";
  } else {
    state = "DELAYED";
  }

  return {
    scheduledStart,
    actualStart,
    delayMs,
    delayMinutes,
    state,
  };
}

export function formatDelayLabel(
  timing: GameStartTiming,
): string {
  switch (timing.state) {
    case "NOT_STARTED":
      return "Not started";
    case "ON_TIME":
      return "On time";
    case "EARLY":
      return `${Math.abs(timing.delayMinutes ?? 0)} min early`;
    case "DELAYED":
      return `${timing.delayMinutes ?? 0} min late`;
  }
}
EOF

cat > "$TRACKING_TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  computeGameStartTiming,
  formatDelayLabel,
} from "../lib/tournament-game-start-tracking";

describe("Milestone 7.8 delay / actual start tracking", () => {
  const scheduled = "2026-08-16T20:00:00.000Z";

  it("reports not-started before an actual start exists", () => {
    expect(computeGameStartTiming(scheduled, null)).toMatchObject({
      actualStart: null,
      delayMs: null,
      delayMinutes: null,
      state: "NOT_STARTED",
    });
  });

  it("treats a start within 30 seconds as on time", () => {
    const timing = computeGameStartTiming(
      scheduled,
      "2026-08-16T20:00:20.000Z",
    );

    expect(timing.state).toBe("ON_TIME");
    expect(formatDelayLabel(timing)).toBe("On time");
  });

  it("calculates a late start", () => {
    const timing = computeGameStartTiming(
      scheduled,
      "2026-08-16T20:07:30.000Z",
    );

    expect(timing.state).toBe("DELAYED");
    expect(timing.delayMinutes).toBe(7.5);
    expect(formatDelayLabel(timing)).toBe("7.5 min late");
  });

  it("calculates an early start", () => {
    const timing = computeGameStartTiming(
      scheduled,
      "2026-08-16T19:57:00.000Z",
    );

    expect(timing.state).toBe("EARLY");
    expect(timing.delayMinutes).toBe(-3);
    expect(formatDelayLabel(timing)).toBe("3 min early");
  });

  it("rejects invalid timestamps", () => {
    expect(() =>
      computeGameStartTiming("not-a-date", null),
    ).toThrow("Invalid scheduled start timestamp.");

    expect(() =>
      computeGameStartTiming(scheduled, "not-a-date"),
    ).toThrow("Invalid actual start timestamp.");
  });
});
EOF

cat > "$CONTROL" <<'EOF'
"use client";

import { useMemo, useState } from "react";
import type { GameStartAuthorizationRecord } from "../../lib/tournament-game-start-authorization";
import {
  computeGameStartTiming,
  formatDelayLabel,
} from "../../lib/tournament-game-start-tracking";

type Props = {
  gameId: string;
  scheduledStart: string;
  authorization: GameStartAuthorizationRecord | null;
};

type LifecycleStartResponse = {
  game?: {
    clockStartedAt?: string | null;
    scheduledStart?: string;
    status?: string;
    gamePhase?: string;
  };
};

function formatTimestamp(value: string | null): string {
  if (!value) return "—";

  const date = new Date(value);

  if (!Number.isFinite(date.getTime())) return value;

  return date.toLocaleString();
}

export function GameLiveTransitionControl({
  gameId,
  scheduledStart,
  authorization,
}: Props) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [actualStart, setActualStart] = useState<string | null>(null);
  const [startAccepted, setStartAccepted] = useState(false);

  const timing = useMemo(
    () => computeGameStartTiming(scheduledStart, actualStart),
    [actualStart, scheduledStart],
  );

  const requestLiveTransition = async () => {
    if (!authorization || pending || startAccepted) {
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

      let parsed: LifecycleStartResponse = {};

      try {
        parsed = body ? JSON.parse(body) : {};
      } catch {
        throw new Error(
          "Game start was accepted but the API response could not be parsed.",
        );
      }

      const authoritativeActualStart =
        parsed.game?.clockStartedAt ?? null;

      if (!authoritativeActualStart) {
        throw new Error(
          "Game start response did not include authoritative clockStartedAt.",
        );
      }

      setActualStart(authoritativeActualStart);
      setStartAccepted(true);
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
            startAccepted
              ? "text-sm font-semibold text-emerald-400"
              : "text-sm font-semibold text-slate-400"
          }
        >
          {startAccepted ? "LIVE start accepted" : "Awaiting start"}
        </span>
      </div>

      <div
        data-testid="game-start-timing"
        className="mt-4 grid gap-3 md:grid-cols-3"
      >
        <div className="rounded-lg border border-slate-800 bg-slate-950/60 p-3">
          <div className="text-[10px] font-semibold uppercase tracking-wide text-slate-500">
            Scheduled
          </div>
          <div className="mt-1 text-sm font-semibold text-slate-200">
            {formatTimestamp(scheduledStart)}
          </div>
        </div>

        <div className="rounded-lg border border-slate-800 bg-slate-950/60 p-3">
          <div className="text-[10px] font-semibold uppercase tracking-wide text-slate-500">
            Actual start
          </div>
          <div
            data-testid="actual-game-start"
            className="mt-1 text-sm font-semibold text-slate-200"
          >
            {formatTimestamp(actualStart)}
          </div>
        </div>

        <div className="rounded-lg border border-slate-800 bg-slate-950/60 p-3">
          <div className="text-[10px] font-semibold uppercase tracking-wide text-slate-500">
            Start variance
          </div>
          <div
            data-testid="game-start-delay"
            className={
              timing.state === "DELAYED"
                ? "mt-1 text-sm font-semibold text-amber-400"
                : timing.state === "EARLY"
                  ? "mt-1 text-sm font-semibold text-sky-400"
                  : timing.state === "ON_TIME"
                    ? "mt-1 text-sm font-semibold text-emerald-400"
                    : "mt-1 text-sm font-semibold text-slate-400"
            }
          >
            {formatDelayLabel(timing)}
          </div>
        </div>
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
            disabled={pending || startAccepted}
            onClick={requestLiveTransition}
            className="mt-3 w-full rounded-lg border border-emerald-800/70 bg-emerald-950/20 px-3 py-2 text-sm font-semibold text-emerald-300 transition hover:border-emerald-600 disabled:cursor-not-allowed disabled:opacity-40"
          >
            {pending
              ? "Requesting start..."
              : startAccepted
                ? "Game start recorded"
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
        Actual start comes from the API's authoritative clockStartedAt value.
        Delay is derived from actual start minus scheduled start; the browser
        does not invent the game-start timestamp.
      </p>
    </section>
  );
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx";

let text = fs.readFileSync(file, "utf8");

const oldControl = /<GameLiveTransitionControl\s+gameId=\{selectedGame\.id\}\s+authorization=\{gameStartAuthorization\}\s*\/>/m;

if (!oldControl.test(text)) {
  if (
    text.includes("<GameLiveTransitionControl") &&
    text.includes("scheduledStart={selectedGame.scheduledStart}")
  ) {
    process.exit(0);
  }

  throw new Error(
    "Could not locate Milestone 7.7 GameLiveTransitionControl usage.",
  );
}

text = text.replace(
  oldControl,
`<GameLiveTransitionControl
              gameId={selectedGame.id}
              scheduledStart={selectedGame.scheduledStart}
              authorization={gameStartAuthorization}
            />`,
);

fs.writeFileSync(file, text);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 7.8 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - scheduled start display"
echo "  - authoritative actual start from API clockStartedAt"
echo "  - derived early / on-time / delayed state"
echo "  - delay minutes"
echo "  - no browser-generated actual-start timestamp"
echo "  - Milestone 7.8 timing tests"
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
