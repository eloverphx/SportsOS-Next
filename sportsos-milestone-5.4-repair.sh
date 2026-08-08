#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PAGE="apps/dashboard/app/games/[id]/control/page.tsx"
CSS="apps/dashboard/app/games/[id]/control/scorekeeper.module.css"
TEST="apps/api/test/scorekeeper-console-contract.test.ts"

for f in "$PAGE" "$CSS" "$TEST"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing expected file: $f" >&2
    exit 1
  fi
done

if ! grep -q 'Penalty clocks' "$PAGE"; then
  echo "Milestone 5.3 penalty workflow was not detected." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/5.4-repair-${STAMP}"

for f in "$PAGE" "$CSS" "$TEST"; do
  mkdir -p "$BACKUP_DIR/$(dirname "$f")"
  cp "$f" "$BACKUP_DIR/$f"
done

node <<'NODE'
const fs = require("fs");
const path = "apps/dashboard/app/games/[id]/control/page.tsx";
let text = fs.readFileSync(path, "utf8");

function insertBefore(marker, content, label) {
  const index = text.indexOf(marker);
  if (index < 0) throw new Error(`Could not find ${label}`);
  text = text.slice(0, index) + content + text.slice(index);
}

if (!text.includes("async function startGame(): Promise<void>")) {
  insertBefore(
    "  async function horn(): Promise<void> {",
`  async function startGame(): Promise<void> {
    if (!game || !canScore) return;

    setBusy(true);
    setError("");

    try {
      const response = await api<{ game: Game }>(\`/games/\${game.id}/lifecycle\`, {
        method: "POST",
        body: JSON.stringify({
          command: "startGame",
          commandId: crypto.randomUUID(),
        }),
      });

      setGame(response.game);
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not start game.");
    } finally {
      setBusy(false);
    }
  }

`,
    "horn function marker",
  );
}

if (!text.includes("const requiredReadiness = [")) {
  const calcMarker = `  const visiblePenalties = activePenalties
    .map((penalty) => ({
      ...penalty,
      displayedRemainingMs: effectiveClock(
        penalty.remainingMs,
        penalty.running,
        penalty.startedAt,
        now,
      ),
    }))
    .filter((penalty) => penalty.displayedRemainingMs > 0);`;

  if (!text.includes(calcMarker)) {
    throw new Error("Could not find active penalty calculation marker");
  }

  const readiness = `

  const homeRosterCount =
    game.homeTeamId === null
      ? null
      : players.filter((player) => player.teamId === game.homeTeamId).length;
  const awayRosterCount =
    game.awayTeamId === null
      ? null
      : players.filter((player) => player.teamId === game.awayTeamId).length;

  const requiredReadiness = [
    {
      key: "game",
      label: "Game configuration",
      ready: game.status === "SCHEDULED" && game.gamePhase === "PREGAME",
      detail:
        game.status === "SCHEDULED" && game.gamePhase === "PREGAME"
          ? "Scheduled and ready for first puck drop"
          : \`\${game.status} · \${game.gamePhase}\`,
    },
    {
      key: "permission",
      label: "Scorekeeper access",
      ready: canScore,
      detail: canScore ? "GAME_SCORE permission confirmed" : "Scoring permission required",
    },
    {
      key: "realtime",
      label: "Realtime connection",
      ready: socketConnected,
      detail: socketConnected ? "Connected to SportsOS realtime" : "Realtime disconnected",
    },
    {
      key: "home-roster",
      label: \`\${game.homeTeamName} roster\`,
      ready: game.homeTeamId === null || (homeRosterCount ?? 0) > 0,
      detail:
        game.homeTeamId === null
          ? "External team · roster not required"
          : \`\${homeRosterCount ?? 0} eligible players\`,
    },
    {
      key: "away-roster",
      label: \`\${game.awayTeamName} roster\`,
      ready: game.awayTeamId === null || (awayRosterCount ?? 0) > 0,
      detail:
        game.awayTeamId === null
          ? "External team · roster not required"
          : \`\${awayRosterCount ?? 0} eligible players\`,
    },
  ];

  const recommendedReadiness = [
    {
      key: "scoreboard-assigned",
      label: "Scoreboard assigned",
      ready: devices.length > 0,
      detail:
        devices.length > 0
          ? \`\${devices.length} assigned device\${devices.length === 1 ? "" : "s"}\`
          : "No scoreboard assigned · manual operation still available",
    },
    {
      key: "scoreboard-online",
      label: "Scoreboard online",
      ready: devices.length === 0 || onlineDevices > 0,
      detail:
        devices.length === 0
          ? "Not required"
          : \`\${onlineDevices}/\${devices.length} online\`,
    },
    {
      key: "overlay",
      label: "Broadcast overlay",
      ready: true,
      detail: "Game overlay route is available",
    },
    {
      key: "stream",
      label: "Stream telemetry",
      ready: true,
      detail: "Not instrumented yet · does not block game start",
    },
  ];

  const requiredReady = requiredReadiness.every((item) => item.ready);
  const pregameVisible =
    game.status === "SCHEDULED" || game.gamePhase === "PREGAME";`;

  text = text.replace(calcMarker, calcMarker + readiness);
}

