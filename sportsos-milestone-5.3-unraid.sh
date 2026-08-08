#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PAGE="apps/dashboard/app/games/[id]/control/page.tsx"
CSS="apps/dashboard/app/games/[id]/control/scorekeeper.module.css"
TEST="apps/api/test/scorekeeper-console-contract.test.ts"

for f in "$PAGE" "$CSS" "$TEST"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing expected 5.2 file: $f" >&2
    exit 1
  fi
done

if ! grep -q 'Roster entry from Scorekeeper Console' "$PAGE"; then
  echo "Milestone 5.2 roster-aware goal entry was not detected." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/5.3-${STAMP}"

for f in "$PAGE" "$CSS" "$TEST"; do
  mkdir -p "$BACKUP_DIR/$(dirname "$f")"
  cp "$f" "$BACKUP_DIR/$f"
done

node <<'NODE'
const fs = require("fs");
const path = "apps/dashboard/app/games/[id]/control/page.tsx";
let text = fs.readFileSync(path, "utf8");

function replaceOnce(oldText, newText, label) {
  if (!text.includes(oldText)) {
    throw new Error(`Could not find ${label}`);
  }
  text = text.replace(oldText, newText);
}

replaceOnce(
`interface Device {
  id: number;`,
`interface ActivePenalty {
  id: number;
  gameEventId: number;
  gameId: number;
  side: "home" | "away";
  playerName: string | null;
  jerseyNumber: number | null;
  infraction: string;
  originalDurationMs: number;
  remainingMs: number;
  running: boolean;
  startedAt: string | null;
  createdAt: string;
}

interface Device {
  id: number;`,
"active penalty interface",
);

replaceOnce(
`  const [players, setPlayers] = useState<PlayerOption[]>([]);
  const [devices, setDevices] = useState<Device[]>([]);
  const [goalSide, setGoalSide] = useState<"home" | "away" | null>(null);`,
`  const [players, setPlayers] = useState<PlayerOption[]>([]);
  const [activePenalties, setActivePenalties] = useState<ActivePenalty[]>([]);
  const [devices, setDevices] = useState<Device[]>([]);
  const [goalSide, setGoalSide] = useState<"home" | "away" | null>(null);
  const [penaltySide, setPenaltySide] = useState<"home" | "away" | null>(null);
  const [penaltyPlayerId, setPenaltyPlayerId] = useState("");
  const [penaltyCode, setPenaltyCode] = useState("Tripping");
  const [penaltyMinutes, setPenaltyMinutes] = useState("2");`,
"penalty state",
);

replaceOnce(
`      const [gameResponse, eventResponse, playerResponse, deviceResponse] = await Promise.all([
        api<{ game: Game }>(\`/games/\${gameId}\`),
        api<{ events: GameEvent[] }>(\`/games/\${gameId}/events\`),
        api<{ players: PlayerOption[] }>(\`/games/\${gameId}/event-players\`),
        api<{ devices: Device[] }>("/scoreboard-devices"),
      ]);

      setGame(gameResponse.game);
      setEvents(eventResponse.events);
      setPlayers(playerResponse.players);`,
`      const [
        gameResponse,
        eventResponse,
        playerResponse,
        penaltyResponse,
        deviceResponse,
      ] = await Promise.all([
        api<{ game: Game }>(\`/games/\${gameId}\`),
        api<{ events: GameEvent[] }>(\`/games/\${gameId}/events\`),
        api<{ players: PlayerOption[] }>(\`/games/\${gameId}/event-players\`),
        api<{ penalties: ActivePenalty[] }>(\`/games/\${gameId}/penalties\`),
        api<{ devices: Device[] }>("/scoreboard-devices"),
      ]);

      setGame(gameResponse.game);
      setEvents(eventResponse.events);
      setPlayers(playerResponse.players);
      setActivePenalties(penaltyResponse.penalties);`,
"load active penalties",
);

