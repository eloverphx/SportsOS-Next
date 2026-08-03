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
  seasonName: string;
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
};

type ScoringAction =
  | { action: "adjustScore"; side: "home" | "away"; amount: number }
  | { action: "startClock" }
  | { action: "pauseClock" }
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
  const actionQueue = useRef<Promise<void>>(Promise.resolve());
  const pendingActions = useRef(0);

  const canScore = userHasPermission(user, PERMISSIONS.GAME_SCORE);

  const displayedClock = useMemo(
    () => (game ? formatClock(remainingMs(game, now)) : "--:--"),
    [game, now],
  );

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
                    disabled={!canScore}
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
                <span>PERIOD {game.period}</span>
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

            {!canScore && (
              <p className={styles.error}>
                Your account does not have permission to score this game.
              </p>
            )}
          </>
        )}
      </main>
    </AuthGate>
  );
}
