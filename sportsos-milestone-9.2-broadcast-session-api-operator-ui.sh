#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="9.2-broadcast-session-api-operator-ui"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

cd "$ROOT"

SESSION_LIB="apps/dashboard/lib/tournament-broadcast-session.ts"
API_ROUTE="apps/dashboard/app/api/tournament/broadcast/session/route.ts"
PAGE="apps/dashboard/app/tournament/broadcast/page.tsx"
COMPONENT="apps/dashboard/components/tournament/TournamentBroadcastOperatorPanel.tsx"
TEST="apps/dashboard/test/tournament-broadcast-session-9.2.test.ts"

[[ -f "$SESSION_LIB" ]] || {
  echo "ERROR: Milestone 9.1 broadcast session model missing: $SESSION_LIB" >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$API_ROUTE")" \
  "$BACKUP_DIR/$(dirname "$PAGE")" \
  "$BACKUP_DIR/$(dirname "$COMPONENT")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$API_ROUTE")" \
  "$(dirname "$PAGE")" \
  "$(dirname "$COMPONENT")"

for file in "$API_ROUTE" "$PAGE" "$COMPONENT" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$API_ROUTE" <<'EOF'
import { NextRequest, NextResponse } from "next/server";
import {
  buildBroadcastSessionSummary,
  type BroadcastOverlayState,
  type BroadcastTransportState,
} from "../../../../../lib/tournament-broadcast-session";

function boolParam(
  request: NextRequest,
  key: string,
): boolean {
  return request.nextUrl.searchParams.get(key) === "true";
}

function transportParam(
  request: NextRequest,
): BroadcastTransportState {
  const value =
    request.nextUrl.searchParams.get("transport")?.toUpperCase();

  if (
    value === "OFFLINE" ||
    value === "CONNECTING" ||
    value === "READY" ||
    value === "LIVE" ||
    value === "ERROR"
  ) {
    return value;
  }

  return "OFFLINE";
}

function overlayParam(
  request: NextRequest,
): BroadcastOverlayState {
  const value =
    request.nextUrl.searchParams.get("overlay")?.toUpperCase();

  if (
    value === "DISABLED" ||
    value === "READY" ||
    value === "ACTIVE"
  ) {
    return value;
  }

  return "DISABLED";
}

export async function GET(request: NextRequest) {
  const gameId =
    request.nextUrl.searchParams.get("gameId")?.trim() ?? "";

  if (!gameId) {
    return NextResponse.json(
      {
        error: "gameId is required.",
      },
      {
        status: 400,
      },
    );
  }

  const summary = buildBroadcastSessionSummary({
    gameId,
    operatorAssigned: boolParam(
      request,
      "operatorAssigned",
    ),
    gameAuthorized: boolParam(
      request,
      "gameAuthorized",
    ),
    gameLive: boolParam(request, "gameLive"),
    transportState: transportParam(request),
    overlayState: overlayParam(request),
    streamKeyConfigured: boolParam(
      request,
      "streamKeyConfigured",
    ),
  });

  return NextResponse.json({
    summary,
  });
}
EOF

cat > "$COMPONENT" <<'EOF'
"use client";

import { useMemo, useState } from "react";
import {
  buildBroadcastSessionSummary,
  type BroadcastOverlayState,
  type BroadcastTransportState,
} from "../../lib/tournament-broadcast-session";

