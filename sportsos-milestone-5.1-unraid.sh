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

PAGE="apps/dashboard/app/games/[id]/control/page.tsx"
CSS="apps/dashboard/app/games/[id]/control/scorekeeper.module.css"
TEST="apps/api/test/scorekeeper-console-contract.test.ts"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/5.1-${STAMP}"
mkdir -p "$BACKUP_DIR"

for f in "$PAGE" "$CSS"; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$f")"
    cp "$f" "$BACKUP_DIR/$f"
  fi
done

mkdir -p "$(dirname "$PAGE")"

cat > "$PAGE" <<'EOF'
"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { io } from "socket.io-client";
import { AuthGate } from "../../../../components/AuthGate";
import { API, api } from "../../../../lib/api";
import {
  getStoredUser,
  PERMISSIONS,
  userHasPermission,
  type AuthenticatedUser,
} from "../../../../lib/auth";
import styles from "./scorekeeper.module.css";

type GameStatus = "SCHEDULED" | "LIVE" | "FINAL" | "POSTPONED" | "CANCELED";
type GamePhase = "PREGAME" | "REGULATION" | "INTERMISSION" | "OVERTIME" | "FINAL";

interface Game {
  id: number;
  organizationId: number;
  organizationName: string;
  seasonName: string;
  homeTeamName: string;
  awayTeamName: string;
  venue: string | null;
  status: GameStatus;
  gamePhase: GamePhase;
  homeScore: number;
  awayScore: number;
  period: number;
  periodLabel: string;
  regulationPeriods: number;
  clockRemainingMs: number;
  clockRunning: boolean;
  clockStartedAt: string | null;
  intermissionRemainingMs: number;
  intermissionRunning: boolean;
  intermissionStartedAt: string | null;
  overtimeEnabled: boolean;
}

interface GameEvent {
  id: number;
  type: "GOAL" | "PENALTY";
  side: "home" | "away";
  period: number;
  clockRemainingMs: number;
  playerName: string | null;
  playerJerseyNumber: number | null;
  penaltyCode: string | null;
  penaltyMinutes: number | null;
  voidedAt: string | null;
  createdAt: string;
}

interface Device {
  id: number;
  gameId: number | null;
  name: string;
  status: "ONLINE" | "OFFLINE";
  lastSeenAt: string | null;
}

type ScoringAction =
  | { action: "startClock" }
  | { action: "pauseClock" }
  | { action: "nextPeriod" }
  | { action: "startOvertime" }
  | { action: "finishGame" }
  | { action: "adjustClock"; amountMs: number };

function effectiveClock(
  remainingMs: number,
  running: boolean,
  startedAt: string | null,
  now: number,
): number {
  if (!running || !startedAt) return Math.max(0, remainingMs);
  return Math.max(0, remainingMs - (now - new Date(startedAt).getTime()));
}

function formatClock(milliseconds: number): string {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  return `${Math.floor(totalSeconds / 60)}:${String(totalSeconds % 60).padStart(2, "0")}`;
}

function sideLabel(game: Game, side: "home" | "away"): string {
  return side === "home" ? game.homeTeamName : game.awayTeamName;
}

