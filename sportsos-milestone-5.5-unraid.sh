#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PAGE="apps/dashboard/app/games/[id]/control/page.tsx"
CSS="apps/dashboard/app/games/[id]/control/scorekeeper.module.css"
TEST="apps/api/test/scorekeeper-console-contract.test.ts"

for f in "$PAGE" "$CSS" "$TEST"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing expected 5.4 file: $f" >&2
    exit 1
  fi
done

if ! grep -q 'Game-day readiness' "$PAGE"; then
  echo "Milestone 5.4 readiness workflow was not detected." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/5.5-${STAMP}"

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

if (!text.includes("async function finishGame(): Promise<void>")) {
  insertBefore(
    "  async function startGame(): Promise<void> {",
`  async function finishGame(): Promise<void> {
    if (!game || !canScore) return;

    setBusy(true);
    setError("");

    try {
      const response = await api<{ game: Game }>(\`/games/\${game.id}/lifecycle\`, {
        method: "POST",
        body: JSON.stringify({
          command: "finishGame",
          commandId: crypto.randomUUID(),
        }),
      });

      setGame(response.game);
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not finish game.");
    } finally {
      setBusy(false);
    }
  }

`,
    "startGame function marker",
  );
}

if (!text.includes("const goalEvents = activeEvents.filter")) {
  const marker = `  const pregameVisible =
    game.status === "SCHEDULED" || game.gamePhase === "PREGAME";`;

  if (!text.includes(marker)) throw new Error("Could not find pregameVisible marker");

  text = text.replace(
    marker,
`${marker}

  const goalEvents = activeEvents.filter((event) => event.type === "GOAL");
  const penaltyEvents = activeEvents.filter((event) => event.type === "PENALTY");
  const homeGoals = goalEvents.filter((event) => event.side === "home");
  const awayGoals = goalEvents.filter((event) => event.side === "away");
  const homePenalties = penaltyEvents.filter((event) => event.side === "home");
  const awayPenalties = penaltyEvents.filter((event) => event.side === "away");

  const finalGame = game.status === "FINAL" || game.gamePhase === "FINAL";
  const canFinishGame =
    canScore &&
    !busy &&
    !finalGame &&
    game.status === "LIVE" &&
    !game.clockRunning &&
    !game.intermissionRunning;`,
  );
}

if (!text.includes("Postgame summary")) {
  const marker = `        {pregameVisible ? (`;
  if (!text.includes(marker)) throw new Error("Could not find pregame panel marker");

  const panel = `        {finalGame ? (
          <section className={styles.postgamePanel}>
            <div className={styles.postgameHeader}>
              <div>
                <span className={styles.eyebrow}>Postgame</span>
                <h2>Postgame summary</h2>
                <p>
                  Game state is FINAL. Clock controls and scoring are closed for normal operation.
                </p>
              </div>
              <div className={styles.finalBadge}>FINAL</div>
            </div>

            <div className={styles.finalScore}>
              <div>
                <span>HOME</span>
                <strong>{game.homeTeamName}</strong>
                <b>{game.homeScore}</b>
              </div>
              <span className={styles.finalDivider}>—</span>
              <div>
                <span>AWAY</span>
                <strong>{game.awayTeamName}</strong>
                <b>{game.awayScore}</b>
              </div>
            </div>

            <div className={styles.postgameStats}>
              <article>
                <span>Goals</span>
                <strong>{goalEvents.length}</strong>
                <small>{homeGoals.length} home · {awayGoals.length} away</small>
              </article>
              <article>
                <span>Penalties</span>
                <strong>{penaltyEvents.length}</strong>
                <small>{homePenalties.length} home · {awayPenalties.length} away</small>
              </article>
              <article>
                <span>Recorded events</span>
                <strong>{activeEvents.length}</strong>
                <small>Non-voided game events</small>
              </article>
              <article>
                <span>Active penalties</span>
                <strong>{visiblePenalties.length}</strong>
                <small>{visiblePenalties.length === 0 ? "All cleared" : "Review before leaving"}</small>
              </article>
            </div>

            <div className={styles.postgameColumns}>
              <div>
                <h3>Scoring recap</h3>
                {goalEvents.length === 0 ? (
                  <p className={styles.muted}>No goals recorded.</p>
                ) : (
                  goalEvents.map((event) => (
                    <div className={styles.recapRow} key={event.id}>
                      <div>
                        <strong>{sideLabel(game, event.side)}</strong>
                        <span>P{event.period} · {formatClock(event.clockRemainingMs)}</span>
                      </div>
                      <div>
                        <strong>
                          {event.playerName
                            ? \`\${event.playerJerseyNumber ? \`#\${event.playerJerseyNumber} \` : ""}\${event.playerName}\`
                            : "Unassigned scorer"}
                        </strong>
                      </div>
                    </div>
                  ))
                )}
              </div>

              <div>
                <h3>Penalty recap</h3>
                {penaltyEvents.length === 0 ? (
                  <p className={styles.muted}>No penalties recorded.</p>
                ) : (
                  penaltyEvents.map((event) => (
                    <div className={styles.recapRow} key={event.id}>
                      <div>
                        <strong>{sideLabel(game, event.side)}</strong>
                        <span>P{event.period} · {formatClock(event.clockRemainingMs)}</span>
                      </div>
                      <div>
                        <strong>{event.penaltyCode || "Penalty"}</strong>
                        <span>{event.penaltyMinutes ?? 0}:00</span>
                      </div>
                    </div>
                  ))
                )}
              </div>
            </div>

            <div className={styles.postgameLinks}>
              <Link href={\`/games/\${game.id}/scoreboard\`}>Public scoreboard</Link>
              <Link href={\`/games/\${game.id}/overlay\`}>Broadcast overlay</Link>
              <a
                href={\`\${API}/system/game-engine/games/\${game.id}/diagnostics\`}
                target="_blank"
                rel="noreferrer"
              >
                Engine diagnostics
              </a>
              <Link href="/games">Return to games</Link>
            </div>
          </section>
        ) : null}

`;

  insertBefore(marker, panel, "pregame panel marker");
}

