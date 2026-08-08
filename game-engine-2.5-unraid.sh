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
TEST="apps/api/test/game-engine-telemetry-route-shape.test.ts"

if [[ ! -f "$PAGE" ]]; then
  echo "Missing expected dashboard file: $PAGE" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/2.5-${STAMP}"
mkdir -p "$BACKUP_DIR/$(dirname "$PAGE")"
cp "$PAGE" "$BACKUP_DIR/$PAGE"

node <<'NODE'
const fs = require("fs");
const path = "apps/dashboard/app/system-health/page.tsx";
let text = fs.readFileSync(path, "utf8");

if (!text.includes("interface GameEngineResponse")) {
  const marker = `interface ReadyResponse {`;
  const idx = text.indexOf(marker);
  if (idx < 0) throw new Error("Could not locate ReadyResponse in system-health page");

  const block = `interface GameEngineResponse {
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

`;

  text = text.slice(0, idx) + block + text.slice(idx);
}

if (!text.includes("function formatEngineClock")) {
  const marker = `"use client";`;
  const idx = text.indexOf(marker);
  if (idx < 0) throw new Error("Could not locate use client marker");

  const insertAt = idx + marker.length;
  const helper = `

function formatEngineClock(milliseconds: number): string {
  const totalSeconds = Math.max(0, Math.floor(milliseconds / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return \`\${minutes}:\${String(seconds).padStart(2, "0")}\`;
}
`;

  text = text.slice(0, insertAt) + helper + text.slice(insertAt);
}

if (!text.includes("const [gameEngine")) {
  const stateMarker = `const [`;
  const componentStart = text.indexOf("export default function");
  if (componentStart < 0) throw new Error("Could not locate system-health component");

  const nextState = text.indexOf(stateMarker, componentStart);
  if (nextState < 0) throw new Error("Could not locate first state declaration");

  const lineEnd = text.indexOf("\n", nextState);
  const injection = `
  const [gameEngine, setGameEngine] = useState<GameEngineResponse | null>(null);
  const [gameEngineError, setGameEngineError] = useState<string | null>(null);
`;

  text = text.slice(0, lineEnd + 1) + injection + text.slice(lineEnd + 1);
}

if (!text.includes("/system/game-engine")) {
  const loadMarker = `const load = useCallback(async () => {`;
  const loadIdx = text.indexOf(loadMarker);
  if (loadIdx < 0) throw new Error("Could not locate load callback");

  const bodyStart = text.indexOf("\n", loadIdx) + 1;
  const fetchBlock = `    setGameEngineError(null);

    try {
      const token =
        typeof window !== "undefined" ? window.localStorage.getItem("sportsos.token") : null;
      const response = await fetch(\`\${API}/system/game-engine\`, {
        headers: token ? { Authorization: \`Bearer \${token}\` } : undefined,
      });

      if (!response.ok) {
        throw new Error(\`Game engine telemetry returned HTTP \${response.status}\`);
      }

      setGameEngine((await response.json()) as GameEngineResponse);
    } catch (error) {
      setGameEngineError(error instanceof Error ? error.message : "Could not load game engine telemetry");
    }

`;

  text = text.slice(0, bodyStart) + fetchBlock + text.slice(bodyStart);
}

