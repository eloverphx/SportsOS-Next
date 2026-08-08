#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

for cmd in bash node npm cp date grep; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
done

PAGE="apps/dashboard/app/system-health/page.tsx"
COMPONENT="apps/dashboard/components/system-health/GameEnginePanel.tsx"
TEST="apps/api/test/game-engine-telemetry-route-shape.test.ts"

if [[ ! -f "$PAGE" ]]; then
  echo "Missing expected dashboard file: $PAGE" >&2
  exit 1
fi

if [[ ! -f "apps/dashboard/lib/authenticated-api.ts" ]]; then
  echo "Missing authenticated API helper." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/2.5-repair-${STAMP}"
mkdir -p "$BACKUP_DIR/$(dirname "$PAGE")"
cp "$PAGE" "$BACKUP_DIR/$PAGE"

mkdir -p "$(dirname "$COMPONENT")"

cat > "$COMPONENT" <<'EOF'
"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { authenticatedFetch } from "../../lib/authenticated-api";

interface GameEngineResponse {
  readonly status: "healthy" | "attention";
  readonly summary: {
    readonly total: number;
    readonly healthy: number;
    readonly transitionPending: number;
    readonly operatorRequired: number;
    readonly warnings: number;
  };
  readonly games: ReadonlyArray<{
    readonly gameId: number;
    readonly organizationId: number;
    readonly matchup: string;
    readonly state: "HEALTHY" | "TRANSITION_PENDING" | "OPERATOR_REQUIRED" | "WARNING";
    readonly status: string;
    readonly gamePhase: string;
    readonly period: number;
    readonly regulationPeriods: number;
    readonly clockRemainingMs: number;
    readonly clockRunning: boolean;
    readonly intermissionRemainingMs: number;
    readonly intermissionRunning: boolean;
    readonly actionRequired: string | null;
    readonly warnings: ReadonlyArray<{
      readonly code: string;
      readonly message: string;
    }>;
  }>;
  readonly recentTransitions: ReadonlyArray<{
    readonly timestamp: string;
    readonly source: "runtime-supervisor" | "system";
    readonly gameId: number;
    readonly action: string;
    readonly outcome: "applied" | "replayed" | "failed";
    readonly detail?: string;
  }>;
}