if (!text.includes("FINISH GAME")) {
  const marker = `        <section className={styles.utilityBar}>`;
  if (!text.includes(marker)) throw new Error("Could not find utility bar marker");

  const finish = `        {!finalGame && game.status === "LIVE" ? (
          <section className={styles.finishGamePanel}>
            <div>
              <span className={styles.eyebrow}>Game completion</span>
              <h2>Close out this game</h2>
              <p>
                Pause the game clock and confirm the final score before finishing.
              </p>
            </div>

            <button
              type="button"
              className={styles.finishGameButton}
              disabled={!canFinishGame}
              onClick={() => {
                if (
                  window.confirm(
                    \`Finish game as FINAL? \${game.homeTeamName} \${game.homeScore} - \${game.awayScore} \${game.awayTeamName}\`,
                  )
                ) {
                  void finishGame();
                }
              }}
            >
              {busy ? "FINISHING…" : "FINISH GAME"}
            </button>
          </section>
        ) : null}

`;

  insertBefore(marker, finish, "utility bar marker");
}

fs.writeFileSync(path, text);
NODE

if ! grep -q '^\.postgamePanel {' "$CSS"; then
cat >> "$CSS" <<'EOF'

.finishGamePanel,
.postgamePanel {
  margin: 16px 0;
  border-radius: 18px;
  padding: 18px;
  background: rgba(15, 23, 42, 0.92);
}

.finishGamePanel {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 18px;
  border: 1px solid rgba(248, 113, 113, 0.28);
}

.finishGamePanel h2,
.postgameHeader h2 {
  margin: 3px 0 5px;
}

.finishGamePanel p,
.postgameHeader p {
  margin: 0;
  color: #94a3b8;
}

.finishGameButton {
  min-width: 180px;
  min-height: 58px;
  border: 0;
  border-radius: 14px;
  background: #7f1d1d;
  color: white;
  font-weight: 900;
  cursor: pointer;
}

.postgamePanel {
  border: 1px solid rgba(34, 197, 94, 0.28);
}

.postgameHeader {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 16px;
}

.finalBadge {
  min-width: 110px;
  border-radius: 999px;
  padding: 10px 16px;
  text-align: center;
  background: rgba(22, 101, 52, 0.52);
  color: #bbf7d0;
  font-weight: 900;
  letter-spacing: 0.1em;
}

.finalScore {
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  align-items: center;
  gap: 20px;
  margin-top: 20px;
  padding: 18px;
  border-radius: 16px;
  background: rgba(2, 6, 23, 0.45);
}

.finalScore > div {
  display: grid;
  gap: 4px;
  text-align: center;
}

.finalScore > div span {
  color: #94a3b8;
  font-size: 0.75rem;
  font-weight: 900;
  letter-spacing: 0.12em;
}

.finalScore > div strong {
  font-size: 1.2rem;
}

.finalScore > div b {
  font-size: 3.6rem;
  line-height: 1;
}

.finalDivider {
  color: #64748b;
  font-size: 2rem;
}

.postgameStats {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 10px;
  margin-top: 14px;
}