if (!text.includes("Active Game Engine")) {
  const returnIdx = text.lastIndexOf("return (");
  if (returnIdx < 0) throw new Error("Could not locate return block");

  const closeMain = text.lastIndexOf("</main>");
  const closeShell = text.lastIndexOf("</AppShell>");
  let insertAt = closeMain > returnIdx ? closeMain : closeShell;

  if (insertAt < 0) {
    throw new Error("Could not locate insertion point near end of System Health UI");
  }

  const panel = `
      <section
        style={{
          marginTop: 24,
          border: "1px solid rgba(148, 163, 184, 0.24)",
          borderRadius: 16,
          padding: 20,
        }}
      >
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
            <h2 style={{ margin: 0 }}>Active Game Engine</h2>
            <p style={{ marginTop: 6, opacity: 0.72 }}>
              Authoritative lifecycle state, supervisor activity, and operator warnings.
            </p>
          </div>

          {gameEngine ? (
            <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
              <strong>Total: {gameEngine.summary.total}</strong>
              <span>Healthy: {gameEngine.summary.healthy}</span>
              <span>Pending: {gameEngine.summary.transitionPending}</span>
              <span>Operator: {gameEngine.summary.operatorRequired}</span>
              <span>Warnings: {gameEngine.summary.warnings}</span>
            </div>
          ) : null}
        </div>

        {gameEngineError ? (
          <p style={{ color: "#ef4444" }}>{gameEngineError}</p>
        ) : null}

        {!gameEngineError && !gameEngine ? (
          <p style={{ opacity: 0.7 }}>Loading game engine telemetry…</p>
        ) : null}

        {gameEngine?.games.length === 0 ? (
          <p style={{ opacity: 0.7 }}>No scheduled or live games are currently visible.</p>
        ) : null}

        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit, minmax(300px, 1fr))",
            gap: 16,
            marginTop: 16,
          }}
        >
          {gameEngine?.games.map((game) => (
            <article
              key={game.gameId}
              style={{
                border: "1px solid rgba(148, 163, 184, 0.2)",
                borderRadius: 14,
                padding: 16,
              }}
            >
              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  gap: 12,
                  alignItems: "flex-start",
                }}
              >
                <div>
                  <strong>{game.matchup}</strong>
                  <div style={{ marginTop: 4, opacity: 0.7 }}>
                    Game #{game.gameId}
                  </div>
                </div>
                <span style={{ fontWeight: 700 }}>{game.state}</span>
              </div>

              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
                  gap: 10,
                  marginTop: 16,
                }}
              >
                <div>
                  <div style={{ opacity: 0.65, fontSize: 13 }}>Phase</div>
                  <div>{game.gamePhase}</div>
                </div>
                <div>
                  <div style={{ opacity: 0.65, fontSize: 13 }}>Period</div>
                  <div>
                    {game.period} / {game.regulationPeriods}
                  </div>
                </div>
                <div>
                  <div style={{ opacity: 0.65, fontSize: 13 }}>Game clock</div>
                  <div>
                    {formatEngineClock(game.clockRemainingMs)}{" "}
                    {game.clockRunning ? "RUNNING" : "STOPPED"}
                  </div>
                </div>
                <div>
                  <div style={{ opacity: 0.65, fontSize: 13 }}>Intermission</div>
                  <div>
                    {formatEngineClock(game.intermissionRemainingMs)}{" "}
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
                    <p key={warning.code} style={{ margin: "6px 0", color: "#ef4444" }}>
                      <strong>{warning.code}:</strong> {warning.message}
                    </p>
                  ))}
                </div>
              ) : null}

              <div style={{ display: "flex", gap: 10, marginTop: 16, flexWrap: "wrap" }}>
                <a href={\`/games/\${game.gameId}/scoreboard\`}>Open scoreboard</a>
                <a href={\`/games/\${game.gameId}/overlay\`}>Open overlay</a>
              </div>
            </article>
          ))}
        </div>

        <div style={{ marginTop: 24 }}>
          <h3>Recent engine transitions</h3>

          {gameEngine?.recentTransitions.length === 0 ? (
            <p style={{ opacity: 0.7 }}>No automatic lifecycle transitions recorded yet.</p>
          ) : null}

          <div style={{ display: "grid", gap: 8 }}>
            {gameEngine?.recentTransitions.map((transition, index) => (
              <div
                key={\`\${transition.timestamp}-\${transition.gameId}-\${transition.action}-\${index}\`}
                style={{
                  display: "grid",
                  gridTemplateColumns: "minmax(150px, 1fr) minmax(80px, auto) minmax(100px, auto)",
                  gap: 12,
                  borderBottom: "1px solid rgba(148, 163, 184, 0.15)",
                  paddingBottom: 8,
                }}
              >
                <span>
                  Game #{transition.gameId} — {transition.action}
                </span>
                <span>{transition.outcome}</span>
                <span style={{ opacity: 0.65 }}>
                  {new Date(transition.timestamp).toLocaleTimeString()}
                </span>
              </div>
            ))}
          </div>
        </div>
      </section>
`;

  text = text.slice(0, insertAt) + panel + "\n" + text.slice(insertAt);
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

describe("game engine telemetry dashboard shape", () => {
  it("provides the fields required by the operator dashboard", () => {
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
echo " SportsOS Next - Game Engine 2.5"
echo " Active Game Engine Dashboard"
echo "============================================="
echo
echo "Modified:"
echo "  $PAGE"
echo
echo "Created:"
echo "  $TEST"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck"
echo "  npm test"
