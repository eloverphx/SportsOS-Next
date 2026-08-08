#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PAGE="apps/dashboard/app/games/[id]/control/page.tsx"
CSS="apps/dashboard/app/games/[id]/control/scorekeeper.module.css"
TEST="apps/api/test/scorekeeper-console-contract.test.ts"

for f in "$PAGE" "$CSS" "$TEST"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing expected 5.1 file: $f" >&2
    exit 1
  fi
done

if ! grep -q 'Live scorekeeper' "$PAGE"; then
  echo "Milestone 5.1 scorekeeper console was not detected." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/5.2-${STAMP}"

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
`  seasonName: string;
  homeTeamName: string;
  awayTeamName: string;`,
`  seasonName: string;
  homeTeamId: number | null;
  awayTeamId: number | null;
  homeTeamName: string;
  awayTeamName: string;`,
"game team id fields",
);

replaceOnce(
`interface GameEvent {
  id: number;`,
`interface PlayerOption {
  id: number;
  teamId: number;
  firstName: string;
  lastName: string;
  preferredName: string | null;
  jerseyNumber: number | null;
}

interface GameEvent {
  id: number;`,
"player option interface",
);

replaceOnce(
`function sideLabel(game: Game, side: "home" | "away"): string {
  return side === "home" ? game.homeTeamName : game.awayTeamName;
}`,
`function sideLabel(game: Game, side: "home" | "away"): string {
  return side === "home" ? game.homeTeamName : game.awayTeamName;
}

function playerLabel(player: PlayerOption): string {
  const jersey = player.jerseyNumber == null ? "" : \`#\${player.jerseyNumber} \`;
  return \`\${jersey}\${player.preferredName || player.firstName} \${player.lastName}\`;
}`,
"player label helper",
);

replaceOnce(
`  const [events, setEvents] = useState<GameEvent[]>([]);
  const [devices, setDevices] = useState<Device[]>([]);`,
`  const [events, setEvents] = useState<GameEvent[]>([]);
  const [players, setPlayers] = useState<PlayerOption[]>([]);
  const [devices, setDevices] = useState<Device[]>([]);
  const [goalSide, setGoalSide] = useState<"home" | "away" | null>(null);
  const [scorerId, setScorerId] = useState("");
  const [assist1Id, setAssist1Id] = useState("");
  const [assist2Id, setAssist2Id] = useState("");`,
"scorekeeper state",
);

replaceOnce(
`      const [gameResponse, eventResponse, deviceResponse] = await Promise.all([
        api<{ game: Game }>(\`/games/\${gameId}\`),
        api<{ events: GameEvent[] }>(\`/games/\${gameId}/events\`),
        api<{ devices: Device[] }>("/scoreboard-devices"),
      ]);

      setGame(gameResponse.game);
      setEvents(eventResponse.events);`,
`      const [gameResponse, eventResponse, playerResponse, deviceResponse] = await Promise.all([
        api<{ game: Game }>(\`/games/\${gameId}\`),
        api<{ events: GameEvent[] }>(\`/games/\${gameId}/events\`),
        api<{ players: PlayerOption[] }>(\`/games/\${gameId}/event-players\`),
        api<{ devices: Device[] }>("/scoreboard-devices"),
      ]);

      setGame(gameResponse.game);
      setEvents(eventResponse.events);
      setPlayers(playerResponse.players);`,
"load event players",
);

