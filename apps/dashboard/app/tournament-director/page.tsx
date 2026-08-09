"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { io } from "socket.io-client";
import { AuthGate } from "../../components/AuthGate";
import { AppShell } from "../../components/AppShell";
import { TournamentScheduleConflicts } from "../../components/tournament/TournamentScheduleConflicts";
import { TournamentScheduleEditor } from "../../components/tournament/TournamentScheduleEditor";
import { TournamentScheduleTimeline } from "../../components/tournament/TournamentScheduleTimeline";
import { TournamentDayOperations } from "../../components/tournament/TournamentDayOperations";
import { TournamentFocusPanel } from "../../components/tournament/TournamentFocusPanel";
import { TournamentOperationsNavigation } from "../../components/tournament/TournamentOperationsNavigation";
import "../../components/tournament/tournament-operations-navigation.css";
import { API, api } from "../../lib/api";
import styles from "./tournament-director.module.css";

type GameStatus = "SCHEDULED" | "LIVE" | "FINAL" | "POSTPONED" | "CANCELED";

type Game = {
  id: number;
  organizationId: number;
  organizationName: string;
  seasonName: string;
  homeTeamName: string;
  awayTeamName: string;
  scheduledStart: string;
  venue: string | null;
  status: GameStatus;
  homeScore: number;
  awayScore: number;
  period: number;
  clockRemainingMs: number;
  clockRunning: boolean;
  clockStartedAt: string | null;
};

type Device = {
  id: number;
  organizationId: number;
  organizationName: string;
  gameId: number | null;
  gameLabel: string | null;
  name: string;
  location: string | null;
  status: "ONLINE" | "OFFLINE";
  lastSeenAt: string | null;
};

type ActivePenalty = {
  id: number;
  gameId: number;
  side: "home" | "away";
  playerName: string | null;
  jerseyNumber: number | null;
  infraction: string;
  remainingMs: number;
  running: boolean;
  startedAt: string | null;
};

type EngineState = "HEALTHY" | "TRANSITION_PENDING" | "OPERATOR_REQUIRED" | "WARNING";

type EngineGame = {
  gameId: number;
  matchup: string;
  state: EngineState;
  status: string;
  gamePhase: string;
  period: number;
  regulationPeriods: number;
  clockRemainingMs: number;
  clockRunning: boolean;
  intermissionRemainingMs: number;
  intermissionRunning: boolean;
  actionRequired: string | null;
  warnings: ReadonlyArray<{
    code: string;
    message: string;
  }>;
};

type EngineResponse = {
  status: "healthy" | "attention";
  summary: {
    total: number;
    healthy: number;
    transitionPending: number;
    operatorRequired: number;
    warnings: number;
  };
  games: EngineGame[];
};

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

function stateLabel(state: EngineState | undefined): string {
  switch (state) {
    case "HEALTHY":
      return "Healthy";
    case "TRANSITION_PENDING":
      return "Transition pending";
    case "OPERATOR_REQUIRED":
      return "Operator required";
    case "WARNING":
      return "Warning";
    default:
      return "No engine signal";
  }
}

function statusRank(status: GameStatus): number {
  switch (status) {
    case "LIVE":
      return 0;
    case "SCHEDULED":
      return 1;
    case "FINAL":
      return 2;
    case "POSTPONED":
      return 3;
    case "CANCELED":
      return 4;
  }
}

type StartUrgency = "LATE" | "STARTING_SOON" | "UPCOMING" | null;

function startUrgency(game: Game, now: number): StartUrgency {
  if (game.status !== "SCHEDULED") return null;
  const deltaMs = new Date(game.scheduledStart).getTime() - now;
  if (deltaMs < -5 * 60_000) return "LATE";
  if (deltaMs <= 15 * 60_000) return "STARTING_SOON";
  return "UPCOMING";
}

function urgencyLabel(urgency: StartUrgency): string | null {
  switch (urgency) {
    case "LATE":
      return "LATE START";
    case "STARTING_SOON":
      return "STARTING SOON";
    case "UPCOMING":
      return "UPCOMING";
    default:
      return null;
  }
}