if (!text.includes("Game-day readiness")) {
  const panel = `        {pregameVisible ? (
          <section className={styles.readinessPanel}>
            <div className={styles.readinessHeader}>
              <div>
                <span className={styles.eyebrow}>Pregame</span>
                <h2>Game-day readiness</h2>
                <p>
                  Required checks must be green before SportsOS will start the game.
                  Recommended checks can be bypassed when operating manually.
                </p>
              </div>

              <div
                className={
                  requiredReady ? styles.readinessBadgeReady : styles.readinessBadgeBlocked
                }
              >
                {requiredReady ? "READY" : "NOT READY"}
              </div>
            </div>

            <div className={styles.readinessGrid}>
              <div className={styles.readinessGroup}>
                <h3>Required</h3>
                {requiredReadiness.map((item) => (
                  <div className={styles.readinessItem} key={item.key}>
                    <span
                      className={item.ready ? styles.readyDot : styles.blockedDot}
                      aria-hidden="true"
                    />
                    <div>
                      <strong>{item.label}</strong>
                      <span>{item.detail}</span>
                    </div>
                    <b className={item.ready ? styles.good : styles.bad}>
                      {item.ready ? "READY" : "BLOCKED"}
                    </b>
                  </div>
                ))}
              </div>

              <div className={styles.readinessGroup}>
                <h3>Recommended</h3>
                {recommendedReadiness.map((item) => (
                  <div className={styles.readinessItem} key={item.key}>
                    <span
                      className={item.ready ? styles.readyDot : styles.warningDot}
                      aria-hidden="true"
                    />
                    <div>
                      <strong>{item.label}</strong>
                      <span>{item.detail}</span>
                    </div>
                    <b className={item.ready ? styles.good : styles.neutral}>
                      {item.ready ? "OK" : "CHECK"}
                    </b>
                  </div>
                ))}
              </div>
            </div>

            <div className={styles.startGameBar}>
              <div>
                <strong>
                  {requiredReady
                    ? "SportsOS is ready for game operation."
                    : "Resolve required checks before starting."}
                </strong>
                <span>
                  Starting the game uses the authoritative lifecycle engine and a unique command ID.
                </span>
              </div>

              <button
                type="button"
                className={styles.startGameButton}
                disabled={!requiredReady || busy || game.status !== "SCHEDULED"}
                onClick={() => {
                  if (
                    window.confirm(
                      \`Start \${game.homeTeamName} vs \${game.awayTeamName}?\`,
                    )
                  ) {
                    void startGame();
                  }
                }}
              >
                {busy ? "STARTING…" : "START GAME"}
              </button>
            </div>
          </section>
        ) : null}

`;

  insertBefore(`        {!canScore ? (`, panel, "scorekeeper permission warning marker");
}

fs.writeFileSync(path, text);
NODE

if ! grep -q '^\.readinessPanel {' "$CSS"; then
cat >> "$CSS" <<'EOF'

.readinessPanel {
  margin-bottom: 18px;
  border: 1px solid rgba(59, 130, 246, 0.3);
  border-radius: 20px;
  padding: 18px;
  background: rgba(15, 23, 42, 0.92);
}

.readinessHeader {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 18px;
}

.readinessHeader h2 {
  margin: 3px 0 5px;
}

.readinessHeader p {
  max-width: 760px;
  margin: 0;
  color: #94a3b8;
}

.readinessBadgeReady,
.readinessBadgeBlocked {
  flex: 0 0 auto;
  min-width: 120px;
  border-radius: 999px;
  padding: 10px 16px;
  text-align: center;
  font-weight: 900;
  letter-spacing: 0.08em;
}