export default function ScorekeeperConsolePage() {
  const params = useParams<{ id: string }>();
  const gameId = Number(params.id);

  const [user, setUser] = useState<AuthenticatedUser | null>(null);
  const [game, setGame] = useState<Game | null>(null);
  const [events, setEvents] = useState<GameEvent[]>([]);
  const [devices, setDevices] = useState<Device[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [now, setNow] = useState(() => Date.now());
  const [socketConnected, setSocketConnected] = useState(false);
  const actionQueue = useRef<Promise<void>>(Promise.resolve());
  const pendingActions = useRef(0);

  const canScore = userHasPermission(user, PERMISSIONS.GAME_SCORE);

  const displayedClockMs = useMemo(() => {
    if (!game) return 0;

    if (game.gamePhase === "INTERMISSION") {
      return effectiveClock(
        game.intermissionRemainingMs,
        game.intermissionRunning,
        game.intermissionStartedAt,
        now,
      );
    }

    return effectiveClock(
      game.clockRemainingMs,
      game.clockRunning,
      game.clockStartedAt,
      now,
    );
  }, [game, now]);

  const load = useCallback(async () => {
    if (!Number.isInteger(gameId) || gameId <= 0) {
      setError("Invalid game id.");
      return;
    }

    try {
      const [gameResponse, eventResponse, deviceResponse] = await Promise.all([
        api<{ game: Game }>(`/games/${gameId}`),
        api<{ events: GameEvent[] }>(`/games/${gameId}/events`),
        api<{ devices: Device[] }>("/scoreboard-devices"),
      ]);

      setGame(gameResponse.game);
      setEvents(eventResponse.events);
      setDevices(deviceResponse.devices.filter((device) => device.gameId === gameId));
      setError("");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load scorekeeper console.");
    }
  }, [gameId]);

  useEffect(() => {
    setUser(getStoredUser());
    void load();
  }, [load]);

  useEffect(() => {
    const socket = io(API);

    socket.on("connect", () => setSocketConnected(true));
    socket.on("disconnect", () => setSocketConnected(false));

    const refresh = (payload?: { id?: number; gameId?: number; game?: { id?: number } }) => {
      const changedGameId = payload?.game?.id ?? payload?.gameId ?? payload?.id;

      if (changedGameId === undefined || changedGameId === gameId) {
        void load();
      }
    };

    [
      "game:updated",
      "game:scored",
      "game:clock-expired",
      "game:intermission-expired",
      "game:event-created",
      "game:event-voided",
      "game:penalties-updated",
      "scoreboard-device:updated",
      "scoreboard-device:status",
      "scoreboard-devices:changed",
    ].forEach((eventName) => socket.on(eventName, refresh));

    return () => {
      socket.disconnect();
    };
  }, [gameId, load]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);

  function score(action: ScoringAction): Promise<void> {
    if (!game || !canScore) return Promise.resolve();

    const actionId = crypto.randomUUID();
    pendingActions.current += 1;
    setBusy(true);
    setError("");

    const request = actionQueue.current.then(async () => {
      const response = await api<{ game: Game }>(`/games/${game.id}/scoring`, {
        method: "POST",
        body: JSON.stringify({ ...action, actionId }),
      });

      setGame(response.game);
    });

    actionQueue.current = request
      .catch((cause: unknown) => {
        setError(cause instanceof Error ? cause.message : "Could not update game.");
      })
      .finally(() => {
        pendingActions.current -= 1;
        if (pendingActions.current === 0) setBusy(false);
      });

    return request;
  }

  async function addEvent(
    type: "GOAL" | "PENALTY",
    side: "home" | "away",
  ): Promise<void> {
    if (!game || !canScore) return;

    setBusy(true);
    setError("");

    try {
      await api(`/games/${game.id}/events`, {
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
      });

      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not record event.");
    } finally {
      setBusy(false);
    }
  }

  async function undoLastEvent(): Promise<void> {
    if (!game || !canScore) return;

    const last = events.find((event) => !event.voidedAt);
    if (!last) {
      setError("There is no scoring event to undo.");
      return;
    }

    if (!window.confirm(`Void the last ${last.type.toLowerCase()} event?`)) return;

    setBusy(true);
    setError("");

    try {
      await api(`/games/${game.id}/events/${last.id}`, {
        method: "DELETE",
      });

      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not undo the last event.");
    } finally {
      setBusy(false);
    }
  }

  async function horn(): Promise<void> {
    if (!game || !canScore) return;

    try {
      await api(`/games/${game.id}/broadcast`, {
        method: "POST",
        body: JSON.stringify({ type: "HORN" }),
      });
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not trigger horn.");
    }
  }

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (target?.tagName === "INPUT" || target?.tagName === "TEXTAREA" || target?.tagName === "SELECT") {
        return;
      }

      if (!game || !canScore || busy) return;

      if (event.code === "Space") {
        event.preventDefault();
        void score({
          action:
            game.gamePhase === "INTERMISSION"
              ? "pauseClock"
              : game.clockRunning
                ? "pauseClock"
                : "startClock",
        } as ScoringAction);
      } else if (event.key.toLowerCase() === "h") {
        void addEvent("GOAL", "home");
      } else if (event.key.toLowerCase() === "a") {
        void addEvent("GOAL", "away");
      } else if (event.key.toLowerCase() === "u") {
        void undoLastEvent();
      } else if (event.key.toLowerCase() === "f") {
        void horn();
      }
    };

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [busy, canScore, game, events]);

  if (!game) {
    return (
      <AuthGate>
        <main className={styles.page}>
          <p>{error || "Loading game…"}</p>
        </main>
      </AuthGate>
    );
  }

  const inIntermission = game.gamePhase === "INTERMISSION";
  const clockRunning = inIntermission ? game.intermissionRunning : game.clockRunning;
  const activeEvents = events.filter((event) => !event.voidedAt);
  const onlineDevices = devices.filter((device) => device.status === "ONLINE").length;

  return (
    <AuthGate>
      <main className={styles.page}>
        <header className={styles.topbar}>
          <div>
            <span className={styles.eyebrow}>Live scorekeeper</span>
            <h1>{game.homeTeamName} vs {game.awayTeamName}</h1>
            <p>{game.venue || game.organizationName} · {game.seasonName}</p>
          </div>

          <div className={styles.topActions}>
            <Link href={`/games/${game.id}/scoreboard`}>Public scoreboard</Link>
            <Link href={`/games/${game.id}/overlay`}>Overlay</Link>
            <Link href="/games">Exit console</Link>
          </div>
        </header>

        {error ? <div className={styles.error}>{error}</div> : null}

        {!canScore ? (
          <div className={styles.warning}>
            Your account can view this console but does not have GAME_SCORE permission.
          </div>
        ) : null}

        <section className={styles.scoreboard}>
          <div className={styles.teamBlock}>
            <span className={styles.side}>HOME</span>
            <h2>{game.homeTeamName}</h2>
            <strong className={styles.score}>{game.homeScore}</strong>
            <button
              className={styles.goalButton}
              disabled={!canScore || busy || game.status === "FINAL"}
              onClick={() => void addEvent("GOAL", "home")}
            >
              GOAL
            </button>
            <button
              className={styles.penaltyButton}
              disabled={!canScore || busy || game.status === "FINAL"}
              onClick={() => void addEvent("PENALTY", "home")}
            >
              2:00 PENALTY
            </button>
          </div>

          <div className={styles.clockBlock}>
            <span className={styles.phase}>
              {inIntermission ? "INTERMISSION" : game.periodLabel || `PERIOD ${game.period}`}
            </span>
            <strong className={styles.clock}>{formatClock(displayedClockMs)}</strong>
            <span className={styles.clockState}>
              {clockRunning ? "RUNNING" : "PAUSED"} · {game.status}
            </span>

            <button
              className={clockRunning ? styles.pauseButton : styles.startButton}
              disabled={!canScore || busy || game.status === "FINAL" || inIntermission}
              onClick={() =>
                void score({
                  action: game.clockRunning ? "pauseClock" : "startClock",
                })
              }
            >
              {game.clockRunning ? "PAUSE CLOCK" : "START CLOCK"}
            </button>

            <div className={styles.clockAdjustments}>
              <button disabled={!canScore || busy || inIntermission} onClick={() => void score({ action: "adjustClock", amountMs: -1000 })}>−1s</button>
              <button disabled={!canScore || busy || inIntermission} onClick={() => void score({ action: "adjustClock", amountMs: 1000 })}>+1s</button>
              <button disabled={!canScore || busy || inIntermission} onClick={() => void score({ action: "adjustClock", amountMs: -10000 })}>−10s</button>
              <button disabled={!canScore || busy || inIntermission} onClick={() => void score({ action: "adjustClock", amountMs: 10000 })}>+10s</button>
            </div>

            {displayedClockMs === 0 && game.status !== "FINAL" ? (
              <div className={styles.flowActions}>
                {game.period < game.regulationPeriods ? (
                  <button onClick={() => void score({ action: "nextPeriod" })}>NEXT PERIOD</button>
                ) : (
                  <>
                    {game.overtimeEnabled ? (
                      <button onClick={() => void score({ action: "startOvertime" })}>START OVERTIME</button>
                    ) : null}
                    <button className={styles.dangerButton} onClick={() => void score({ action: "finishGame" })}>FINAL</button>
                  </>
                )}
              </div>
            ) : null}
          </div>

          <div className={styles.teamBlock}>
            <span className={styles.side}>AWAY</span>
            <h2>{game.awayTeamName}</h2>
            <strong className={styles.score}>{game.awayScore}</strong>
            <button
              className={styles.goalButton}
              disabled={!canScore || busy || game.status === "FINAL"}
              onClick={() => void addEvent("GOAL", "away")}
            >
              GOAL
            </button>
            <button
              className={styles.penaltyButton}
              disabled={!canScore || busy || game.status === "FINAL"}
              onClick={() => void addEvent("PENALTY", "away")}
            >
              2:00 PENALTY
            </button>
          </div>
        </section>

        <section className={styles.utilityBar}>
          <button disabled={!canScore || busy} onClick={() => void undoLastEvent()}>
            UNDO LAST EVENT
          </button>
          <button disabled={!canScore || busy} onClick={() => void horn()}>
            HORN
          </button>
          <span className={styles.shortcut}>Space: clock · H/A: goals · U: undo · F: horn</span>
        </section>

        <section className={styles.lowerGrid}>
          <article className={styles.panel}>
            <div className={styles.panelHeader}>
              <div>
                <span className={styles.eyebrow}>Game activity</span>
                <h2>Live event feed</h2>
              </div>
              <strong>{activeEvents.length}</strong>
            </div>

            <div className={styles.eventFeed}>
              {activeEvents.length === 0 ? (
                <p className={styles.muted}>No goals or penalties recorded yet.</p>
              ) : (
                activeEvents.slice(0, 12).map((event) => (
                  <div className={styles.eventRow} key={event.id}>
                    <div>
                      <strong>{event.type}</strong>
                      <span>{sideLabel(game, event.side)}</span>
                    </div>
                    <div>
                      <span>P{event.period} · {formatClock(event.clockRemainingMs)}</span>
                      <span>
                        {event.playerName
                          ? `${event.playerJerseyNumber ? `#${event.playerJerseyNumber} ` : ""}${event.playerName}`
                          : event.type === "PENALTY"
                            ? `${event.penaltyMinutes ?? 2}:00 ${event.penaltyCode ?? "Penalty"}`
                            : "Quick-entry goal"}
                      </span>
                    </div>
                  </div>
                ))
              )}
            </div>
          </article>

          <article className={styles.panel}>
            <span className={styles.eyebrow}>Connections</span>
            <h2>Game-day status</h2>

            <div className={styles.statusList}>
              <div>
                <span>API</span>
                <strong className={styles.good}>ONLINE</strong>
              </div>
              <div>
                <span>Realtime</span>
                <strong className={socketConnected ? styles.good : styles.bad}>
                  {socketConnected ? "CONNECTED" : "DISCONNECTED"}
                </strong>
              </div>
              <div>
                <span>Scoreboard devices</span>
                <strong className={onlineDevices === devices.length && devices.length > 0 ? styles.good : styles.neutral}>
                  {onlineDevices}/{devices.length} ONLINE
                </strong>
              </div>
              <div>
                <span>Scoring access</span>
                <strong className={canScore ? styles.good : styles.bad}>
                  {canScore ? "READY" : "READ ONLY"}
                </strong>
              </div>
            </div>

            {devices.length > 0 ? (
              <div className={styles.deviceList}>
                {devices.map((device) => (
                  <div key={device.id}>
                    <span>{device.name}</span>
                    <strong className={device.status === "ONLINE" ? styles.good : styles.bad}>
                      {device.status}
                    </strong>
                  </div>
                ))}
              </div>
            ) : (
              <p className={styles.muted}>No scoreboard device is assigned to this game.</p>
            )}
          </article>
        </section>
      </main>
    </AuthGate>
  );
}
EOF