function formatClock(milliseconds: number): string {
  const totalSeconds = Math.max(0, Math.floor(milliseconds / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

function stateLabel(state: GameEngineResponse["games"][number]["state"]): string {
  switch (state) {
    case "HEALTHY":
      return "Healthy";
    case "TRANSITION_PENDING":
      return "Transition pending";
    case "OPERATOR_REQUIRED":
      return "Operator required";
    case "WARNING":
      return "Warning";
  }
}

export function GameEnginePanel() {
  const [telemetry, setTelemetry] = useState<GameEngineResponse | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);

  const load = useCallback(async (): Promise<void> => {
    setError("");

    try {
      const response = await authenticatedFetch<GameEngineResponse>("/system/game-engine");
      setTelemetry(response);
    } catch (caughtError) {
      setError(
        caughtError instanceof Error
          ? caughtError.message
          : "Could not load game engine telemetry",
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();

    const timer = window.setInterval(() => {
      void load();
    }, 5_000);

    return () => window.clearInterval(timer);
  }, [load]);

  return (
    <section className="panel">
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "flex-start",
          gap: 16,
          flexWrap: "wrap",
        }}
      >
        <div>
          <h2>Active Game Engine</h2>
          <p className="muted">
            Authoritative lifecycle state, automatic transitions, and operator warnings.
          </p>
        </div>

        <button className="secondary" disabled={loading} onClick={() => void load()}>
          {loading ? "Checking…" : "Refresh engine"}
        </button>
      </div>

      {error ? <p className="error">{error}</p> : null}

      {telemetry ? (
        <div className="cards" style={{ marginTop: 16 }}>
          <div className="metric">
            <span>Engine status</span>
            <strong className={telemetry.status === "healthy" ? "online" : "offline"}>
              {telemetry.status === "healthy" ? "Healthy" : "Attention needed"}
            </strong>
          </div>
          <div className="metric">
            <span>Visible games</span>
            <strong>{telemetry.summary.total}</strong>
          </div>
          <div className="metric">
            <span>Transition pending</span>
            <strong>{telemetry.summary.transitionPending}</strong>
          </div>
          <div className="metric">
            <span>Operator required</span>
            <strong>{telemetry.summary.operatorRequired}</strong>
          </div>
          <div className="metric">
            <span>Warnings</span>
            <strong>{telemetry.summary.warnings}</strong>
          </div>
        </div>
      ) : null}

      {!error && !telemetry && loading ? <p className="muted">Loading game engine…</p> : null}

      {telemetry?.games.length === 0 ? (
        <p className="muted">No scheduled or live games are currently visible.</p>
      ) : null}

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(300px, 1fr))",
          gap: 16,
          marginTop: 18,
        }}
      >
        {telemetry?.games.map((game) => (
          <article
            key={game.gameId}
            style={{
              border: "1px solid rgba(148, 163, 184, 0.24)",
              borderRadius: 14,
              padding: 16,
            }}
          >
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "flex-start",
                gap: 12,
              }}
            >
              <div>
                <strong>{game.matchup}</strong>
                <div className="muted" style={{ marginTop: 4 }}>
                  Game #{game.gameId}
                </div>
              </div>
              <strong>{stateLabel(game.state)}</strong>
            </div>

            <div
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
                gap: 12,
                marginTop: 16,
              }}
            >
              <div>
                <span className="muted">Phase</span>
                <div>{game.gamePhase}</div>
              </div>
              <div>
                <span className="muted">Period</span>
                <div>
                  {game.period} / {game.regulationPeriods}
                </div>
              </div>
              <div>
                <span className="muted">Game clock</span>
                <div>
                  {formatClock(game.clockRemainingMs)} {game.clockRunning ? "RUNNING" : "STOPPED"}
                </div>
              </div>
              <div>
                <span className="muted">Intermission</span>
                <div>
                  {formatClock(game.intermissionRemainingMs)}{" "}
                  {game.intermissionRunning ? "RUNNING" : "STOPPED"}
                </div>
              </div>
            </div>

            {game.actionRequired ? (
              <p style={{ marginTop: 14 }}>
                <strong>Action:</strong> {game.actionRequired}
              </p>
            ) : null}

            {game.warnings.length > 0 ? (
              <div style={{ marginTop: 14 }}>
                {game.warnings.map((warning) => (
                  <p className="error" key={warning.code}>
                    <strong>{warning.code}:</strong> {warning.message}
                  </p>
                ))}
              </div>
            ) : null}

            <div
              style={{
                display: "flex",
                gap: 12,
                flexWrap: "wrap",
                marginTop: 16,
              }}
            >
              <Link href={`/games/${game.gameId}/scoreboard`}>Open scoreboard</Link>
              <Link href={`/games/${game.gameId}/overlay`}>Open overlay</Link>
            </div>
          </article>
        ))}
      </div>

      <div style={{ marginTop: 24 }}>
        <h3>Recent engine transitions</h3>

        {telemetry?.recentTransitions.length === 0 ? (
          <p className="muted">No automatic lifecycle transitions recorded yet.</p>
        ) : null}

        <div className="activity">
          {telemetry?.recentTransitions.map((transition, index) => (
            <div
              key={`${transition.timestamp}-${transition.gameId}-${transition.action}-${index}`}
            >
              <b>
                Game #{transition.gameId} — {transition.action}
              </b>
              <span>
                {transition.outcome} · {new Date(transition.timestamp).toLocaleTimeString()}
              </span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
EOF

node <<'NODE'
const fs = require("fs");
const path = "apps/dashboard/app/system-health/page.tsx";
let text = fs.readFileSync(path, "utf8");

// Clean partial declarations inserted by the failed 2.5 installer.
text = text.replace(
  /\nfunction formatEngineClock\(milliseconds: number\): string \{[\s\S]*?\n\}\n/,
  "\n",
);

text = text.replace(
  /\ninterface GameEngineResponse \{[\s\S]*?\n\}\n\n(?=interface ReadyResponse)/,
  "\n",
);

text = text.replace(
  /\n\s*const \[gameEngine, setGameEngine\] = useState<GameEngineResponse \| null>\(null\);\n\s*const \[gameEngineError, setGameEngineError\] = useState<string \| null>\(null\);\n/,
  "\n",
);

// Add standalone component import once.
if (!text.includes('GameEnginePanel')) {
  const importAnchor = 'import { AppShell } from "../../components/AppShell";';

  if (!text.includes(importAnchor)) {
    throw new Error("Could not locate AppShell import in system-health page");
  }

  text = text.replace(
    importAnchor,
    `${importAnchor}
import { GameEnginePanel } from "../../components/system-health/GameEnginePanel";`,
  );
}

// Mount the panel immediately before the existing Platform details panel.
// This avoids relying on the page's loadStatus implementation.
if (!text.includes("<GameEnginePanel />")) {
  const platformPanel = `<section className="panel">
          <h2>Platform details</h2>`;

  if (!text.includes(platformPanel)) {
    // Fallback: mount before the last closing main tag if the page formatting changed.
    const mainClose = text.lastIndexOf("</main>");
    if (mainClose < 0) {
      throw new Error(
        "Could not locate Platform details panel or closing </main> in system-health page",
      );
    }

    text =
      text.slice(0, mainClose) +
      `        <GameEnginePanel />\n\n` +
      text.slice(mainClose);
  } else {
    text = text.replace(
      platformPanel,
      `<GameEnginePanel />

        ${platformPanel}`,
    );
  }
}

fs.writeFileSync(path, text);
NODE

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  classifyEngineGame,
  type EngineTelemetryRow,
} from "../src/modules/games/telemetry.js";

function row(overrides: Partial<EngineTelemetryRow> = {}): EngineTelemetryRow {
  return {
    id: 50,
    organizationId: 9,
    homeTeamName: "Home",
    awayTeamName: "Away",
    status: "LIVE",
    gamePhase: "REGULATION",
    period: 1,
    regulationPeriods: 3,
    clockRemainingMs: 120_000,
    clockRunning: false,
    clockStartedAt: null,
    intermissionRemainingMs: 0,
    intermissionRunning: false,
    intermissionStartedAt: null,
    ...overrides,
  };
}

describe("game engine telemetry dashboard contract", () => {
  it("provides all fields required by the operator dashboard", () => {
    const result = classifyEngineGame(row());

    expect(result).toEqual(
      expect.objectContaining({
        gameId: 50,
        organizationId: 9,
        matchup: "Home vs Away",
        state: "HEALTHY",
        gamePhase: "REGULATION",
        period: 1,
        regulationPeriods: 3,
        clockRemainingMs: 120_000,
        clockRunning: false,
        intermissionRemainingMs: 0,
        intermissionRunning: false,
        actionRequired: null,
        warnings: [],
      }),
    );
  });
});
EOF

echo
echo "============================================="
echo " SportsOS Next - Game Engine 2.5 Repair"
echo " Standalone Active Game Engine Panel"
echo "============================================="
echo
echo "Created:"
echo "  $COMPONENT"
echo "  $TEST"
echo
echo "Repaired/modified:"
echo "  $PAGE"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "The panel now uses authenticatedFetch and refreshes every 5 seconds."
echo
echo "Run:"
echo "  npm run typecheck"
echo "  npm test"