.readinessBadgeReady {
  background: rgba(22, 101, 52, 0.5);
  color: #bbf7d0;
}

.readinessBadgeBlocked {
  background: rgba(127, 29, 29, 0.5);
  color: #fecaca;
}

.readinessGrid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 14px;
  margin-top: 18px;
}

.readinessGroup {
  border: 1px solid rgba(148, 163, 184, 0.15);
  border-radius: 15px;
  padding: 14px;
  background: rgba(2, 6, 23, 0.38);
}

.readinessGroup h3 {
  margin: 0 0 8px;
  color: #cbd5e1;
}

.readinessItem {
  display: grid;
  grid-template-columns: auto 1fr auto;
  gap: 10px;
  align-items: center;
  padding: 10px 0;
  border-bottom: 1px solid rgba(148, 163, 184, 0.1);
}

.readinessItem:last-child {
  border-bottom: 0;
}

.readinessItem > div {
  display: grid;
  gap: 2px;
}

.readinessItem > div span {
  color: #94a3b8;
  font-size: 0.84rem;
}

.readyDot,
.blockedDot,
.warningDot {
  width: 11px;
  height: 11px;
  border-radius: 50%;
}

.readyDot {
  background: #22c55e;
  box-shadow: 0 0 10px rgba(34, 197, 94, 0.7);
}

.blockedDot {
  background: #ef4444;
  box-shadow: 0 0 10px rgba(239, 68, 68, 0.55);
}

.warningDot {
  background: #f59e0b;
}

.startGameBar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 18px;
  margin-top: 16px;
  padding: 14px;
  border-radius: 15px;
  background: rgba(30, 41, 59, 0.82);
}

.startGameBar > div {
  display: grid;
  gap: 4px;
}

.startGameBar span {
  color: #94a3b8;
  font-size: 0.86rem;
}

.startGameButton {
  min-width: 180px;
  min-height: 62px;
  border: 0;
  border-radius: 14px;
  background: #166534;
  color: white;
  font-weight: 900;
  font-size: 1.08rem;
  cursor: pointer;
}

@media (max-width: 800px) {
  .readinessHeader,
  .startGameBar {
    flex-direction: column;
    align-items: stretch;
  }

  .readinessGrid {
    grid-template-columns: 1fr;
  }

  .startGameButton {
    width: 100%;
  }
}
EOF
fi

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

const source = fs.readFileSync(
  new URL("../../dashboard/app/games/[id]/control/page.tsx", import.meta.url),
  "utf8",
);

describe("scorekeeper console vertical-slice contract", () => {
  it("routes clock mutations through the authoritative scoring endpoint", () => {
    expect(source).toContain("`/games/${game.id}/scoring`");
    expect(source).toContain("crypto.randomUUID()");
  });

  it("starts games through the authoritative lifecycle endpoint", () => {
    expect(source).toContain("`/games/${game.id}/lifecycle`");
    expect(source).toContain('command: "startGame"');
    expect(source).toContain("commandId: crypto.randomUUID()");
    expect(source).toContain("START GAME");
  });

  it("requires core readiness checks before game start", () => {
    expect(source).toContain('key: "game"');
    expect(source).toContain('key: "permission"');
    expect(source).toContain('key: "realtime"');
    expect(source).toContain('key: "home-roster"');
    expect(source).toContain('key: "away-roster"');
    expect(source).toContain("requiredReadiness.every");
  });

  it("exempts external teams from roster readiness requirements", () => {
    expect(source).toContain("External team · roster not required");
  });

  it("treats scoreboard readiness as recommended rather than blocking", () => {
    expect(source).toContain('key: "scoreboard-assigned"');
    expect(source).toContain('key: "scoreboard-online"');
    expect(source).toContain("manual operation still available");
  });

  it("does not fabricate stream connectivity", () => {
    expect(source).toContain('key: "stream"');
    expect(source).toContain("Not instrumented yet · does not block game start");
  });

  it("keeps the roster-aware goal and penalty workflows", () => {
    expect(source).toContain("assist1PlayerId: assist1Id || null");
    expect(source).toContain("playerId: penaltyPlayerId || null");
    expect(source).toContain("Penalty clocks");
  });
});
EOF

echo
echo "============================================="
echo " SportsOS 5.4 Repair"
echo " Game-Day Readiness & Pregame Workflow"
echo "============================================="
echo
echo "Applied idempotent readiness patch."
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck"
echo "  npm test"
echo "  npm run build"
