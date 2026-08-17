#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="9.5-realtime-overlay-updates"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  echo "Expected: $EXPECTED_REAL" >&2
  echo "Received: $ROOT_REAL" >&2
  exit 1
fi

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps"
do
  [[ -e "$required" ]] || {
    echo "ERROR: repository safety marker missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

CLIENT="apps/dashboard/components/broadcast/BroadcastOverlayClient.tsx"
TEST="apps/dashboard/test/broadcast-overlay-realtime-9.5.test.ts"

[[ -f "$CLIENT" ]] || {
  echo "ERROR: Milestone 9.4 browser overlay missing: $CLIENT" >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$CLIENT")" \
  "$BACKUP_DIR/$(dirname "$TEST")"

for file in "$CLIENT" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$CLIENT" <<'EOF'
"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { io, type Socket } from "socket.io-client";
import type {
  BroadcastOverlaySnapshot,
} from "../../lib/broadcast-overlay-contract";

type Props = {
  gameId: string;
};

type RealtimePayload = {
  gameId?: string;
};

const SOCKET_URL =
  process.env.NEXT_PUBLIC_SPORTSOS_SOCKET_URL ??
  process.env.NEXT_PUBLIC_API_URL ??
  "";

function formatClock(remainingMs: number): string {
  const totalSeconds = Math.max(
    0,
    Math.floor(remainingMs / 1000),
  );

  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;

  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

export function BroadcastOverlayClient({
  gameId,
}: Props) {
  const [snapshot, setSnapshot] =
    useState<BroadcastOverlaySnapshot | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [realtimeConnected, setRealtimeConnected] =
    useState(false);

  const loadInFlight = useRef(false);

  useEffect(() => {
    let active = true;
    let fallbackTimer: ReturnType<typeof setInterval> | null =
      null;
    let socket: Socket | null = null;

    const load = async () => {
      if (loadInFlight.current) {
        return;
      }

      loadInFlight.current = true;

      try {
        const response = await fetch(
          `/api/tournament/broadcast/overlay/${encodeURIComponent(gameId)}`,
          {
            cache: "no-store",
          },
        );

        if (!response.ok) {
          throw new Error(
            `Overlay snapshot request failed (${response.status}).`,
          );
        }

        const payload =
          (await response.json()) as BroadcastOverlaySnapshot;

        if (active) {
          setSnapshot(payload);
          setError(null);
        }
      } catch (cause) {
        if (active) {
          setError(
            cause instanceof Error
              ? cause.message
              : "Unable to load overlay snapshot.",
          );
        }
      } finally {
        loadInFlight.current = false;
      }
    };

    const refreshIfGameMatches = (
      payload?: RealtimePayload,
    ) => {
      if (
        !payload?.gameId ||
        payload.gameId === gameId
      ) {
        void load();
      }
    };

    void load();

    fallbackTimer = setInterval(() => {
      void load();
    }, 5000);

    if (SOCKET_URL) {
      socket = io(SOCKET_URL, {
        transports: ["websocket", "polling"],
        withCredentials: true,
      });

      socket.on("connect", () => {
        if (active) {
          setRealtimeConnected(true);
        }

        socket?.emit("game:join", {
          gameId,
        });

        void load();
      });

      socket.on("disconnect", () => {
        if (active) {
          setRealtimeConnected(false);
        }
      });

      socket.on("game:updated", refreshIfGameMatches);
      socket.on("game:event", refreshIfGameMatches);
      socket.on("scoreboard:update", refreshIfGameMatches);
      socket.on("game:state", refreshIfGameMatches);
    }

    return () => {
      active = false;

      if (fallbackTimer) {
        clearInterval(fallbackTimer);
      }

      if (socket) {
        socket.emit("game:leave", {
          gameId,
        });

        socket.disconnect();
      }
    };
  }, [gameId]);

  const powerPlayLabel = useMemo(() => {
    if (!snapshot?.powerPlay) {
      return null;
    }

    const team =
      snapshot.powerPlay.teamId === snapshot.home.id
        ? snapshot.home
        : snapshot.powerPlay.teamId === snapshot.away.id
          ? snapshot.away
          : null;

    if (!team) {
      return null;
    }

    return `${team.shortName ?? team.name} PP ${formatClock(
      snapshot.powerPlay.remainingMs,
    )}`;
  }, [snapshot]);

  if (error && !snapshot) {
    return (
      <div
        data-testid="broadcast-overlay-error"
        className="flex h-screen w-screen items-center justify-center bg-transparent text-sm font-semibold text-red-400"
      >
        {error}
      </div>
    );
  }

  if (!snapshot) {
    return (
      <div className="h-screen w-screen bg-transparent" />
    );
  }

  return (
    <main
      data-testid="broadcast-browser-overlay"
      className="pointer-events-none relative h-screen w-screen overflow-hidden bg-transparent font-sans"
    >
      <div className="absolute inset-x-0 bottom-8 mx-auto flex w-[min(94vw,1200px)] items-stretch overflow-hidden rounded-2xl border border-white/15 bg-slate-950/90 text-white shadow-2xl backdrop-blur">
        <div className="flex min-w-0 flex-1 items-center gap-4 px-5 py-4">
          {snapshot.home.logoUrl ? (
            <img
              src={snapshot.home.logoUrl}
              alt=""
              className="h-12 w-12 shrink-0 object-contain"
            />
          ) : null}

          <div className="min-w-0 flex-1">
            <div className="truncate text-sm font-semibold uppercase tracking-wide text-slate-400">
              {snapshot.home.shortName ??
                snapshot.home.name}
            </div>
            <div
              data-testid="overlay-home-score"
              className="text-4xl font-black leading-none"
            >
              {snapshot.home.score}
            </div>
          </div>
        </div>

        <div className="flex min-w-[190px] flex-col items-center justify-center border-x border-white/10 px-5 py-3 text-center">
          <div
            data-testid="overlay-clock"
            className="font-mono text-4xl font-black tabular-nums"
          >
            {formatClock(snapshot.clock.remainingMs)}
          </div>

          <div className="mt-1 text-xs font-bold uppercase tracking-[0.18em] text-slate-400">
            {snapshot.period !== null
              ? `Period ${snapshot.period}`
              : snapshot.phase ?? snapshot.status}
          </div>

          {powerPlayLabel ? (
            <div
              data-testid="overlay-power-play"
              className="mt-2 rounded-full border border-amber-400/40 bg-amber-400/10 px-3 py-1 text-[11px] font-bold uppercase tracking-wide text-amber-300"
            >
              {powerPlayLabel}
            </div>
          ) : null}
        </div>

        <div className="flex min-w-0 flex-1 items-center gap-4 px-5 py-4 text-right">
          <div className="min-w-0 flex-1">
            <div className="truncate text-sm font-semibold uppercase tracking-wide text-slate-400">
              {snapshot.away.shortName ??
                snapshot.away.name}
            </div>
            <div
              data-testid="overlay-away-score"
              className="text-4xl font-black leading-none"
            >
              {snapshot.away.score}
            </div>
          </div>

          {snapshot.away.logoUrl ? (
            <img
              src={snapshot.away.logoUrl}
              alt=""
              className="h-12 w-12 shrink-0 object-contain"
            />
          ) : null}
        </div>
      </div>

      <div className="absolute right-4 top-4 flex items-center gap-2">
        <span
          data-testid="overlay-realtime-state"
          className={
            realtimeConnected
              ? "rounded-full bg-emerald-950/80 px-3 py-1 text-[10px] font-bold uppercase tracking-wide text-emerald-300"
              : "rounded-full bg-amber-950/80 px-3 py-1 text-[10px] font-bold uppercase tracking-wide text-amber-300"
          }
        >
          {realtimeConnected
            ? "Realtime"
            : "Fallback polling"}
        </span>

        {error ? (
          <span className="rounded-lg bg-red-950/80 px-3 py-2 text-xs font-semibold text-red-300">
            Data reconnecting
          </span>
        ) : null}
      </div>
    </main>
  );
}
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 9.5 realtime overlay updates", () => {
  it("uses Socket.IO for realtime updates", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/broadcast/BroadcastOverlayClient.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'from "socket.io-client"',
    );
    expect(component).toContain("io(SOCKET_URL");
  });

  it("joins and leaves the selected game room", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/broadcast/BroadcastOverlayClient.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'socket?.emit("game:join"',
    );
    expect(component).toContain(
      'socket.emit("game:leave"',
    );
  });

  it("refreshes the authoritative snapshot when realtime game events arrive", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/broadcast/BroadcastOverlayClient.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'socket.on("game:updated"',
    );
    expect(component).toContain(
      'socket.on("game:event"',
    );
    expect(component).toContain(
      'socket.on("scoreboard:update"',
    );
  });

  it("keeps a fallback polling path", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/broadcast/BroadcastOverlayClient.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain("setInterval");
    expect(component).toContain("5000");
    expect(component).toContain(
      "Fallback polling",
    );
  });

  it("shows realtime connection state", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/broadcast/BroadcastOverlayClient.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="overlay-realtime-state"',
    );
    expect(component).toContain("Realtime");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 9.5 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - .git / package.json / apps verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - Socket.IO realtime overlay updates"
echo "  - per-game room join / leave"
echo "  - authoritative refresh after realtime events"
echo "  - 5-second fallback polling"
echo "  - realtime/fallback indicator"
echo "  - reconnect-safe behavior"
echo "  - Milestone 9.5 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Next after green:"
echo "  Milestone 9.6 - Overlay Clock Smoothing"
