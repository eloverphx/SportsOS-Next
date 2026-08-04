"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { io } from "socket.io-client";
import { AuthGate } from "../../../../components/AuthGate";
import { API, api } from "../../../../lib/api";
import {
  PERMISSIONS,
  getStoredUser,
  userHasPermission,
  type AuthenticatedUser,
} from "../../../../lib/auth";
import { GameEventsPanel } from "../../../../components/game-events/GameEventsPanel";
import "../../../../components/game-events/game-events.css";
import { ActivePenaltiesPanel } from "../../../../components/penalties/ActivePenaltiesPanel";
import "../../../../components/penalties/penalties.css";
import styles from "./control.module.css";

type GameStatus = "SCHEDULED" | "LIVE" | "FINAL" | "POSTPONED" | "CANCELED";

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

type Game = {
  id: number;
  organizationId: number;
  organizationName: string;
  seasonId: number;
  seasonName: string;
  homeTeamId: number | null;
  awayTeamId: number | null;
  homeTeamName: string;
  awayTeamName: string;
  scheduledStart: string;
  venue: string | null;
  status: GameStatus;
  homeScore: number;
  awayScore: number;
  period: number;
  periodLengthMs: number;
  clockRemainingMs: number;
  clockRunning: boolean;
  clockStartedAt: string | null;
  regulationPeriods: number;
  regulationPeriodLengthMs: number;
  intermissionLengthMs: number;
  intermissionRemainingMs: number;
  intermissionRunning: boolean;
  intermissionStartedAt: string | null;
  intermissionReady: boolean;
  overtimeEnabled: boolean;
  overtimeLengthMs: number;
  periodLabel: string;
  canAdvancePeriod: boolean;
};

type ScoringAction =
  | { action: "adjustScore"; side: "home" | "away"; amount: number }
  | { action: "startClock" }
  | { action: "pauseClock" }
  | { action: "startIntermission" }
  | { action: "pauseIntermission" }
  | { action: "resetIntermission" }
  | { action: "skipIntermission" }
  | { action: "nextPeriod" }
  | { action: "startOvertime" }
  | { action: "finishGame" }
  | { action: "resetClock" }
  | { action: "adjustClock"; amountMs: number }
  | { action: "setClock"; clockRemainingMs: number }
  | { action: "setPeriod"; period: number }
  | { action: "setStatus"; status: GameStatus };

function remainingMs(game: Game, now: number): number {
  if (!game.clockRunning || !game.clockStartedAt) {
    return Math.max(0, game.clockRemainingMs);
  }

  return Math.max(0, game.clockRemainingMs - (now - new Date(game.clockStartedAt).getTime()));
}

function intermissionRemainingMs(game: Game, now: number): number {
  if (!game.intermissionRunning || !game.intermissionStartedAt) {
    return Math.max(0, game.intermissionRemainingMs);
  }

  return Math.max(
    0,
    game.intermissionRemainingMs - (now - new Date(game.intermissionStartedAt).getTime()),
  );
}

function formatClock(milliseconds: number): string {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  return `${Math.floor(totalSeconds / 60)}:${String(totalSeconds % 60).padStart(2, "0")}`;
}