replaceOnce(
`  async function addEvent(
    type: "PENALTY",
    side: "home" | "away",
  ): Promise<void> {
    if (!game || !canScore) return;

    setBusy(true);
    setError("");

    try {
      await api(\`/games/\${game.id}/events\`, {
        method: "POST",
        body: JSON.stringify({
          type,
          side,
          playerId: null,
          penaltyCode: "MINOR",
          penaltyMinutes: 2,
          notes: "Quick entry from Scorekeeper Console",
        }),
      });

      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not record event.");
    } finally {
      setBusy(false);
    }
  }`,
`  function openPenalty(side: "home" | "away"): void {
    setPenaltySide(side);
    setPenaltyPlayerId("");
    setPenaltyCode("Tripping");
    setPenaltyMinutes("2");
    setError("");
  }

  async function recordPenalty(): Promise<void> {
    if (!game || !penaltySide || !canScore) return;

    const minutes = Number(penaltyMinutes);
    if (!Number.isInteger(minutes) || minutes < 1 || minutes > 20) {
      setError("Penalty duration must be between 1 and 20 minutes.");
      return;
    }

    setBusy(true);
    setError("");

    try {
      await api(\`/games/\${game.id}/events\`, {
        method: "POST",
        body: JSON.stringify({
          type: "PENALTY",
          side: penaltySide,
          playerId: penaltyPlayerId || null,
          penaltyCode,
          penaltyMinutes: minutes,
          notes: "Roster penalty from Scorekeeper Console",
        }),
      });

      setPenaltySide(null);
      setPenaltyPlayerId("");
      setPenaltyCode("Tripping");
      setPenaltyMinutes("2");
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not record penalty.");
    } finally {
      setBusy(false);
    }
  }

  async function clearActivePenalty(penaltyId: number): Promise<void> {
    if (!game || !canScore) return;
    if (!window.confirm("Clear this active penalty?")) return;

    setBusy(true);
    setError("");

    try {
      await api(\`/games/\${game.id}/penalties/\${penaltyId}\`, {
        method: "DELETE",
      });
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not clear penalty.");
    } finally {
      setBusy(false);
    }
  }`,
"penalty workflow functions",
);

text = text.replaceAll(
`onClick={() => void addEvent("PENALTY", "home")}`,
`onClick={() => openPenalty("home")}`,
);
text = text.replaceAll(
`onClick={() => void addEvent("PENALTY", "away")}`,
`onClick={() => openPenalty("away")}`,
);

replaceOnce(
`  const assist2Players = goalPlayers.filter(
    (player) => String(player.id) !== scorerId && String(player.id) !== assist1Id,
  );`,
`  const assist2Players = goalPlayers.filter(
    (player) => String(player.id) !== scorerId && String(player.id) !== assist1Id,
  );
  const penaltyTeamId =
    penaltySide === "home"
      ? game.homeTeamId
      : penaltySide === "away"
        ? game.awayTeamId
        : null;
  const penaltyPlayers = players.filter((player) => player.teamId === penaltyTeamId);
  const visiblePenalties = activePenalties
    .map((penalty) => ({
      ...penalty,
      displayedRemainingMs: effectiveClock(
        penalty.remainingMs,
        penalty.running,
        penalty.startedAt,
        now,
      ),
    }))
    .filter((penalty) => penalty.displayedRemainingMs > 0);`,
"penalty calculations",
);

