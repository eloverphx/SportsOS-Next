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
  homeTeamId: number | null;
  awayTeamId: number | null;
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

interface PlayerOption {
  id: number;
  teamId: number;
  firstName: string;
  lastName: string;
  preferredName: string | null;
  jerseyNumber: number | null;
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

interface ActivePenalty {
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

function playerLabel(player: PlayerOption): string {
  const jersey = player.jerseyNumber == null ? "" : `#${player.jerseyNumber} `;
  return `${jersey}${player.preferredName || player.firstName} ${player.lastName}`;
}

export default function ScorekeeperConsolePage() {
  const params = useParams<{ id: string }>();
  const gameId = Number(params.id);

  const [user, setUser] = useState<AuthenticatedUser | null>(null);
  const [game, setGame] = useState<Game | null>(null);
  const [events, setEvents] = useState<GameEvent[]>([]);
  const [players, setPlayers] = useState<PlayerOption[]>([]);
  const [activePenalties, setActivePenalties] = useState<ActivePenalty[]>([]);
  const [devices, setDevices] = useState<Device[]>([]);
  const [goalSide, setGoalSide] = useState<"home" | "away" | null>(null);
  const [penaltySide, setPenaltySide] = useState<"home" | "away" | null>(null);
  const [penaltyPlayerId, setPenaltyPlayerId] = useState("");
  const [penaltyCode, setPenaltyCode] = useState("Tripping");
  const [penaltyMinutes, setPenaltyMinutes] = useState("2");
  const [scorerId, setScorerId] = useState("");
  const [assist1Id, setAssist1Id] = useState("");
  const [assist2Id, setAssist2Id] = useState("");
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
      const [
        gameResponse,
        eventResponse,
        playerResponse,
        penaltyResponse,
        deviceResponse,
      ] = await Promise.all([
        api<{ game: Game }>(`/games/${gameId}`),
        api<{ events: GameEvent[] }>(`/games/${gameId}/events`),
        api<{ players: PlayerOption[] }>(`/games/${gameId}/event-players`),
        api<{ penalties: ActivePenalty[] }>(`/games/${gameId}/penalties`),
        api<{ devices: Device[] }>("/scoreboard-devices"),
      ]);

      setGame(gameResponse.game);
      setEvents(eventResponse.events);
      setPlayers(playerResponse.players);
      setActivePenalties(penaltyResponse.penalties);
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

  function openGoal(side: "home" | "away"): void {
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
      await api(`/games/${game.id}/events`, {
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
      await api(`/games/${game.id}/events`, {
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

  function openPenalty(side: "home" | "away"): void {
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
      await api(`/games/${game.id}/events`, {
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
      await api(`/games/${game.id}/penalties/${penaltyId}`, {
        method: "DELETE",
      });
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not clear penalty.");
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

  async function finishGame(): Promise<void> {
    if (!game || !canScore) return;

    setBusy(true);
    setError("");

    try {
      const response = await api<{ game: Game }>(`/games/${game.id}/lifecycle`, {
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

  async function startGame(): Promise<void> {
    if (!game || !canScore) return;

    setBusy(true);
    setError("");

    try {
      const response = await api<{ game: Game }>(`/games/${game.id}/lifecycle`, {
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
        openGoal("home");
      } else if (event.key.toLowerCase() === "a") {
        openGoal("away");
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
    .filter((penalty) => penalty.displayedRemainingMs > 0);

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
          : `${game.status} · ${game.gamePhase}`,
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
      label: `${game.homeTeamName} roster`,
      ready: game.homeTeamId === null || (homeRosterCount ?? 0) > 0,
      detail:
        game.homeTeamId === null
          ? "External team · roster not required"
          : `${homeRosterCount ?? 0} eligible players`,
    },
    {
      key: "away-roster",
      label: `${game.awayTeamName} roster`,
      ready: game.awayTeamId === null || (awayRosterCount ?? 0) > 0,
      detail:
        game.awayTeamId === null
          ? "External team · roster not required"
          : `${awayRosterCount ?? 0} eligible players`,
    },
  ];

  const recommendedReadiness = [
    {
      key: "scoreboard-assigned",
      label: "Scoreboard assigned",
      ready: devices.length > 0,
      detail:
        devices.length > 0
          ? `${devices.length} assigned device${devices.length === 1 ? "" : "s"}`
          : "No scoreboard assigned · manual operation still available",
    },
    {
      key: "scoreboard-online",
      label: "Scoreboard online",
      ready: devices.length === 0 || onlineDevices > 0,
      detail:
        devices.length === 0
          ? "Not required"
          : `${onlineDevices}/${devices.length} online`,
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
    game.status === "SCHEDULED" || game.gamePhase === "PREGAME";

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
    !game.intermissionRunning;

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

        {finalGame ? (
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
                            ? `${event.playerJerseyNumber ? `#${event.playerJerseyNumber} ` : ""}${event.playerName}`
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
              <Link href={`/games/${game.id}/scoreboard`}>Public scoreboard</Link>
              <Link href={`/games/${game.id}/overlay`}>Broadcast overlay</Link>
              <a
                href={`${API}/system/game-engine/games/${game.id}/diagnostics`}
                target="_blank"
                rel="noreferrer"
              >
                Engine diagnostics
              </a>
              <Link href="/games">Return to games</Link>
            </div>
          </section>
        ) : null}

        {pregameVisible ? (
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
                      `Start ${game.homeTeamName} vs ${game.awayTeamName}?`,
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
              onClick={() => openGoal("home")}
            >
              GOAL
            </button>
            <button
              className={styles.penaltyButton}
              disabled={!canScore || busy || game.status === "FINAL"}
              onClick={() => openPenalty("home")}
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
              onClick={() => openGoal("away")}
            >
              GOAL
            </button>
            <button
              className={styles.penaltyButton}
              disabled={!canScore || busy || game.status === "FINAL"}
              onClick={() => openPenalty("away")}
            >
              2:00 PENALTY
            </button>
          </div>
        </section>

        {penaltySide ? (
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

        {goalSide ? (
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
                    ? `Assists: ${[
                        goalPlayers.find((player) => String(player.id) === assist1Id),
                        goalPlayers.find((player) => String(player.id) === assist2Id),
                      ]
                        .filter(Boolean)
                        .map((player) => playerLabel(player!))
                        .join(", ")}`
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

        {!finalGame && game.status === "LIVE" ? (
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
                    `Finish game as FINAL? ${game.homeTeamName} ${game.homeScore} - ${game.awayScore} ${game.awayTeamName}`,
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

        <section className={styles.utilityBar}>
          <button disabled={!canScore || busy} onClick={() => void undoLastEvent()}>
            UNDO LAST EVENT
          </button>
          <button disabled={!canScore || busy} onClick={() => void horn()}>
            HORN
          </button>
          <span className={styles.shortcut}>Space: clock · H/A: goals · U: undo · F: horn</span>
        </section>

        {visiblePenalties.length > 0 ? (
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
                      {penalty.jerseyNumber != null ? `#${penalty.jerseyNumber} ` : ""}
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