replaceOnce(
`  async function addEvent(
    type: "GOAL" | "PENALTY",
    side: "home" | "away",
  ): Promise<void> {`,
`  function openGoal(side: "home" | "away"): void {
    setGoalSide(side);
    setScorerId("");
    setAssist1Id("");
    setAssist2Id("");
    setError("");
  }

  async function recordGoal(): Promise<void> {
    if (!game || !goalSide || !canScore) return;

    const selectedTeamId = goalSide === "home" ? game.homeTeamId : game.awayTeamId;

    if (selectedTeamId !== null && !scorerId) {
      setError("Select the player who scored, or use Quick unassigned goal.");
      return;
    }

    setBusy(true);
    setError("");

    try {
      await api(\`/games/\${game.id}/events\`, {
        method: "POST",
        body: JSON.stringify({
          type: "GOAL",
          side: goalSide,
          playerId: scorerId || null,
          assist1PlayerId: assist1Id || null,
          assist2PlayerId: assist2Id || null,
          notes: "Roster entry from Scorekeeper Console",
        }),
      });

      setGoalSide(null);
      setScorerId("");
      setAssist1Id("");
      setAssist2Id("");
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not record goal.");
    } finally {
      setBusy(false);
    }
  }

  async function recordUnassignedGoal(): Promise<void> {
    if (!goalSide) return;
    setScorerId("");
    setAssist1Id("");
    setAssist2Id("");

    if (!game || !canScore) return;

    setBusy(true);
    setError("");

    try {
      await api(\`/games/\${game.id}/events\`, {
        method: "POST",
        body: JSON.stringify({
          type: "GOAL",
          side: goalSide,
          playerId: null,
          assist1PlayerId: null,
          assist2PlayerId: null,
          notes: "Unassigned goal from Scorekeeper Console",
        }),
      });

      setGoalSide(null);
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not record goal.");
    } finally {
      setBusy(false);
    }
  }

  async function addEvent(
    type: "PENALTY",
    side: "home" | "away",
  ): Promise<void> {`,
"goal workflow functions",
);

replaceOnce(
`      await api(\`/games/\${game.id}/events\`, {
        method: "POST",
        body: JSON.stringify(
          type === "GOAL"
            ? {
                type: "GOAL",
                side,
                playerId: null,
                assist1PlayerId: null,
                assist2PlayerId: null,
                notes: "Quick entry from Scorekeeper Console",
              }
            : {
                type: "PENALTY",
                side,
                playerId: null,
                penaltyCode: "MINOR",
                penaltyMinutes: 2,
                notes: "Quick entry from Scorekeeper Console",
              },
        ),
      });`,
`      await api(\`/games/\${game.id}/events\`, {
        method: "POST",
        body: JSON.stringify({
          type,
          side,
          playerId: null,
          penaltyCode: "MINOR",
          penaltyMinutes: 2,
          notes: "Quick entry from Scorekeeper Console",
        }),
      });`,
"penalty-only quick event",
);

text = text.replaceAll(
`void addEvent("GOAL", "home")`,
`openGoal("home")`,
);
text = text.replaceAll(
`void addEvent("GOAL", "away")`,
`openGoal("away")`,
);

replaceOnce(
`  const inIntermission = game.gamePhase === "INTERMISSION";
  const clockRunning = inIntermission ? game.intermissionRunning : game.clockRunning;
  const activeEvents = events.filter((event) => !event.voidedAt);
  const onlineDevices = devices.filter((device) => device.status === "ONLINE").length;`,
`  const inIntermission = game.gamePhase === "INTERMISSION";
  const clockRunning = inIntermission ? game.intermissionRunning : game.clockRunning;
  const activeEvents = events.filter((event) => !event.voidedAt);
  const onlineDevices = devices.filter((device) => device.status === "ONLINE").length;
  const goalTeamId =
    goalSide === "home"
      ? game.homeTeamId
      : goalSide === "away"
        ? game.awayTeamId
        : null;
  const goalPlayers = players.filter((player) => player.teamId === goalTeamId);
  const assist1Players = goalPlayers.filter((player) => String(player.id) !== scorerId);
  const assist2Players = goalPlayers.filter(
    (player) => String(player.id) !== scorerId && String(player.id) !== assist1Id,
  );`,
"goal player option calculations",
);

