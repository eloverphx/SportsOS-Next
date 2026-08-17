#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="9.10-broadcast-operations-dashboard"
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

for required in "$ROOT/.git" "$ROOT/package.json" "$ROOT/apps"; do
  [[ -e "$required" ]] || {
    echo "ERROR: repository safety marker missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentBroadcastOperatorPanel.tsx"
PAGE="apps/dashboard/app/tournament/broadcast/operations/page.tsx"
DASH="apps/dashboard/components/tournament/TournamentBroadcastOperationsDashboard.tsx"
SUMMARY_LIB="apps/dashboard/lib/tournament-broadcast-operations.ts"
TEST="apps/dashboard/test/tournament-broadcast-operations-9.10.test.ts"

[[ -f "$PANEL" ]] || {
  echo "ERROR: Milestone 9.9 broadcast operator panel missing: $PANEL" >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$PAGE")" \
  "$BACKUP_DIR/$(dirname "$DASH")" \
  "$BACKUP_DIR/$(dirname "$SUMMARY_LIB")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$PAGE")" \
  "$(dirname "$DASH")"

for file in "$PAGE" "$DASH" "$SUMMARY_LIB" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$SUMMARY_LIB" <<'EOF'
export type BroadcastOperationsStage =
  | "NOT_READY"
  | "READY"
  | "LIVE"
  | "DEGRADED";

export type BroadcastOperationsInput = {
  sessionReady: boolean;
  canGoLive: boolean;
  gameLive: boolean;
  transportLive: boolean;
  overlayEligible: boolean;
  realtimeConnected: boolean;
};

export type BroadcastOperationsSummary = {
  stage: BroadcastOperationsStage;
  progressPercent: number;
  alerts: string[];
};

export function buildBroadcastOperationsSummary(
  input: BroadcastOperationsInput,
): BroadcastOperationsSummary {
  const alerts: string[] = [];

  if (!input.sessionReady) {
    alerts.push("Broadcast session is not ready.");
  }

  if (!input.overlayEligible) {
    alerts.push("Broadcast overlay is not eligible.");
  }

  if (!input.realtimeConnected) {
    alerts.push("Overlay realtime connection is unavailable.");
  }

  if (input.gameLive && !input.transportLive) {
    alerts.push("Game is live but transport is not live.");
  }

  let stage: BroadcastOperationsStage = "NOT_READY";

  if (
    input.gameLive &&
    input.transportLive &&
    input.sessionReady
  ) {
    stage = input.realtimeConnected
      ? "LIVE"
      : "DEGRADED";
  } else if (
    input.sessionReady &&
    input.canGoLive
  ) {
    stage = "READY";
  } else if (
    input.sessionReady ||
    input.gameLive ||
    input.transportLive
  ) {
    stage = "DEGRADED";
  }

  const checks = [
    input.sessionReady,
    input.overlayEligible,
    input.realtimeConnected,
    input.gameLive === input.transportLive,
  ];

  const progressPercent = Math.round(
    (checks.filter(Boolean).length / checks.length) * 100,
  );

  return {
    stage,
    progressPercent,
    alerts,
  };
}
EOF

cat > "$DASH" <<'EOF'
"use client";

import { useMemo, useState } from "react";
import {
  buildBroadcastOperationsSummary,
} from "../../lib/tournament-broadcast-operations";
import { TournamentBroadcastOperatorPanel } from "./TournamentBroadcastOperatorPanel";

export function TournamentBroadcastOperationsDashboard() {
  const [gameId, setGameId] = useState("");
  const [sessionReady, setSessionReady] = useState(false);
  const [canGoLive, setCanGoLive] = useState(false);
  const [gameLive, setGameLive] = useState(false);
  const [transportLive, setTransportLive] = useState(false);
  const [overlayEligible, setOverlayEligible] = useState(false);
  const [realtimeConnected, setRealtimeConnected] = useState(false);

  const summary = useMemo(
    () =>
      buildBroadcastOperationsSummary({
        sessionReady,
        canGoLive,
        gameLive,
        transportLive,
        overlayEligible,
        realtimeConnected,
      }),
    [
      canGoLive,
      gameLive,
      overlayEligible,
      realtimeConnected,
      sessionReady,
      transportLive,
    ],
  );

  const overlayPath =
    gameId.trim().length > 0
      ? `/broadcast/overlay/${encodeURIComponent(gameId.trim())}`
      : null;

  return (
    <section
      data-testid="broadcast-operations-dashboard"
      className="space-y-6"
    >
      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
              Broadcast operations
            </div>

            <div className="mt-1 text-2xl font-bold text-slate-100">
              {summary.stage}
            </div>
          </div>

          <div className="text-right">
            <div className="text-3xl font-bold text-slate-100">
              {summary.progressPercent}%
            </div>
            <div className="text-xs text-slate-500">
              readiness
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

      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
        <div className="grid gap-4 lg:grid-cols-2">
          <label className="text-sm text-slate-300">
            <span className="mb-1 block text-xs uppercase tracking-wide text-slate-500">
              Game ID
            </span>
            <input
              value={gameId}
              onChange={(event) => setGameId(event.target.value)}
              placeholder="Enter game ID"
              className="w-full rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-slate-100"
            />
          </label>

          <div>
            <div className="mb-1 text-xs uppercase tracking-wide text-slate-500">
              Browser source
            </div>

            {overlayPath ? (
              <div className="flex gap-2">
                <code
                  data-testid="broadcast-overlay-url"
                  className="min-w-0 flex-1 overflow-x-auto rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-xs text-slate-300"
                >
                  {overlayPath}
                </code>

                <a
                  href={overlayPath}
                  target="_blank"
                  rel="noreferrer"
                  className="rounded-lg border border-slate-700 px-3 py-2 text-xs font-semibold text-slate-200"
                >
                  Open
                </a>
              </div>
            ) : (
              <div className="rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-xs text-slate-500">
                Enter a game ID to generate the browser-source path.
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        {[
          ["Session ready", sessionReady, setSessionReady],
          ["Can go live", canGoLive, setCanGoLive],
          ["Game live", gameLive, setGameLive],
          ["Transport live", transportLive, setTransportLive],
          ["Overlay eligible", overlayEligible, setOverlayEligible],
          ["Realtime connected", realtimeConnected, setRealtimeConnected],
        ].map(([label, checked, setter]) => (
          <label
            key={String(label)}
            className="flex items-center gap-3 rounded-lg border border-slate-800 bg-slate-950/40 px-3 py-3 text-sm text-slate-300"
          >
            <input
              type="checkbox"
              checked={Boolean(checked)}
              onChange={(event) =>
                (
                  setter as React.Dispatch<
                    React.SetStateAction<boolean>
                  >
                )(event.target.checked)
              }
            />
            {String(label)}
          </label>
        ))}
      </div>

      <TournamentBroadcastOperatorPanel />
    </section>
  );
}
EOF

cat > "$PAGE" <<'EOF'
import { TournamentBroadcastOperationsDashboard } from "../../../../components/tournament/TournamentBroadcastOperationsDashboard";

export default function TournamentBroadcastOperationsPage() {
  return (
    <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
      <div className="mb-6">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          SportsOS Broadcast Operations
        </div>

        <h1 className="mt-2 text-3xl font-bold text-slate-100">
          Broadcast Operations Dashboard
        </h1>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Monitor streaming readiness, browser-source output, realtime health,
          overlay eligibility, and operator branding from one workflow.
        </p>
      </div>

      <TournamentBroadcastOperationsDashboard />
    </main>
  );
}
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";
import {
  buildBroadcastOperationsSummary,
} from "../lib/tournament-broadcast-operations";

describe("Milestone 9.10 broadcast operations dashboard", () => {
  it("reports ready when the stream can go live", () => {
    const summary = buildBroadcastOperationsSummary({
      sessionReady: true,
      canGoLive: true,
      gameLive: false,
      transportLive: false,
      overlayEligible: true,
      realtimeConnected: true,
    });

    expect(summary.stage).toBe("READY");
  });

  it("reports live when game and transport are both live", () => {
    const summary = buildBroadcastOperationsSummary({
      sessionReady: true,
      canGoLive: false,
      gameLive: true,
      transportLive: true,
      overlayEligible: true,
      realtimeConnected: true,
    });

    expect(summary.stage).toBe("LIVE");
  });

  it("reports degraded when realtime is unavailable during a live broadcast", () => {
    const summary = buildBroadcastOperationsSummary({
      sessionReady: true,
      canGoLive: false,
      gameLive: true,
      transportLive: true,
      overlayEligible: true,
      realtimeConnected: false,
    });

    expect(summary.stage).toBe("DEGRADED");
  });

  it("renders the broadcast operations dashboard", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentBroadcastOperationsDashboard.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="broadcast-operations-dashboard"',
    );
    expect(component).toContain(
      'data-testid="broadcast-overlay-url"',
    );
    expect(component).toContain(
      "TournamentBroadcastOperatorPanel",
    );
  });

  it("provides the broadcast operations page", () => {
    const page = fs.readFileSync(
      new URL(
        "../app/tournament/broadcast/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Broadcast Operations Dashboard",
    );
    expect(page).toContain(
      "TournamentBroadcastOperationsDashboard",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 9.10 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - .git / package.json / apps verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - /tournament/broadcast/operations"
echo "  - unified broadcast stage / readiness"
echo "  - browser-source path generator"
echo "  - realtime / transport / overlay health controls"
echo "  - operator theme controls embedded"
echo "  - broadcast alert summary"
echo "  - Milestone 9.10 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "If green, close Milestone 9 with:"
echo "  npm run build && \\"
echo "  docker compose up -d --build api dashboard && \\"
echo "  npm run test:e2e:docker"
echo
echo "After full green:"
echo "  Milestone 9 complete"
echo "  Next: Milestone 10 - ESP32 / Physical Scoreboard Integration"