replaceOnce(
`        {goalSide ? (`,
`        {penaltySide ? (
          <div
            className={styles.modalBackdrop}
            role="presentation"
            onMouseDown={(event) => {
              if (event.target === event.currentTarget && !busy) setPenaltySide(null);
            }}
          >
            <section
              className={styles.goalModal}
              role="dialog"
              aria-modal="true"
              aria-label="Record penalty"
            >
              <div className={styles.modalHeader}>
                <div>
                  <span className={styles.eyebrow}>Record penalty</span>
                  <h2>{sideLabel(game, penaltySide)}</h2>
                </div>
                <button
                  type="button"
                  className={styles.closeButton}
                  disabled={busy}
                  onClick={() => setPenaltySide(null)}
                >
                  ×
                </button>
              </div>

              {penaltyTeamId === null ? (
                <p className={styles.modalNotice}>
                  External team: you can record this penalty without assigning a roster player.
                </p>
              ) : penaltyPlayers.length === 0 ? (
                <p className={styles.modalNotice}>
                  No eligible roster players were returned for this team.
                </p>
              ) : null}

              <div className={styles.goalFields}>
                <label>
                  <span>Player</span>
                  <select
                    value={penaltyPlayerId}
                    onChange={(event) => setPenaltyPlayerId(event.target.value)}
                  >
                    <option value="">Unassigned</option>
                    {penaltyPlayers.map((player) => (
                      <option key={player.id} value={player.id}>
                        {playerLabel(player)}
                      </option>
                    ))}
                  </select>
                </label>

                <label>
                  <span>Infraction</span>
                  <select
                    value={penaltyCode}
                    onChange={(event) => setPenaltyCode(event.target.value)}
                  >
                    {[
                      "Tripping",
                      "Hooking",
                      "Holding",
                      "Interference",
                      "Slashing",
                      "Cross-checking",
                      "Roughing",
                      "High-sticking",
                      "Elbowing",
                      "Boarding",
                      "Charging",
                      "Unsportsmanlike conduct",
                      "Too many players",
                      "Delay of game",
                    ].map((code) => (
                      <option key={code} value={code}>
                        {code}
                      </option>
                    ))}
                  </select>
                </label>

                <label>
                  <span>Duration</span>
                  <select
                    value={penaltyMinutes}
                    onChange={(event) => setPenaltyMinutes(event.target.value)}
                  >
                    {[1, 2, 4, 5, 10].map((minutes) => (
                      <option key={minutes} value={minutes}>
                        {minutes}:00
                      </option>
                    ))}
                  </select>
                </label>
              </div>

              <div className={styles.goalSummary}>
                <strong>{penaltyCode} · {penaltyMinutes}:00</strong>
                <span>
                  {penaltyPlayerId
                    ? playerLabel(
                        penaltyPlayers.find(
                          (player) => String(player.id) === penaltyPlayerId,
                        )!,
                      )
                    : "Unassigned player"}
                </span>
              </div>

              <div className={styles.modalActions}>
                <button
                  type="button"
                  className={styles.confirmPenaltyButton}
                  disabled={busy}
                  onClick={() => void recordPenalty()}
                >
                  {busy ? "SAVING…" : "CONFIRM PENALTY"}
                </button>
                <button
                  type="button"
                  className={styles.cancelButton}
                  disabled={busy}
                  onClick={() => setPenaltySide(null)}
                >
                  CANCEL
                </button>
              </div>
            </section>
          </div>
        ) : null}

        {goalSide ? (`,
"penalty modal",
);

replaceOnce(
`        <section className={styles.lowerGrid}>`,
`        {visiblePenalties.length > 0 ? (
          <section className={styles.activePenaltyStrip}>
            <div className={styles.penaltyStripHeader}>
              <div>
                <span className={styles.eyebrow}>Live penalties</span>
                <h2>Penalty clocks</h2>
              </div>
              <strong>{visiblePenalties.length} active</strong>
            </div>

            <div className={styles.penaltyCards}>
              {visiblePenalties.map((penalty) => (
                <article className={styles.activePenaltyCard} key={penalty.id}>
                  <div>
                    <span className={styles.side}>{sideLabel(game, penalty.side)}</span>
                    <strong>
                      {penalty.jerseyNumber != null ? \`#\${penalty.jerseyNumber} \` : ""}
                      {penalty.playerName || "Unassigned"}
                    </strong>
                    <span>{penalty.infraction}</span>
                  </div>

                  <strong className={styles.penaltyClock}>
                    {formatClock(penalty.displayedRemainingMs)}
                  </strong>

                  <div className={styles.penaltyCardActions}>
                    <span className={penalty.running ? styles.good : styles.neutral}>
                      {penalty.running ? "RUNNING" : "PAUSED"}
                    </span>
                    <button
                      type="button"
                      disabled={!canScore || busy}
                      onClick={() => void clearActivePenalty(penalty.id)}
                    >
                      CLEAR
                    </button>
                  </div>
                </article>
              ))}
            </div>
          </section>
        ) : null}

        <section className={styles.lowerGrid}>`,
"active penalty strip",
);

fs.writeFileSync(path, text);
NODE

cat >> "$CSS" <<'EOF'