replaceOnce(
`        <section className={styles.utilityBar}>`,
`        {goalSide ? (
          <div
            className={styles.modalBackdrop}
            role="presentation"
            onMouseDown={(event) => {
              if (event.target === event.currentTarget && !busy) setGoalSide(null);
            }}
          >
            <section
              className={styles.goalModal}
              role="dialog"
              aria-modal="true"
              aria-label="Record goal"
            >
              <div className={styles.modalHeader}>
                <div>
                  <span className={styles.eyebrow}>Record goal</span>
                  <h2>{sideLabel(game, goalSide)}</h2>
                </div>
                <button
                  type="button"
                  className={styles.closeButton}
                  disabled={busy}
                  onClick={() => setGoalSide(null)}
                >
                  ×
                </button>
              </div>

              {goalTeamId === null ? (
                <p className={styles.modalNotice}>
                  This is an external team without a SportsOS roster. You can record the goal unassigned.
                </p>
              ) : goalPlayers.length === 0 ? (
                <p className={styles.modalNotice}>
                  No eligible roster players were returned for this team.
                </p>
              ) : null}

              <div className={styles.goalFields}>
                <label>
                  <span>Scorer</span>
                  <select
                    value={scorerId}
                    onChange={(event) => {
                      const value = event.target.value;
                      setScorerId(value);
                      if (assist1Id === value) setAssist1Id("");
                      if (assist2Id === value) setAssist2Id("");
                    }}
                  >
                    <option value="">Select scorer…</option>
                    {goalPlayers.map((player) => (
                      <option key={player.id} value={player.id}>
                        {playerLabel(player)}
                      </option>
                    ))}
                  </select>
                </label>

                <label>
                  <span>First assist</span>
                  <select
                    value={assist1Id}
                    disabled={!scorerId}
                    onChange={(event) => {
                      const value = event.target.value;
                      setAssist1Id(value);
                      if (assist2Id === value) setAssist2Id("");
                    }}
                  >
                    <option value="">None</option>
                    {assist1Players.map((player) => (
                      <option key={player.id} value={player.id}>
                        {playerLabel(player)}
                      </option>
                    ))}
                  </select>
                </label>

                <label>
                  <span>Second assist</span>
                  <select
                    value={assist2Id}
                    disabled={!scorerId}
                    onChange={(event) => setAssist2Id(event.target.value)}
                  >
                    <option value="">None</option>
                    {assist2Players.map((player) => (
                      <option key={player.id} value={player.id}>
                        {playerLabel(player)}
                      </option>
                    ))}
                  </select>
                </label>
              </div>

              <div className={styles.goalSummary}>
                <strong>
                  {scorerId
                    ? playerLabel(goalPlayers.find((player) => String(player.id) === scorerId)!)
                    : "Scorer not selected"}
                </strong>
                <span>
                  {assist1Id || assist2Id
                    ? \`Assists: \${[
                        goalPlayers.find((player) => String(player.id) === assist1Id),
                        goalPlayers.find((player) => String(player.id) === assist2Id),
                      ]
                        .filter(Boolean)
                        .map((player) => playerLabel(player!))
                        .join(", ")}\`
                    : "Unassisted"}
                </span>
              </div>

              <div className={styles.modalActions}>
                <button
                  type="button"
                  className={styles.confirmGoalButton}
                  disabled={busy || (goalTeamId !== null && !scorerId)}
                  onClick={() => void recordGoal()}
                >
                  {busy ? "SAVING…" : "CONFIRM GOAL"}
                </button>
                <button
                  type="button"
                  className={styles.unassignedButton}
                  disabled={busy}
                  onClick={() => void recordUnassignedGoal()}
                >
                  QUICK UNASSIGNED GOAL
                </button>
                <button
                  type="button"
                  className={styles.cancelButton}
                  disabled={busy}
                  onClick={() => setGoalSide(null)}
                >
                  CANCEL
                </button>
              </div>
            </section>
          </div>
        ) : null}

        <section className={styles.utilityBar}>`,
"goal modal markup",
);

fs.writeFileSync(path, text);
NODE

cat >> "$CSS" <<'EOF'