export default function TournamentDirectorPage() {
  const [games, setGames] = useState<Game[]>([]);
  const [devices, setDevices] = useState<Device[]>([]);
  const [engine, setEngine] = useState<EngineResponse | null>(null);
  const [penaltiesByGame, setPenaltiesByGame] = useState<Record<number, ActivePenalty[]>>({});
  const [realtimeConnected, setRealtimeConnected] = useState(false);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [now, setNow] = useState(() => Date.now());
  const [statusFilter, setStatusFilter] = useState<"ALL" | GameStatus>("ALL");
  const [search, setSearch] = useState("");

  const load = useCallback(async (): Promise<void> => {
    try {
      const [gameResponse, deviceResponse, engineResponse] = await Promise.all([
        api<{ games: Game[] }>("/games"),
        api<{ devices: Device[] }>("/scoreboard-devices"),
        api<EngineResponse>("/system/game-engine"),
      ]);

      const visibleGames = gameResponse.games.filter(
        (game) => game.status !== "CANCELED" || statusFilter === "CANCELED",
      );

      const livePenaltyEntries = await Promise.all(
        visibleGames
          .filter((game) => game.status === "LIVE")
          .map(async (game) => {
            try {
              const response = await api<{ penalties: ActivePenalty[] }>(
                `/games/${game.id}/penalties`,
              );
              return [game.id, response.penalties] as const;
            } catch {
              return [game.id, []] as const;
            }
          }),
      );

      setGames(gameResponse.games);
      setDevices(deviceResponse.devices);
      setEngine(engineResponse);
      setPenaltiesByGame(Object.fromEntries(livePenaltyEntries));
      setError("");
    } catch (caughtError) {
      setError(
        caughtError instanceof Error
          ? caughtError.message
          : "Could not load tournament operations.",
      );
    } finally {
      setLoading(false);
    }
  }, [statusFilter]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    const socket = io(API);

    socket.on("connect", () => setRealtimeConnected(true));
    socket.on("disconnect", () => setRealtimeConnected(false));

    [
      "game:created",
      "game:updated",
      "game:deleted",
      "game:scored",
      "game:clock-expired",
      "game:intermission-expired",
      "game:event-created",
      "game:event-voided",
      "game:penalties-updated",
      "scoreboard-device:updated",
      "scoreboard-device:status",
      "scoreboard-devices:changed",
    ].forEach((eventName) => socket.on(eventName, () => void load()));

    return () => {
      socket.disconnect();
    };
  }, [load]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    const timer = window.setInterval(() => void load(), 15_000);
    return () => window.clearInterval(timer);
  }, [load]);

  const rows = useMemo(() => {
    const needle = search.trim().toLowerCase();

    return games
      .filter((game) => statusFilter === "ALL" || game.status === statusFilter)
      .filter((game) => {
        if (!needle) return true;
        return `${game.homeTeamName} ${game.awayTeamName} ${game.venue ?? ""} ${game.seasonName}`
          .toLowerCase()
          .includes(needle);
      })
      .sort((left, right) => {
        const rankDifference = statusRank(left.status) - statusRank(right.status);
        if (rankDifference !== 0) return rankDifference;
        return new Date(left.scheduledStart).getTime() - new Date(right.scheduledStart).getTime();
      })
      .map((game) => {
        const assignedDevices = devices.filter((device) => device.gameId === game.id);
        const engineGame = engine?.games.find((entry) => entry.gameId === game.id);
        const penalties = penaltiesByGame[game.id] ?? [];

        return {
          game,
          assignedDevices,
          engineGame,
          penalties,
        };
      });
  }, [devices, engine, games, penaltiesByGame, search, statusFilter]);

  const rinkGroups = useMemo(() => {
    const groups = new Map<string, typeof rows>();

    for (const row of rows) {
      const rink = row.game.venue?.trim() || "Rink not assigned";
      const current = groups.get(rink) ?? [];
      current.push(row);
      groups.set(rink, current);
    }

    return Array.from(groups.entries()).sort(([left], [right]) =>
      left.localeCompare(right),
    );
  }, [rows]);

  const liveGames = games.filter((game) => game.status === "LIVE").length;
  const scheduledGames = games.filter((game) => game.status === "SCHEDULED").length;
  const finalGames = games.filter((game) => game.status === "FINAL").length;
  const offlineAssignedDevices = devices.filter(
    (device) => device.gameId !== null && device.status === "OFFLINE",
  ).length;
  const attentionGames =
    engine?.games.filter((game) => game.state !== "HEALTHY").length ?? 0;

  return (
    <AuthGate>
      <AppShell>
        <main className={styles.page}>
          <header className={styles.header}>
            <div>
              <span className={styles.eyebrow}>Milestone 6 · Tournament operations</span>
              <h1>Tournament Director</h1>
              <p>
                Multi-rink command center for live games, upcoming starts, devices,
                penalties, and engine warnings.
              </p>
            </div>

            <div className={styles.headerActions}>
              <span className={realtimeConnected ? styles.online : styles.offline}>
                Realtime {realtimeConnected ? "connected" : "disconnected"}
              </span>
              <button type="button" onClick={() => void load()} disabled={loading}>
                {loading ? "Refreshing…" : "Refresh"}
              </button>
            </div>
          </header>

          {error ? <div className={styles.error}>{error}</div> : null}

          <section className={styles.metrics} aria-label="Tournament summary">
            <article>
              <span>Live</span>
              <strong>{liveGames}</strong>
            </article>
            <article>
              <span>Upcoming</span>
              <strong>{scheduledGames}</strong>
            </article>
            <article>
              <span>Final</span>
              <strong>{finalGames}</strong>
            </article>
            <article>
              <span>Needs attention</span>
              <strong>{attentionGames}</strong>
            </article>
            <article>
              <span>Assigned devices offline</span>
              <strong>{offlineAssignedDevices}</strong>
            </article>
          </section>

          <TournamentScheduleConflicts games={games} />

          <TournamentScheduleEditor games={games} onSaved={load} />

          <TournamentScheduleTimeline games={games} />

          <TournamentOperationsNavigation />

          <TournamentDayOperations
            games={games}
            devices={devices}
            engineGames={engine?.games ?? []}
          />

          <TournamentFocusPanel games={games} />

          <section className={styles.filters} aria-label="Tournament filters">
            <label>
              Status
              <select
                value={statusFilter}
                onChange={(event) =>
                  setStatusFilter(event.target.value as "ALL" | GameStatus)
                }
              >
                <option value="ALL">All active games</option>
                <option value="LIVE">Live</option>
                <option value="SCHEDULED">Upcoming</option>
                <option value="FINAL">Final</option>
                <option value="POSTPONED">Postponed</option>
                <option value="CANCELED">Canceled</option>
              </select>
            </label>

            <label className={styles.search}>
              Search
              <input
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder="Team, rink, season…"
              />
            </label>
          </section>

          {rows.length === 0 && !loading ? (
            <section className={styles.empty}>
              No games match the current Tournament Director filters.
            </section>
          ) : null}

          <section className={styles.rinkBoard} aria-label="Multi-rink game board">
            {rinkGroups.map(([rink, rinkRows]) => (
              <section className={styles.rinkGroup} key={rink} aria-label={rink}>
                <div className={styles.rinkHeading}>
                  <div>
                    <span className={styles.eyebrow}>Rink</span>
                    <h2>{rink}</h2>
                  </div>
                  <strong>{rinkRows.length} game{rinkRows.length === 1 ? "" : "s"}</strong>
                </div>

                <div className={styles.board}>
                  {rinkRows.map(({ game, assignedDevices, engineGame, penalties }) => {
              const clock = formatClock(
                effectiveClock(
                  game.clockRemainingMs,
                  game.clockRunning,
                  game.clockStartedAt,
                  now,
                ),
              );
              const onlineDevices = assignedDevices.filter(
                (device) => device.status === "ONLINE",
              ).length;
              const engineAttention =
                engineGame !== undefined && engineGame.state !== "HEALTHY";
              const urgency = startUrgency(game, now);
              const urgencyText = urgencyLabel(urgency);

              return (
                <article
                  key={game.id}
                  className={`${styles.gameCard} ${
                    engineAttention ? styles.attentionCard : ""
                  }`}
                >
                  <div className={styles.cardTop}>
                    <div>
                      <div className={styles.badges}>
                        <span className={styles.status}>{game.status}</span>
                        {urgencyText ? (
                          <span
                            className={`${styles.urgency} ${
                              urgency === "LATE"
                                ? styles.urgencyLate
                                : urgency === "STARTING_SOON"
                                  ? styles.urgencySoon
                                  : styles.urgencyUpcoming
                            }`}
                          >
                            {urgencyText}
                          </span>
                        ) : null}
                      </div>
                      <strong>{game.venue || "Rink not assigned"}</strong>
                      <small>{game.seasonName}</small>
                    </div>

                    <div className={styles.clockBlock}>
                      <strong>{game.status === "LIVE" ? clock : `P${game.period}`}</strong>
                      <span>
                        {game.status === "LIVE"
                          ? `Period ${game.period}`
                          : new Date(game.scheduledStart).toLocaleString()}
                      </span>
                    </div>
                  </div>

                  <div className={styles.matchup}>
                    <div>
                      <span>{game.homeTeamName}</span>
                      <strong>{game.homeScore}</strong>
                    </div>
                    <div>
                      <span>{game.awayTeamName}</span>
                      <strong>{game.awayScore}</strong>
                    </div>
                  </div>

                  <div className={styles.healthGrid}>
                    <div>
                      <span>Engine</span>
                      <strong
                        className={
                          engineGame?.state === "HEALTHY"
                            ? styles.good
                            : engineGame
                              ? styles.bad
                              : styles.neutral
                        }
                      >
                        {stateLabel(engineGame?.state)}
                      </strong>
                    </div>
                    <div>
                      <span>Scoreboards</span>
                      <strong>
                        {assignedDevices.length === 0
                          ? "None assigned"
                          : `${onlineDevices}/${assignedDevices.length} online`}
                      </strong>
                    </div>
                    <div>
                      <span>Active penalties</span>
                      <strong>{penalties.length}</strong>
                    </div>
                  </div>

                  {engineGame?.actionRequired ? (
                    <div className={styles.operatorAlert}>
                      <strong>Operator action:</strong> {engineGame.actionRequired}
                    </div>
                  ) : null}

                  {engineGame?.warnings.length ? (
                    <div className={styles.warningList}>
                      {engineGame.warnings.map((warning) => (
                        <div key={`${game.id}-${warning.code}`}>
                          <strong>{warning.code}</strong>
                          <span>{warning.message}</span>
                        </div>
                      ))}
                    </div>
                  ) : null}

                  {penalties.length > 0 ? (
                    <div className={styles.penalties}>
                      {penalties.map((penalty) => (
                        <span key={penalty.id}>
                          {penalty.side === "home" ? "HOME" : "AWAY"} ·{" "}
                          {penalty.jerseyNumber ? `#${penalty.jerseyNumber} ` : ""}
                          {penalty.playerName || "Team"} · {penalty.infraction} ·{" "}
                          {formatClock(
                            effectiveClock(
                              penalty.remainingMs,
                              penalty.running,
                              penalty.startedAt,
                              now,
                            ),
                          )}
                        </span>
                      ))}
                    </div>
                  ) : null}

                  {assignedDevices.length > 0 ? (
                    <div className={styles.devices}>
                      {assignedDevices.map((device) => (
                        <span
                          key={device.id}
                          className={
                            device.status === "ONLINE" ? styles.deviceOnline : styles.deviceOffline
                          }
                        >
                          {device.name}
                          {device.location ? ` · ${device.location}` : ""} · {device.status}
                        </span>
                      ))}
                    </div>
                  ) : null}

                  <div className={styles.actions}>
                    <Link href={`/games/${game.id}/control`}>Open Scorekeeper</Link>
                    <Link href={`/games/${game.id}/scoreboard`}>Public Scoreboard</Link>
                    <Link href={`/games/${game.id}/overlay`}>Broadcast Overlay</Link>
                    <Link href={`/system-health?gameId=${game.id}`}>Engine Health</Link>
                  </div>
                </article>
              );
                  })}
                </div>
              </section>
            ))}
          </section>
        </main>
      </AppShell>
    </AuthGate>
  );
}