.confirmPenaltyButton {
  min-height: 58px;
  border: 0;
  border-radius: 13px;
  background: #854d0e;
  color: white;
  font-weight: 900;
  cursor: pointer;
}

.activePenaltyStrip {
  margin: 16px 0;
  border: 1px solid rgba(245, 158, 11, 0.28);
  border-radius: 18px;
  padding: 16px;
  background: rgba(69, 26, 3, 0.36);
}

.penaltyStripHeader {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.penaltyStripHeader h2 {
  margin: 2px 0 0;
}

.penaltyCards {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  gap: 10px;
  margin-top: 12px;
}

.activePenaltyCard {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 12px;
  align-items: center;
  padding: 13px;
  border: 1px solid rgba(245, 158, 11, 0.2);
  border-radius: 14px;
  background: rgba(15, 23, 42, 0.8);
}

.activePenaltyCard > div:first-child {
  display: grid;
  gap: 3px;
}

.penaltyClock {
  font-variant-numeric: tabular-nums;
  font-size: 2rem;
  color: #fde68a;
}

.penaltyCardActions {
  grid-column: 1 / -1;
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
}

.penaltyCardActions button {
  min-height: 38px;
  padding: 7px 13px;
  border: 1px solid rgba(248, 113, 113, 0.35);
  border-radius: 9px;
  background: #451a03;
  color: #fed7aa;
  font-weight: 800;
}
EOF

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
    expect(source).toContain('action: "startClock"');
    expect(source).toContain('action: "pauseClock"');
  });

  it("loads roster-aware event players for the active game", () => {
    expect(source).toContain("`/games/${gameId}/event-players`");
    expect(source).toContain("setPlayers(playerResponse.players)");
  });

  it("records roster-aware goals as game events", () => {
    expect(source).toContain("assist1PlayerId: assist1Id || null");
    expect(source).toContain("assist2PlayerId: assist2Id || null");
    expect(source).toContain("playerId: scorerId || null");
  });

  it("records roster-aware penalties through the game-event path", () => {
    expect(source).toContain('type: "PENALTY"');
    expect(source).toContain("playerId: penaltyPlayerId || null");
    expect(source).toContain("penaltyCode");
    expect(source).toContain("penaltyMinutes: minutes");
    expect(source).toContain('"Roster penalty from Scorekeeper Console"');
  });

  it("offers common hockey penalty choices and supported durations", () => {
    expect(source).toContain('"Tripping"');
    expect(source).toContain('"Hooking"');
    expect(source).toContain('"Interference"');
    expect(source).toContain('"High-sticking"');
    expect(source).toContain("[1, 2, 4, 5, 10]");
  });

  it("loads and renders authoritative active penalty clocks", () => {
    expect(source).toContain("`/games/${gameId}/penalties`");
    expect(source).toContain("setActivePenalties(penaltyResponse.penalties)");
    expect(source).toContain("displayedRemainingMs");
    expect(source).toContain("Penalty clocks");
  });

  it("clears active penalties through the existing penalty endpoint", () => {
    expect(source).toContain("`/games/${game.id}/penalties/${penaltyId}`");
    expect(source).toContain('"Clear this active penalty?"');
  });

  it("uses the event void route for undo instead of subtracting score", () => {
    expect(source).toContain("`/games/${game.id}/events/${last.id}`");
    expect(source).toContain('method: "DELETE"');
  });

  it("subscribes to realtime game, event, penalty, and device updates", () => {
    expect(source).toContain('"game:event-created"');
    expect(source).toContain('"game:event-voided"');
    expect(source).toContain('"game:penalties-updated"');
    expect(source).toContain('"scoreboard-device:status"');
  });
});
EOF

echo
echo "============================================="
echo " SportsOS Milestone 5.3"
echo " Roster-Aware Penalty Workflow"
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
echo "Penalty flow:"
echo "  PENALTY"
echo "    -> player"
echo "    -> infraction"
echo "    -> duration"
echo "    -> confirm"
echo
echo "Added:"
echo "  live active-penalty clocks"
echo "  running/paused state"
echo "  player + jersey display"
echo "  clear active penalty control"
echo "  external-team unassigned support"
echo
echo "Run:"
echo "  npm run typecheck"
echo "  npm test"
echo "  npm run build"