cat > "$CSS" <<'EOF'
.page {
  min-height: 100vh;
  padding: 22px;
  background:
    radial-gradient(circle at top, rgba(59, 130, 246, 0.12), transparent 35%),
    #070b12;
  color: #f8fafc;
}

.topbar,
.panelHeader,
.utilityBar,
.statusList > div,
.deviceList > div,
.eventRow {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.topbar {
  margin-bottom: 18px;
}

.topbar h1,
.panel h2 {
  margin: 2px 0;
}

.topbar p,
.muted {
  color: #94a3b8;
}

.topActions {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}

.topActions a {
  color: #bfdbfe;
}

.eyebrow,
.side,
.phase {
  font-size: 0.75rem;
  font-weight: 900;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: #93c5fd;
}

.error,
.warning {
  border-radius: 12px;
  padding: 12px 14px;
  margin-bottom: 14px;
}

.error {
  background: rgba(127, 29, 29, 0.55);
  color: #fecaca;
}

.warning {
  background: rgba(120, 53, 15, 0.45);
  color: #fde68a;
}

.scoreboard {
  display: grid;
  grid-template-columns: minmax(250px, 1fr) minmax(320px, 1.2fr) minmax(250px, 1fr);
  gap: 16px;
}

.teamBlock,
.clockBlock,
.panel {
  border: 1px solid rgba(148, 163, 184, 0.2);
  background: rgba(15, 23, 42, 0.86);
  border-radius: 20px;
  padding: 20px;
}

.teamBlock {
  display: flex;
  flex-direction: column;
  text-align: center;
}

.teamBlock h2 {
  min-height: 58px;
  display: grid;
  place-items: center;
  margin: 8px 0;
}

.score {
  font-size: clamp(4rem, 10vw, 7rem);
  line-height: 1;
  margin: 12px 0 20px;
}

.clockBlock {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
}

.clock {
  font-variant-numeric: tabular-nums;
  font-size: clamp(4.5rem, 11vw, 8rem);
  line-height: 1;
  margin: 12px 0;
}

.clockState {
  color: #94a3b8;
  margin-bottom: 18px;
}

button {
  min-height: 48px;
}

.goalButton,
.penaltyButton,
.startButton,
.pauseButton,
.dangerButton,
.flowActions button,
.utilityBar button {
  border: 0;
  border-radius: 14px;
  font-weight: 900;
  padding: 15px 18px;
  cursor: pointer;
}

.goalButton {
  min-height: 82px;
  font-size: 1.45rem;
  background: #166534;
  color: white;
}

.penaltyButton {
  margin-top: 10px;
  background: #854d0e;
  color: white;
}

.startButton {
  width: 100%;
  background: #166534;
  color: white;
}

.pauseButton {
  width: 100%;
  background: #991b1b;
  color: white;
}

.dangerButton {
  background: #7f1d1d;
  color: white;
}

.clockAdjustments,
.flowActions {
  width: 100%;
  display: grid;
  gap: 8px;
  margin-top: 12px;
}

.clockAdjustments {
  grid-template-columns: repeat(4, 1fr);
}

.clockAdjustments button {
  border: 1px solid rgba(148, 163, 184, 0.3);
  background: #111827;
  color: #e2e8f0;
  border-radius: 10px;
}

.flowActions {
  grid-template-columns: repeat(auto-fit, minmax(130px, 1fr));
}

.flowActions button {
  background: #1d4ed8;
  color: white;
}

.utilityBar {
  margin: 16px 0;
  padding: 12px;
  border-radius: 14px;
  background: rgba(15, 23, 42, 0.85);
}

.utilityBar button {
  background: #1e293b;
  color: #f8fafc;
}

.shortcut {
  margin-left: auto;
  color: #94a3b8;
  font-size: 0.85rem;
}

.lowerGrid {
  display: grid;
  grid-template-columns: 1.5fr 0.8fr;
  gap: 16px;
}

.eventFeed,
.statusList,
.deviceList {
  display: grid;
  gap: 8px;
  margin-top: 14px;
}

.eventRow,
.statusList > div,
.deviceList > div {
  padding: 10px 0;
  border-bottom: 1px solid rgba(148, 163, 184, 0.12);
}

.eventRow > div {
  display: grid;
  gap: 3px;
}

.eventRow > div:last-child {
  text-align: right;
  color: #cbd5e1;
}

.good {
  color: #86efac;
}

.bad {
  color: #fca5a5;
}

.neutral {
  color: #fde68a;
}

button:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

@media (max-width: 1000px) {
  .scoreboard {
    grid-template-columns: 1fr 1fr;
  }

  .clockBlock {
    grid-column: 1 / -1;
    grid-row: 1;
  }

  .lowerGrid {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 680px) {
  .page {
    padding: 10px;
  }

  .topbar,
  .utilityBar {
    align-items: stretch;
    flex-direction: column;
  }

  .scoreboard {
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }

  .teamBlock,
  .clockBlock,
  .panel {
    padding: 12px;
    border-radius: 14px;
  }

  .clockBlock {
    grid-column: 1 / -1;
  }

  .teamBlock h2 {
    font-size: 1rem;
  }

  .score {
    font-size: 4rem;
  }

  .goalButton {
    min-height: 72px;
  }

  .clockAdjustments {
    grid-template-columns: repeat(2, 1fr);
  }

  .shortcut {
    margin-left: 0;
  }
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

  it("records goals and penalties as game events", () => {
    expect(source).toContain("`/games/${game.id}/events`");
    expect(source).toContain('type: "GOAL"');
    expect(source).toContain('type: "PENALTY"');
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

  it("provides touch controls and keyboard shortcuts", () => {
    expect(source).toContain("GOAL");
    expect(source).toContain("2:00 PENALTY");
    expect(source).toContain('event.code === "Space"');
    expect(source).toContain('event.key.toLowerCase() === "h"');
    expect(source).toContain('event.key.toLowerCase() === "a"');
  });
});
EOF

echo
echo "============================================="
echo " SportsOS Milestone 5.1"
echo " Live Scorekeeper Console Foundation"
echo "============================================="
echo
echo "Created:"
echo "  $PAGE"
echo "  $CSS"
echo "  $TEST"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "New route:"
echo "  /games/:id/control"
echo
echo "Features:"
echo "  touch-first home/away goal entry"
echo "  quick 2-minute penalty entry"
echo "  authoritative clock start/pause/corrections"
echo "  period/overtime/final controls"
echo "  guarded undo via event voiding"
echo "  horn trigger"
echo "  realtime event feed"
echo "  scoreboard device status"
echo "  keyboard shortcuts"
echo
echo "Run:"
echo "  npm run typecheck"
echo "  npm test"