.postgameStats article {
  display: grid;
  gap: 4px;
  padding: 13px;
  border-radius: 13px;
  background: rgba(30, 41, 59, 0.78);
}

.postgameStats article span,
.postgameStats article small {
  color: #94a3b8;
}

.postgameStats article strong {
  font-size: 1.8rem;
}

.postgameColumns {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 14px;
  margin-top: 16px;
}

.postgameColumns > div {
  border: 1px solid rgba(148, 163, 184, 0.14);
  border-radius: 14px;
  padding: 14px;
}

.postgameColumns h3 {
  margin: 0 0 8px;
}

.recapRow {
  display: flex;
  justify-content: space-between;
  gap: 16px;
  padding: 9px 0;
  border-bottom: 1px solid rgba(148, 163, 184, 0.1);
}

.recapRow:last-child {
  border-bottom: 0;
}

.recapRow > div {
  display: grid;
  gap: 2px;
}

.recapRow > div:last-child {
  text-align: right;
}

.recapRow span {
  color: #94a3b8;
  font-size: 0.84rem;
}

.postgameLinks {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin-top: 16px;
}

.postgameLinks a {
  border: 1px solid rgba(96, 165, 250, 0.28);
  border-radius: 10px;
  padding: 10px 12px;
  color: #bfdbfe;
  text-decoration: none;
  background: rgba(30, 41, 59, 0.75);
}

@media (max-width: 850px) {
  .finishGamePanel,
  .postgameHeader {
    flex-direction: column;
    align-items: stretch;
  }

  .postgameStats,
  .postgameColumns {
    grid-template-columns: 1fr 1fr;
  }
}

@media (max-width: 560px) {
  .finalScore {
    grid-template-columns: 1fr auto 1fr;
    gap: 8px;
  }

  .finalScore > div b {
    font-size: 2.6rem;
  }

  .postgameStats,
  .postgameColumns {
    grid-template-columns: 1fr;
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
  it("starts games through the authoritative lifecycle endpoint", () => {
    expect(source).toContain("`/games/${game.id}/lifecycle`");
    expect(source).toContain('command: "startGame"');
    expect(source).toContain("commandId: crypto.randomUUID()");
  });

  it("finishes games through the authoritative lifecycle endpoint", () => {
    expect(source).toContain('command: "finishGame"');
    expect(source).toContain("FINISH GAME");
    expect(source).toContain("Finish game as FINAL?");
  });

  it("requires a paused live game before normal finish", () => {
    expect(source).toContain("const canFinishGame =");
    expect(source).toContain('game.status === "LIVE"');
    expect(source).toContain("!game.clockRunning");
    expect(source).toContain("!game.intermissionRunning");
  });

  it("renders a postgame final score and recap", () => {
    expect(source).toContain("Postgame summary");
    expect(source).toContain("Scoring recap");
    expect(source).toContain("Penalty recap");
    expect(source).toContain("Non-voided game events");
  });

  it("uses only non-voided events for postgame counts", () => {
    expect(source).toContain("const activeEvents = events.filter((event) => !event.voidedAt)");
    expect(source).toContain('activeEvents.filter((event) => event.type === "GOAL")');
    expect(source).toContain('activeEvents.filter((event) => event.type === "PENALTY")');
  });

  it("links postgame operators to scoreboard overlay and diagnostics", () => {
    expect(source).toContain("Public scoreboard");
    expect(source).toContain("Broadcast overlay");
    expect(source).toContain("/system/game-engine/games/${game.id}/diagnostics");
    expect(source).toContain("Engine diagnostics");
  });

  it("preserves pregame readiness and roster-aware workflows", () => {
    expect(source).toContain("Game-day readiness");
    expect(source).toContain("assist1PlayerId: assist1Id || null");
    expect(source).toContain("playerId: penaltyPlayerId || null");
    expect(source).toContain("Penalty clocks");
  });
});
EOF

echo
echo "============================================="
echo " SportsOS Milestone 5.5"
echo " Game Completion & Postgame Workflow"
echo "============================================="
echo
echo "Modified:"
echo "  $PAGE"
echo "  $CSS"
echo "  $TEST"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Added:"
echo "  controlled FINISH GAME action"
echo "  finishGame lifecycle command + UUID"
echo "  paused-clock finish guard"
echo "  FINAL postgame mode"
echo "  final score summary"
echo "  scoring recap"
echo "  penalty recap"
echo "  active penalty closeout indicator"
echo "  public scoreboard link"
echo "  broadcast overlay link"
echo "  engine diagnostics link"
echo
echo "Run:"
echo "  npm run typecheck"
echo "  npm test"
echo "  npm run build"
