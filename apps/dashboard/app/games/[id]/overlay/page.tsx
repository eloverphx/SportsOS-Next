"use client";

import { useParams, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import { io } from "socket.io-client";
import { API } from "../../../../lib/api";
import styles from "./overlay.module.css";

type Penalty = {
  id: number;
  side: "home" | "away";
  remainingMs: number;
  running: boolean;
  startedAt: string | null;
};

type Game = {
  id: number;
  organizationName: string;
  organizationLogoUrl: string | null;
  homeTeamName: string;
  homeTeamLogoUrl: string | null;
  homeTeamPrimaryColor: string;
  awayTeamName: string;
  awayTeamLogoUrl: string | null;
  awayTeamPrimaryColor: string;
  homeScore: number;
  awayScore: number;
  period: number;
  gamePhase: "PREGAME" | "REGULATION" | "INTERMISSION" | "OVERTIME" | "FINAL";
  clockRemainingMs: number;
  clockRunning: boolean;
  clockStartedAt: string | null;
  intermissionRemainingMs: number;
  intermissionRunning: boolean;
  intermissionStartedAt: string | null;
  periodLabel: string;
  penalties: Penalty[];
};

function remaining(game: Game, now: number): number {
  if (!game.clockRunning || !game.clockStartedAt) return Math.max(0, game.clockRemainingMs);
  return Math.max(0, game.clockRemainingMs - (now - new Date(game.clockStartedAt).getTime()));
}

function penaltyRemaining(penalty: Penalty, now: number): number {
  if (!penalty.running || !penalty.startedAt) return Math.max(0, penalty.remainingMs);
  return Math.max(0, penalty.remainingMs - (now - new Date(penalty.startedAt).getTime()));
}

function effectiveIntermissionMs(
  game: {
    intermissionRunning: boolean;
    intermissionStartedAt: string | null;
    intermissionRemainingMs: number;
  },
  now: number,
): number {
  if (!game.intermissionRunning || !game.intermissionStartedAt) {
    return Math.max(0, game.intermissionRemainingMs);
  }

  return Math.max(
    0,
    game.intermissionRemainingMs - (now - new Date(game.intermissionStartedAt).getTime()),
  );
}

function formatClock(ms: number): string {
  const total = Math.max(0, Math.ceil(ms / 1000));
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}

function Logo({ url, name }: { url: string | null; name: string }) {
  return url ? (
    <img src={url} alt={`${name} logo`} />
  ) : (
    <span>{name.slice(0, 2).toUpperCase()}</span>
  );
}

export default function OverlayPage() {
  const params = useParams<{ id: string }>();
  const search = useSearchParams();
  const gameId = Number(params.id);
  const [game, setGame] = useState<Game | null>(null);
  const [now, setNow] = useState(() => Date.now());

  const load = useCallback(async () => {
    const response = await fetch(`${API}/public/games/${gameId}/scoreboard`, { cache: "no-store" });
    const body = (await response.json()) as { game: Game };
    setGame(body.game);
  }, [gameId]);

  useEffect(() => {
    void load();
    const socket = io(API);
    let connectedOnce = false;

    socket.on("connect", () => {
      socket.emit("public-game:subscribe", { gameId });

      if (!connectedOnce) {
        connectedOnce = true;
        return;
      }

      void load();
    });

    const refresh = (payload: { id?: number; gameId?: number; game?: { id?: number } }) => {
      if ((payload.gameId ?? payload.game?.id ?? payload.id) === gameId) void load();
    };
    [
      "game:scored",
      "game:updated",
      "game:clock-expired",
      "game:intermission-expired",
      "game:event-created",
      "game:event-voided",
      "game:penalties-updated",
    ].forEach((eventName) => socket.on(eventName, refresh));
    return () => {
      socket.disconnect();
    };
  }, [gameId, load]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);

  const powerPlay = useMemo(() => {
    if (!game) return null;
    const home = game.penalties.filter(
      (p) => p.side === "home" && penaltyRemaining(p, now) > 0,
    ).length;
    const away = game.penalties.filter(
      (p) => p.side === "away" && penaltyRemaining(p, now) > 0,
    ).length;
    if (home === away) return null;
    return home < away ? game.homeTeamName : game.awayTeamName;
  }, [game, now]);

  if (!game) return null;

  const title = search.get("title") || game.organizationName;
  const sponsorUrl = search.get("sponsorUrl");

  return (
    <main
      className={styles.overlay}
      style={
        {
          "--home-primary": game.homeTeamPrimaryColor,
          "--away-primary": game.awayTeamPrimaryColor,
        } as React.CSSProperties
      }
    >
      <section className={styles.bar}>
        <div className={`${styles.team} ${styles.away}`}>
          <div className={styles.logo}>
            <Logo url={game.awayTeamLogoUrl} name={game.awayTeamName} />
          </div>
          <strong>{game.awayTeamName}</strong>
          <b>{game.awayScore}</b>
        </div>
        <div className={styles.center}>
          <span>
            {game.gamePhase === "INTERMISSION"
              ? "INT"
              : game.periodLabel === "OVERTIME"
                ? "OT"
                : `P${game.period}`}
          </span>
          <strong>
            {game.gamePhase === "INTERMISSION"
              ? formatClock(effectiveIntermissionMs(game, now))
              : formatClock(remaining(game, now))}
          </strong>
          {powerPlay && <small>POWER PLAY · {powerPlay}</small>}
        </div>
        <div className={`${styles.team} ${styles.home}`}>
          <b>{game.homeScore}</b>
          <strong>{game.homeTeamName}</strong>
          <div className={styles.logo}>
            <Logo url={game.homeTeamLogoUrl} name={game.homeTeamName} />
          </div>
        </div>
      </section>

      <section className={styles.brandStrip}>
        <span>{title}</span>
        {sponsorUrl && <img src={sponsorUrl} alt="Sponsor" />}
      </section>
    </main>
  );
}