export default function ScoreboardControlPage() {
  const params = useParams<{ id: string }>();
  const deviceId = Number(params.id);

  const [user, setUser] = useState<AuthenticatedUser | null>(null);
  const [device, setDevice] = useState<Device | null>(null);
  const [game, setGame] = useState<Game | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [now, setNow] = useState(() => Date.now());
  const [minutes, setMinutes] = useState("20");
  const [seconds, setSeconds] = useState("00");
  const [eventRefreshToken, setEventRefreshToken] = useState(0);
  const [showPeriodEndDialog, setShowPeriodEndDialog] = useState(false);
  const actionQueue = useRef<Promise<void>>(Promise.resolve());
  const pendingActions = useRef(0);

  const canScore = userHasPermission(user, PERMISSIONS.GAME_SCORE);

  const displayedClockMs = useMemo(() => (game ? remainingMs(game, now) : 0), [game, now]);

  const displayedClock = formatClock(displayedClockMs);

  const displayedIntermissionMs = game ? intermissionRemainingMs(game, now) : 0;
  const displayedIntermission = formatClock(displayedIntermissionMs);

  const canAdvancePeriod = Boolean(game) && game?.status !== "FINAL" && displayedClockMs === 0;

  const load = useCallback(async () => {
    if (!Number.isInteger(deviceId) || deviceId <= 0) {
      setError("Invalid scoreboard device.");
      return;
    }

    try {
      const deviceResponse = await api<{ devices: Device[] }>("/scoreboard-devices");

      const selectedDevice = deviceResponse.devices.find((entry) => entry.id === deviceId) ?? null;

      if (!selectedDevice) {
        setDevice(null);
        setGame(null);
        setError("Scoreboard device not found.");
        return;
      }

      setDevice(selectedDevice);

      if (!selectedDevice.gameId) {
        setGame(null);
        setError("");
        return;
      }

      const gameResponse = await api<{ game: Game }>(`/games/${selectedDevice.gameId}`);

      setGame(gameResponse.game);
      setError("");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load scoreboard control.");
    }
  }, [deviceId]);

  useEffect(() => {
    setUser(getStoredUser());
  }, []);

  useEffect(() => {
    void load();

    const socket = io(API);

    const refreshForGame = (payload: { id?: number; game?: { id?: number } }) => {
      const changedGameId = payload.game?.id ?? payload.id;
      if (!game?.id || changedGameId === game.id) void load();
    };

    const refreshForDevice = (payload: { id?: number }) => {
      if (!payload.id || payload.id === deviceId) void load();
    };

    socket.on("game:scored", refreshForGame);
    socket.on("game:updated", refreshForGame);
    socket.on("game:deleted", refreshForGame);
    socket.on("game:event-created", () => {
      setEventRefreshToken((v) => v + 1);
      void load();
    });
    socket.on("game:penalties-updated", () => {
      setEventRefreshToken((v) => v + 1);
    });
    socket.on("game:event-voided", () => {
      setEventRefreshToken((v) => v + 1);
      void load();
    });
    socket.on("scoreboard-device:updated", refreshForDevice);
    socket.on("scoreboard-device:deleted", refreshForDevice);
    socket.on("scoreboard-device:status", refreshForDevice);

    return () => {
      socket.disconnect();
    };
  }, [deviceId, game?.id, load]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    if (!game) return;

    const totalSeconds = Math.ceil(game.periodLengthMs / 1000);

    setMinutes(String(Math.floor(totalSeconds / 60)));
    setSeconds(String(totalSeconds % 60).padStart(2, "0"));
  }, [game?.id, game?.periodLengthMs]);

  function score(action: ScoringAction): Promise<void> {
    if (!game || !canScore) {
      return Promise.resolve();
    }

    const gameId = game.id;

    pendingActions.current += 1;
    setBusy(true);
    setError("");

    const request = actionQueue.current.then(async () => {
      const response = await api<{ game: Game }>(`/games/${gameId}/scoring`, {
        method: "POST",
        body: JSON.stringify(action),
      });

      setGame(response.game);
      setEventRefreshToken((value) => value + 1);
    });

    actionQueue.current = request
      .catch((cause: unknown) => {
        setError(cause instanceof Error ? cause.message : "Could not update game.");
      })
      .finally(() => {
        pendingActions.current -= 1;

        if (pendingActions.current === 0) {
          setBusy(false);
        }
      });

    return request;
  }

  function advanceGameFlow(): void {
    if (!game || !canScore || !canAdvancePeriod) return;

    if (game.period >= game.regulationPeriods) {
      setShowPeriodEndDialog(true);
      return;
    }

    void score({ action: "nextPeriod" });
  }

  async function chooseOvertime(): Promise<void> {
    setShowPeriodEndDialog(false);
    await score({ action: "startOvertime" });
  }

  async function chooseFinal(): Promise<void> {
    setShowPeriodEndDialog(false);
    await score({ action: "finishGame" });
  }

  async function triggerHorn(): Promise<void> {
    if (!game || !canScore) return;

    setError("");

    try {
      await api(`/games/${game.id}/broadcast`, {
        method: "POST",
        body: JSON.stringify({ type: "HORN" }),
      });
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not trigger horn.");
    }
  }
  async function setExactClock(): Promise<void> {
    const minuteValue = Number(minutes);
    const secondValue = Number(seconds);

    if (
      !Number.isInteger(minuteValue) ||
      minuteValue < 0 ||
      !Number.isInteger(secondValue) ||
      secondValue < 0 ||
      secondValue > 59
    ) {
      setError("Enter valid minutes and seconds.");
      return;
    }

    await score({
      action: "setClock",
      clockRemainingMs: minuteValue * 60_000 + secondValue * 1000,
    });
  }

  return (
    <AuthGate>
      <main className={styles.page}>
        <header className={styles.header}>
          <div>
            <span className={styles.eyebrow}>Scoreboard control</span>
            <h1>{device?.name ?? "Loading device…"}</h1>
            <p>{device?.location || device?.organizationName || ""}</p>

            {game && (
              <p>
                Game rules: {game.regulationPeriods} × {game.regulationPeriodLengthMs / 60_000} min
                {game.overtimeEnabled ? ` · OT ${game.overtimeLengthMs / 60_000} min` : " · No OT"}
              </p>
            )}
          </div>

          <div className={styles.headerActions}>
            {device && (
              <span className={device.status === "ONLINE" ? styles.online : styles.offline}>
                {device.status}
              </span>
            )}

            <Link href="/scoreboards" className={styles.secondaryButton}>
              Back
            </Link>
          </div>
        </header>

        {error && <p className={styles.error}>{error}</p>}

        {!device && !error && (
          <section className={styles.message}>Loading scoreboard device…</section>
        )}

        {device && !device.gameId && (
          <section className={styles.message}>
            <h2>No game assigned</h2>
            <p>Assign a game to this device from the Scoreboards page.</p>
          </section>
        )}

        {device && game && (
          <>
            <section className={styles.scoreboard}>
              <article className={styles.teamPanel}>
                <span>AWAY</span>
                <h2>{game.awayTeamName}</h2>
                <strong>{game.awayScore}</strong>

                <div className={styles.scoreButtons}>
                  <button
                    disabled={!canScore || Boolean(game?.intermissionRunning)}
                    onClick={() =>
                      void score({
                        action: "adjustScore",
                        side: "away",
                        amount: -1,
                      })
                    }
                  >
                    −1
                  </button>

                  <button
                    disabled={!canScore}
                    onClick={() =>
                      void score({
                        action: "adjustScore",
                        side: "away",
                        amount: 1,
                      })
                    }
                  >
                    +1
                  </button>
                </div>
              </article>

              <section className={styles.clockPanel}>
                <span>{game.periodLabel ?? `PERIOD ${game.period}`}</span>
                <strong>{displayedClock}</strong>
                <small>
                  {game.clockRunning ? "RUNNING" : "PAUSED"} · {game.status}
                </small>

                <button
                  className={styles.primaryClockButton}
                  disabled={!canScore}
                  onClick={() =>
                    void score({
                      action: game.clockRunning ? "pauseClock" : "startClock",
                    })
                  }
                >
                  {game.clockRunning ? "PAUSE" : "START"}
                </button>
              </section>

              <article className={styles.teamPanel}>
                <span>HOME</span>
                <h2>{game.homeTeamName}</h2>
                <strong>{game.homeScore}</strong>

                <div className={styles.scoreButtons}>
                  <button
                    disabled={!canScore}
                    onClick={() =>
                      void score({
                        action: "adjustScore",
                        side: "home",
                        amount: -1,
                      })
                    }
                  >
                    −1
                  </button>

                  <button
                    disabled={!canScore}
                    onClick={() =>
                      void score({
                        action: "adjustScore",
                        side: "home",
                        amount: 1,
                      })
                    }
                  >
                    +1
                  </button>
                </div>
              </article>
            </section>

            <section className={styles.controls}>
              <div className={styles.controlGroup}>
                <h3>Period</h3>
                <div className={styles.buttonRow}>
                  <button
                    disabled={!canScore || game.period <= 1}
                    onClick={() =>
                      void score({
                        action: "setPeriod",
                        period: Math.max(1, game.period - 1),
                      })
                    }
                  >
                    Period −
                  </button>

                  <button
                    disabled={!canScore}
                    onClick={() =>
                      void score({
                        action: "setPeriod",
                        period: game.period + 1,
                      })
                    }
                  >
                    Period +
                  </button>

                  <button
                    className={styles.nextPeriodButton}
                    disabled={!canScore || !canAdvancePeriod}
                    onClick={advanceGameFlow}
                  >
                    {game.period >= game.regulationPeriods ? "End regulation" : "Next period"}
                  </button>
                </div>
              </div>

              <div className={styles.controlGroup}>
                <h3>Clock adjustment</h3>
                <div className={styles.buttonGrid}>
                  {[
                    ["−1m", -60_000],
                    ["+1m", 60_000],
                    ["−10s", -10_000],
                    ["+10s", 10_000],
                    ["−1s", -1_000],
                    ["+1s", 1_000],
                  ].map(([label, amount]) => (
                    <button
                      key={String(label)}
                      disabled={!canScore}
                      onClick={() =>
                        void score({
                          action: "adjustClock",
                          amountMs: Number(amount),
                        })
                      }
                    >
                      {label}
                    </button>
                  ))}
                </div>
              </div>

              <div className={styles.controlGroup}>
                <h3>Set and reset</h3>

                <div className={styles.clockInputs}>
                  <label>
                    Minutes
                    <input
                      type="number"
                      min="0"
                      max="120"
                      value={minutes}
                      onChange={(event) => setMinutes(event.target.value)}
                    />
                  </label>

                  <label>
                    Seconds
                    <input
                      type="number"
                      min="0"
                      max="59"
                      value={seconds}
                      onChange={(event) => setSeconds(event.target.value)}
                    />
                  </label>
                </div>

                <div className={styles.buttonRow}>
                  <button disabled={!canScore} onClick={() => void setExactClock()}>
                    Set clock
                  </button>

                  <button disabled={!canScore} onClick={() => void score({ action: "resetClock" })}>
                    Reset clock
                  </button>
                </div>
              </div>

              <div className={styles.controlGroup}>
                <h3>Intermission</h3>

                <div className={styles.intermissionClock}>
                  <strong>{displayedIntermission}</strong>
                  <span>
                    {game.intermissionRunning
                      ? "RUNNING · PENALTIES PAUSED"
                      : displayedIntermissionMs === 0
                        ? "READY FOR NEXT PERIOD"
                        : "PAUSED · PENALTIES PAUSED"}
                  </span>
                </div>

                <div className={styles.buttonRow}>
                  <button
                    disabled={!canScore || displayedClockMs > 0}
                    onClick={() =>
                      void score({
                        action: game.intermissionRunning
                          ? "pauseIntermission"
                          : "startIntermission",
                      })
                    }
                  >
                    {game.intermissionRunning ? "Pause intermission" : "Start intermission"}
                  </button>

                  <button
                    disabled={!canScore}
                    onClick={() => void score({ action: "resetIntermission" })}
                  >
                    Reset intermission
                  </button>

                  <button
                    disabled={!canScore}
                    onClick={() => void score({ action: "skipIntermission" })}
                  >
                    Skip intermission
                  </button>
                </div>
              </div>

              <div className={styles.controlGroup}>
                <h3>Broadcast</h3>

                <button
                  className={styles.hornButton}
                  disabled={!canScore}
                  onClick={() => void triggerHorn()}
                >
                  Manual horn
                </button>
              </div>

              <div className={styles.controlGroup}>
                <h3>Game status</h3>

                <div className={styles.buttonRow}>
                  <button
                    disabled={!canScore}
                    onClick={() =>
                      void score({
                        action: "setStatus",
                        status: "LIVE",
                      })
                    }
                  >
                    Mark live
                  </button>

                  <button
                    className={styles.finalButton}
                    disabled={!canScore}
                    onClick={() =>
                      void score({
                        action: "setStatus",
                        status: "FINAL",
                      })
                    }
                  >
                    Mark final
                  </button>
                </div>
              </div>
            </section>

            <ActivePenaltiesPanel
              gameId={game.id}
              homeTeamName={game.homeTeamName}
              awayTeamName={game.awayTeamName}
              canScore={canScore}
              refreshToken={eventRefreshToken}
            />

            <GameEventsPanel
              gameId={game.id}
              homeTeamId={game.homeTeamId}
              awayTeamId={game.awayTeamId}
              homeTeamName={game.homeTeamName}
              awayTeamName={game.awayTeamName}
              canScore={canScore}
              refreshToken={eventRefreshToken}
              onScoreChanged={load}
            />

            {!canScore && (
              <p className={styles.error}>
                Your account does not have permission to score this game.
              </p>
            )}

            {showPeriodEndDialog && (
              <div
                className={styles.periodEndBackdrop}
                role="presentation"
                onClick={() => setShowPeriodEndDialog(false)}
              >
                <section
                  className={styles.periodEndDialog}
                  role="dialog"
                  aria-modal="true"
                  aria-labelledby="period-end-title"
                  onClick={(event) => event.stopPropagation()}
                >
                  <span className={styles.eyebrow}>Regulation complete</span>

                  <h2 id="period-end-title">What happens next?</h2>

                  <p>
                    {game.awayTeamName} {game.awayScore} – {game.homeScore} {game.homeTeamName}
                  </p>

                  <div className={styles.periodEndActions}>
                    {game.overtimeEnabled && (
                      <button
                        type="button"
                        className={styles.overtimeButton}
                        onClick={() => void chooseOvertime()}
                      >
                        Start overtime
                      </button>
                    )}

                    <button
                      type="button"
                      className={styles.finalChoiceButton}
                      onClick={() => void chooseFinal()}
                    >
                      Mark game final
                    </button>

                    <button
                      type="button"
                      className={styles.cancelChoiceButton}
                      onClick={() => setShowPeriodEndDialog(false)}
                    >
                      Cancel
                    </button>
                  </div>
                </section>
              </div>
            )}
          </>
        )}
      </main>
    </AuthGate>
  );
}