export function TournamentBroadcastOperatorPanel() {
  const [gameId, setGameId] = useState("");
  const [operatorAssigned, setOperatorAssigned] =
    useState(false);
  const [gameAuthorized, setGameAuthorized] =
    useState(false);
  const [gameLive, setGameLive] = useState(false);
  const [streamKeyConfigured, setStreamKeyConfigured] =
    useState(false);
  const [transportState, setTransportState] =
    useState<BroadcastTransportState>("OFFLINE");
  const [overlayState, setOverlayState] =
    useState<BroadcastOverlayState>("DISABLED");

  const summary = useMemo(
    () =>
      buildBroadcastSessionSummary({
        gameId: gameId.trim() || "unselected-game",
        operatorAssigned,
        gameAuthorized,
        gameLive,
        transportState,
        overlayState,
        streamKeyConfigured,
      }),
    [
      gameAuthorized,
      gameId,
      gameLive,
      operatorAssigned,
      overlayState,
      streamKeyConfigured,
      transportState,
    ],
  );

  return (
    <section
      data-testid="broadcast-operator-panel"
      className="space-y-5"
    >
      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
              Broadcast session
            </div>
            <div className="mt-1 text-2xl font-bold text-slate-100">
              {summary.status}
            </div>
          </div>

          <div className="text-right text-xs text-slate-500">
            {summary.ready ? "Ready" : "Not ready"}
          </div>
        </div>

        <div className="mt-4 grid gap-4 md:grid-cols-2">
          <label className="text-sm text-slate-300">
            <span className="mb-1 block text-xs uppercase tracking-wide text-slate-500">
              Game ID
            </span>
            <input
              value={gameId}
              onChange={(event) =>
                setGameId(event.target.value)
              }
              placeholder="Enter game ID"
              className="w-full rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-slate-100"
            />
          </label>

          <label className="text-sm text-slate-300">
            <span className="mb-1 block text-xs uppercase tracking-wide text-slate-500">
              Transport
            </span>
            <select
              value={transportState}
              onChange={(event) =>
                setTransportState(
                  event.target.value as BroadcastTransportState,
                )
              }
              className="w-full rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-slate-100"
            >
              <option value="OFFLINE">OFFLINE</option>
              <option value="CONNECTING">CONNECTING</option>
              <option value="READY">READY</option>
              <option value="LIVE">LIVE</option>
              <option value="ERROR">ERROR</option>
            </select>
          </label>

          <label className="text-sm text-slate-300">
            <span className="mb-1 block text-xs uppercase tracking-wide text-slate-500">
              Overlay
            </span>
            <select
              value={overlayState}
              onChange={(event) =>
                setOverlayState(
                  event.target.value as BroadcastOverlayState,
                )
              }
              className="w-full rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-slate-100"
            >
              <option value="DISABLED">DISABLED</option>
              <option value="READY">READY</option>
              <option value="ACTIVE">ACTIVE</option>
            </select>
          </label>
        </div>

        <div className="mt-4 grid gap-3 md:grid-cols-2">
          {[
            [
              "Broadcast operator assigned",
              operatorAssigned,
              setOperatorAssigned,
            ],
            [
              "Game start authorized",
              gameAuthorized,
              setGameAuthorized,
            ],
            [
              "Game currently live",
              gameLive,
              setGameLive,
            ],
            [
              "Stream destination configured",
              streamKeyConfigured,
              setStreamKeyConfigured,
            ],
          ].map(([label, checked, setter]) => (
            <label
              key={String(label)}
              className="flex items-center gap-3 rounded-lg border border-slate-800 bg-slate-950/40 px-3 py-2 text-sm text-slate-300"
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
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            Blockers
          </div>

          <div className="mt-3 space-y-2">
            {summary.blockers.length === 0 ? (
              <div className="text-sm text-emerald-300">
                No broadcast blockers.
              </div>
            ) : (
              summary.blockers.map((blocker) => (
                <div
                  key={blocker}
                  className="rounded-lg border border-red-900/50 bg-red-950/20 px-3 py-2 text-xs text-red-300"
                >
                  {blocker}
                </div>
              ))
            )}
          </div>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            Warnings
          </div>

          <div className="mt-3 space-y-2">
            {summary.warnings.length === 0 ? (
              <div className="text-sm text-slate-400">
                No broadcast warnings.
              </div>
            ) : (
              summary.warnings.map((warning) => (
                <div
                  key={warning}
                  className="rounded-lg border border-amber-900/50 bg-amber-950/20 px-3 py-2 text-xs text-amber-200"
                >
                  {warning}
                </div>
              ))
            )}
          </div>
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Ready
          </div>
          <div className="mt-2 text-xl font-bold text-slate-100">
            {summary.ready ? "YES" : "NO"}
          </div>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Can go live
          </div>
          <div className="mt-2 text-xl font-bold text-slate-100">
            {summary.canGoLive ? "YES" : "NO"}
          </div>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Overlay eligible
          </div>
          <div className="mt-2 text-xl font-bold text-slate-100">
            {summary.overlayEligible ? "YES" : "NO"}
          </div>
        </div>
      </div>
    </section>
  );
}
EOF

cat > "$PAGE" <<'EOF'
import { TournamentBroadcastOperatorPanel } from "../../../components/tournament/TournamentBroadcastOperatorPanel";

export default function TournamentBroadcastPage() {
  return (
    <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
      <div className="mb-6">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          SportsOS Broadcast Operations
        </div>

        <h1 className="mt-2 text-3xl font-bold text-slate-100">
          Broadcast Operator
        </h1>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Validate per-game streaming readiness before connecting an
          external transport such as OBS, RTMP, or another broadcast backend.
        </p>
      </div>

      <TournamentBroadcastOperatorPanel />
    </main>
  );
}
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 9.2 broadcast session API / operator UI", () => {
  it("provides a broadcast session API route", () => {
    const route = fs.readFileSync(
      new URL(
        "../app/api/tournament/broadcast/session/route.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain("buildBroadcastSessionSummary");
    expect(route).toContain("gameId is required");
  });

  it("renders the broadcast operator panel", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentBroadcastOperatorPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="broadcast-operator-panel"',
    );
    expect(component).toContain("Can go live");
    expect(component).toContain("Overlay eligible");
  });

  it("provides the tournament broadcast page", () => {
    const page = fs.readFileSync(
      new URL(
        "../app/tournament/broadcast/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain("Broadcast Operator");
    expect(page).toContain(
      "TournamentBroadcastOperatorPanel",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 9.2 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - GET /api/tournament/broadcast/session"
echo "  - /tournament/broadcast"
echo "  - broadcast operator readiness panel"
echo "  - transport and overlay state controls"
echo "  - blockers / warnings visibility"
echo "  - can-go-live and overlay eligibility indicators"
echo "  - Milestone 9.2 tests"
echo
echo "Important:"
echo "  - this does NOT control OBS/RTMP yet"
echo "  - this is the operator/readiness layer only"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Next after green:"
echo "  Milestone 9.3 - Broadcast Overlay Data Contract"
