"use client";

import { useParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import { io } from "socket.io-client";
import { API } from "../../../../lib/api";
import styles from "./scoreboard.module.css";

type GameStatus = "SCHEDULED" | "LIVE" | "FINAL" | "POSTPONED" | "CANCELED";

type Penalty = {
  id: number;
  side: "home" | "away";
  playerName: string | null;
  infraction: string;
  remainingMs: number;
  running: boolean;
  startedAt: string | null;
};

type ScoreboardGame = {
  id: number;
  organizationName: string;
  seasonName: string;
  homeTeamName: string;
  awayTeamName: string;
  scheduledStart: string;
  timezone: string;
  venue: string | null;
  status: GameStatus;
  homeScore: number;
  awayScore: number;
  period: number;
  periodLengthMs: number;
  clockRemainingMs: number;
  clockRunning: boolean;
  clockStartedAt: string | null;
  penalties: Penalty[];
};

function effectiveRemainingMs(game: ScoreboardGame, now: number): number {
  if (!game.clockRunning || !game.clockStartedAt) return Math.max(0, game.clockRemainingMs);
  return Math.max(0, game.clockRemainingMs - (now - new Date(game.clockStartedAt).getTime()));
}

function formatClock(milliseconds: number): string {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

function statusLabel(game: ScoreboardGame): string {
  return game.status === "LIVE" && !game.clockRunning ? "LIVE · PAUSED" : game.status;
}

export default function ScoreboardPage() {
  const params = useParams<{ id: string }>();
  const gameId = Number(params.id);
  const [game, setGame] = useState<ScoreboardGame | null>(null);
  const [error, setError] = useState("");
  const [now, setNow] = useState(() => Date.now());

  const load = useCallback(async () => {
    if (!Number.isInteger(gameId) || gameId <= 0) {
      setError("Invalid game");
      return;
    }
    try {
      const response = await fetch(`${API}/public/games/${gameId}/scoreboard`, {
        cache: "no-store",
      });
      const body = (await response.json().catch(() => ({}))) as {
        game?: ScoreboardGame;
        error?: string;
      };
      if (!response.ok || !body.game)
        throw new Error(body.error ?? `Request failed (${response.status})`);
      setGame(body.game);
      setError("");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load scoreboard");
    }
  }, [gameId]);

  useEffect(() => {
    void load();
    const socket = io(API);
    const refreshForGame = (payload: { id?: number; game?: { id?: number } }) => {
      if ((payload.game?.id ?? payload.id) === gameId) void load();
    };
    socket.on("game:scored", refreshForGame);
    socket.on("game:updated", refreshForGame);
    socket.on("game:penalties-updated", refreshForGame);
    socket.on("game:event-created", refreshForGame);
    socket.on("game:event-voided", refreshForGame);
    return () => {
      socket.disconnect();
    };
  }, [gameId, load]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);

  const clock = useMemo(
    () => (game ? formatClock(effectiveRemainingMs(game, now)) : "--:--"),
    [game, now],
  );

  if (error)
    return (
      <main className={styles.center}>
        <section className={styles.message}>
          <h1>Scoreboard unavailable</h1>
          <p>{error}</p>
        </section>
      </main>
    );
  if (!game)
    return (
      <main className={styles.center}>
        <section className={styles.message}>
          <h1>Loading scoreboard…</h1>
        </section>
      </main>
    );

  return (
    <main className={styles.scoreboard}>
      <header className={styles.topbar}>
        <div>
          <strong>{game.organizationName}</strong>
          <span>{game.seasonName}</span>
        </div>
        <div className={styles.status}>{statusLabel(game)}</div>
      </header>
      <section className={styles.game}>
        <article className={styles.team}>
          <span className={styles.side}>AWAY</span>
          <h1>{game.awayTeamName}</h1>
          <div className={styles.score}>{game.awayScore}</div>
        </article>
        <section className={styles.clockPanel}>
          <span className={styles.period}>PERIOD {game.period}</span>
          <div className={styles.clock}>{clock}</div>
          <span className={styles.clockState}>{game.clockRunning ? "RUNNING" : "PAUSED"}</span>
        </section>
        <article className={styles.team}>
          <span className={styles.side}>HOME</span>
          <h1>{game.homeTeamName}</h1>
          <div className={styles.score}>{game.homeScore}</div>
        </article>
      </section>
      {game.penalties.length > 0 && (
        <section className={styles.penalties}>
          {game.penalties.map((penalty) => (
            <div key={penalty.id}>
              <strong>{penalty.side === "home" ? "HOME" : "AWAY"} PENALTY</strong>
              <span>
                {formatClock(
                  penalty.running && penalty.startedAt
                    ? Math.max(
                        0,
                        penalty.remainingMs - (now - new Date(penalty.startedAt).getTime()),
                      )
                    : penalty.remainingMs,
                )}
              </span>
              <small>{penalty.playerName || penalty.infraction}</small>
            </div>
          ))}
        </section>
      )}

      <footer className={styles.footer}>
        <span>{game.venue || "Venue not set"}</span>
        <span>{new Date(game.scheduledStart).toLocaleString()}</span>
      </footer>
    </main>
  );
}