.modalBackdrop {
  position: fixed;
  inset: 0;
  z-index: 100;
  display: grid;
  place-items: center;
  padding: 18px;
  background: rgba(2, 6, 23, 0.78);
  backdrop-filter: blur(8px);
}

.goalModal {
  width: min(680px, 100%);
  max-height: 92vh;
  overflow: auto;
  border: 1px solid rgba(96, 165, 250, 0.32);
  border-radius: 22px;
  padding: 22px;
  background: #0f172a;
  box-shadow: 0 30px 90px rgba(0, 0, 0, 0.5);
}

.modalHeader {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}

.modalHeader h2 {
  margin: 4px 0 0;
  font-size: 1.8rem;
}

.closeButton {
  width: 48px;
  min-width: 48px;
  border: 1px solid rgba(148, 163, 184, 0.25);
  border-radius: 12px;
  background: #111827;
  color: #f8fafc;
  font-size: 1.8rem;
}

.modalNotice {
  margin: 16px 0;
  padding: 12px;
  border-radius: 12px;
  background: rgba(120, 53, 15, 0.35);
  color: #fde68a;
}

.goalFields {
  display: grid;
  gap: 14px;
  margin-top: 20px;
}

.goalFields label {
  display: grid;
  gap: 7px;
  font-weight: 800;
}

.goalFields select {
  width: 100%;
  min-height: 58px;
  border: 1px solid rgba(148, 163, 184, 0.28);
  border-radius: 12px;
  padding: 0 14px;
  background: #111827;
  color: #f8fafc;
  font-size: 1rem;
}

.goalSummary {
  display: grid;
  gap: 5px;
  margin-top: 18px;
  padding: 14px;
  border-radius: 12px;
  background: rgba(30, 41, 59, 0.9);
}

.goalSummary span {
  color: #cbd5e1;
}

.modalActions {
  display: grid;
  grid-template-columns: 1fr;
  gap: 9px;
  margin-top: 18px;
}

.confirmGoalButton,
.unassignedButton,
.cancelButton {
  min-height: 58px;
  border: 0;
  border-radius: 13px;
  font-weight: 900;
  cursor: pointer;
}

.confirmGoalButton {
  background: #166534;
  color: white;
}

.unassignedButton {
  background: #1d4ed8;
  color: white;
}

.cancelButton {
  background: #334155;
  color: white;
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
    expect(source).toContain("player.teamId === goalTeamId");
  });

  it("records roster-aware goals as game events", () => {
    expect(source).toContain("assist1PlayerId: assist1Id || null");
    expect(source).toContain("assist2PlayerId: assist2Id || null");
    expect(source).toContain("playerId: scorerId || null");
    expect(source).toContain('"Roster entry from Scorekeeper Console"');
  });

  it("prevents selecting the scorer again as an assist", () => {
    expect(source).toContain("String(player.id) !== scorerId");
    expect(source).toContain("String(player.id) !== assist1Id");
  });

  it("retains an explicit unassigned-goal path for external or incomplete rosters", () => {
    expect(source).toContain("recordUnassignedGoal");
    expect(source).toContain("QUICK UNASSIGNED GOAL");
    expect(source).toContain("playerId: null");
  });

  it("records penalties as game events", () => {
    expect(source).toContain('type: "PENALTY"');
    expect(source).toContain('penaltyMinutes: 2');
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
echo " SportsOS Milestone 5.2"
echo " Roster-Aware Goal Entry"
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
echo "Goal flow:"
echo "  GOAL"
echo "    -> scorer"
echo "    -> first assist"
echo "    -> second assist"
echo "    -> confirm"
echo
echo "Safety / compatibility:"
echo "  players loaded from /games/:id/event-players"
echo "  players filtered to scoring team"
echo "  scorer excluded from assist lists"
echo "  assist 1 excluded from assist 2"
echo "  external teams retain unassigned goal path"
echo "  goal still commits through /games/:id/events"
echo
echo "Run:"
echo "  npm run typecheck"
echo "  npm test"
echo "  npm run build"
