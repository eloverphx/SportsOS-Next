"use client";

import { useParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { io } from "socket.io-client";
import { API } from "../../../../lib/api";
import styles from "./scoreboard.module.css";

type GameStatus = "SCHEDULED" | "LIVE" | "FINAL" | "POSTPONED" | "CANCELED";
type Side = "home" | "away";
type SoundType = "GOAL" | "PENALTY" | "HORN";

type Penalty = {
  id: number;
  side: Side;
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

type BroadcastEffect = {
  effectId: string;
  type: "GOAL" | "PENALTY" | "PENALTY_ENDED";
  side: Side;
  playerName?: string | null;
  jerseyNumber?: number | null;
  infraction?: string | null;
  penaltyMinutes?: number | null;
};

type BroadcastSound = {
  gameId?: number;
  soundId: string;
  type: SoundType;
};

function effectiveRemainingMs(game: ScoreboardGame, now: number): number {
  if (!game.clockRunning || !game.clockStartedAt) return Math.max(0, game.clockRemainingMs);
  return Math.max(0, game.clockRemainingMs - (now - new Date(game.clockStartedAt).getTime()));
}

function effectivePenaltyRemaining(penalty: Penalty, now: number): number {
  if (!penalty.running || !penalty.startedAt) return Math.max(0, penalty.remainingMs);
  return Math.max(0, penalty.remainingMs - (now - new Date(penalty.startedAt).getTime()));
}

function formatClock(milliseconds: number): string {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  return `${Math.floor(totalSeconds / 60)}:${String(totalSeconds % 60).padStart(2, "0")}`;
}

function statusLabel(game: ScoreboardGame): string {
  return game.status === "LIVE" && !game.clockRunning ? "LIVE · PAUSED" : game.status;
}

function playTone(context: AudioContext, frequency: number, start: number, duration: number): void {
  const oscillator = context.createOscillator();
  const gain = context.createGain();

  oscillator.type = "square";
  oscillator.frequency.setValueAtTime(frequency, start);

  gain.gain.setValueAtTime(0.0001, start);
  gain.gain.exponentialRampToValueAtTime(0.22, start + 0.02);
  gain.gain.exponentialRampToValueAtTime(0.0001, start + duration);

  oscillator.connect(gain);
  gain.connect(context.destination);
  oscillator.start(start);
  oscillator.stop(start + duration + 0.03);
}

function playSound(context: AudioContext, type: SoundType): void {
  const start = context.currentTime + 0.02;

  if (type === "GOAL") {
    playTone(context, 220, start, 0.9);
    playTone(context, 165, start + 0.12, 1.15);
    return;
  }

  if (type === "PENALTY") {
    playTone(context, 740, start, 0.16);
    playTone(context, 520, start + 0.22, 0.16);
    return;
  }

  playTone(context, 190, start, 1.25);
  playTone(context, 145, start + 0.08, 1.35);
}

export default function ScoreboardPage() {
  const params = useParams<{ id: string }>();
  const gameId = Number(params.id);

  const [game, setGame] = useState<ScoreboardGame | null>(null);
  const [error, setError] = useState("");
  const [now, setNow] = useState(() => Date.now());
  const [effect, setEffect] = useState<BroadcastEffect | null>(null);
  const [soundEnabled, setSoundEnabled] = useState(false);

  const seenEffects = useRef(new Set<string>());
  const seenSounds = useRef(new Set<string>());
  const effectTimer = useRef<number | null>(null);
  const previousPenaltyIds = useRef<Set<number> | null>(null);
  const audioContext = useRef<AudioContext | null>(null);
  const priorDisplayedClock = useRef<number | null>(null);
  const periodHornPlayed = useRef(false);

  const playBroadcastSound = useCallback(
    (sound: BroadcastSound) => {
      if (!soundEnabled || seenSounds.current.has(sound.soundId)) return;
      seenSounds.current.add(sound.soundId);

      const context = audioContext.current;
      if (!context) return;

      void context.resume().then(() => playSound(context, sound.type));
    },
    [soundEnabled],
  );

  const enableSound = useCallback(async () => {
    const context = audioContext.current ?? new AudioContext();
    audioContext.current = context;
    await context.resume();
    setSoundEnabled(true);
    playSound(context, "PENALTY");
  }, []);

  const showEffect = useCallback((next: BroadcastEffect) => {
    if (seenEffects.current.has(next.effectId)) return;
    seenEffects.current.add(next.effectId);
    setEffect(next);

    if (effectTimer.current !== null) window.clearTimeout(effectTimer.current);

    effectTimer.current = window.setTimeout(
      () => {
        setEffect(null);
        effectTimer.current = null;
      },
      next.type === "GOAL" ? 4500 : 3000,
    );
  }, []);

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

      if (!response.ok || !body.game) {
        throw new Error(body.error ?? `Request failed (${response.status})`);
      }

      const nextPenaltyIds = new Set(body.game.penalties.map((penalty) => penalty.id));
      const previous = previousPenaltyIds.current;

      if (previous !== null) {
        for (const oldId of previous) {
          if (!nextPenaltyIds.has(oldId)) {
            showEffect({
              effectId: `penalty-ended-${oldId}-${Date.now()}`,
              type: "PENALTY_ENDED",
              side: "home",
            });
            break;
          }
        }
      }

      previousPenaltyIds.current = nextPenaltyIds;
      setGame(body.game);
      setError("");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load scoreboard");
    }
  }, [gameId, showEffect]);

  useEffect(() => {
    void load();
    const socket = io(API);

    const refreshForGame = (payload: { id?: number; game?: { id?: number }; gameId?: number }) => {
      const changedId = payload.gameId ?? payload.game?.id ?? payload.id;
      if (changedId === gameId) void load();
    };

    socket.on("game:scored", refreshForGame);
    socket.on("game:updated", refreshForGame);
    socket.on("game:penalties-updated", refreshForGame);
    socket.on("game:event-created", refreshForGame);
    socket.on("game:event-voided", refreshForGame);

    socket.on("scoreboard:effect", (payload: BroadcastEffect & { gameId?: number }) => {
      if (payload.gameId === gameId) {
        showEffect(payload);
        void load();
      }
    });

    socket.on("scoreboard:sound", (payload: BroadcastSound) => {
      if (payload.gameId === gameId) playBroadcastSound(payload);
    });

    return () => {
      socket.disconnect();
      if (effectTimer.current !== null) window.clearTimeout(effectTimer.current);
    };
  }, [gameId, load, playBroadcastSound, showEffect]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);

  const displayedClockMs = useMemo(() => (game ? effectiveRemainingMs(game, now) : 0), [game, now]);

  useEffect(() => {
    if (!game) return;

    const previous = priorDisplayedClock.current;
    if (displayedClockMs > 0) periodHornPlayed.current = false;

    if (
      soundEnabled &&
      game.clockRunning &&
      previous !== null &&
      previous > 0 &&
      displayedClockMs === 0 &&
      !periodHornPlayed.current
    ) {
      periodHornPlayed.current = true;
      const context = audioContext.current;
      if (context) playSound(context, "HORN");
    }

    priorDisplayedClock.current = displayedClockMs;
  }, [displayedClockMs, game, soundEnabled]);

  const clock = formatClock(displayedClockMs);

  const powerPlaySide = useMemo<Side | null>(() => {
    if (!game) return null;

    const homePenalties = game.penalties.filter(
      (penalty) => penalty.side === "home" && effectivePenaltyRemaining(penalty, now) > 0,
    ).length;

    const awayPenalties = game.penalties.filter(
      (penalty) => penalty.side === "away" && effectivePenaltyRemaining(penalty, now) > 0,
    ).length;

    if (homePenalties === awayPenalties) return null;
    return homePenalties < awayPenalties ? "home" : "away";
  }, [game, now]);

  if (error) {
    return (
      <main className={styles.center}>
        <section className={styles.message}>
          <h1>Scoreboard unavailable</h1>
          <p>{error}</p>
        </section>
      </main>
    );
  }

  if (!game) {
    return (
      <main className={styles.center}>
        <section className={styles.message}>
          <h1>Loading scoreboard…</h1>
        </section>
      </main>
    );
  }

  const effectTeam = effect?.side === "home" ? game.homeTeamName : game.awayTeamName;

  return (
    <main className={styles.scoreboard}>
      {effect && (
        <section
          className={`${styles.effectOverlay} ${
            effect.type === "GOAL" ? styles.goalEffect : styles.noticeEffect
          }`}
          aria-live="assertive"
        >
          <strong>
            {effect.type === "GOAL"
              ? "GOAL!"
              : effect.type === "PENALTY"
                ? "PENALTY"
                : "PENALTY ENDED"}
          </strong>
          {effect.type !== "PENALTY_ENDED" && <span>{effectTeam}</span>}
          {effect.playerName && (
            <small>
              {effect.jerseyNumber == null ? "" : `#${effect.jerseyNumber} `}
              {effect.playerName}
            </small>
          )}
          {effect.type === "PENALTY" && effect.infraction && (
            <small>
              {effect.penaltyMinutes} MIN · {effect.infraction}
            </small>
          )}
        </section>
      )}

      <header className={styles.topbar}>
        <div>
          <strong>{game.organizationName}</strong>
          <span>{game.seasonName}</span>
        </div>

        <div className={styles.topbarActions}>
          <button
            type="button"
            className={soundEnabled ? styles.soundEnabled : styles.soundButton}
            onClick={() => void enableSound()}
          >
            {soundEnabled ? "Sound enabled" : "Enable sound"}
          </button>
          <div className={styles.status}>{statusLabel(game)}</div>
        </div>
      </header>

      {powerPlaySide && (
        <section className={styles.powerPlayBanner}>
          POWER PLAY · {powerPlaySide === "home" ? game.homeTeamName : game.awayTeamName}
        </section>
      )}

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
              <span>{formatClock(effectivePenaltyRemaining(penalty, now))}</span>
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
