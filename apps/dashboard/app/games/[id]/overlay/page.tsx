"use client";

import type { BroadcastEffectPayload, PublicScoreboardGame, ScoreboardPenalty } from "@sportsos/core";

import { useParams, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import { createRealtimeSocket } from "../../../../lib/realtime";
import { API } from "../../../../lib/api";
import styles from "./overlay.module.css";

type Penalty = ScoreboardPenalty;
type Game = PublicScoreboardGame;

type BroadcastSessionProfile = {
  gameId: string;
  enabled: boolean;
  title: string | null;
  sponsorUrl: string | null;
  showPowerPlay: boolean;
  showTeamLogos: boolean;
  scenePreset:
    | "STANDARD"
    | "MINIMAL"
    | "SPONSOR_FOCUS";
  sponsorUrls: string[];
  sponsorRotationSeconds: number;
  soundEnabled: boolean;
  goalSoundUrl: string | null;
  penaltySoundUrl: string | null;
  hornSoundUrl: string | null;
  intermissionSoundUrl: string | null;
  updatedAt: string;
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

function BroadcastEffectCard({
  effect,
  game,
}: {
  effect:
    BroadcastEffectPayload;
  game:
    Game;
}) {
  const teamName =
    effect.side ===
      "home"
      ? game.homeTeamName
      : game.awayTeamName;

  const heading =
    effect.type ===
      "GOAL"
      ? "GOAL"
      : effect.type ===
          "PENALTY"
        ? "PENALTY"
        : "PENALTY ENDED";

  const detail =
    effect.type ===
      "GOAL"
      ? [
          effect.jerseyNumber
            ? `#${effect.jerseyNumber}`
            : null,
          effect.playerName ??
            null,
        ]
          .filter(Boolean)
          .join(" ")
      : effect.type ===
          "PENALTY"
        ? [
            effect.jerseyNumber
              ? `#${effect.jerseyNumber}`
              : null,
            effect.playerName ??
              null,
            effect.infraction ??
              null,
            effect.penaltyMinutes
              ? `${effect.penaltyMinutes} MIN`
              : null,
          ]
            .filter(Boolean)
            .join(" · ")
        : teamName;

  return (
    <section
      className={
        `${styles.effectCard} ${styles[`effect${effect.type.replaceAll("_", "")}`]}`
      }
      data-effect-type={
        effect.type
      }
      data-effect-side={
        effect.side
      }
    >
      <span>
        {teamName}
      </span>
      <strong>
        {heading}
      </strong>
      {detail && (
        <small>
          {detail}
        </small>
      )}
    </section>
  );
}

function playBroadcastSound(
  url: string | null,
): void {
  if (!url) {
    return;
  }

  const audio =
    new Audio(
      url,
    );

  audio.preload =
    "auto";

  void audio.play().catch(
    () => {
      // Browser/OBS autoplay policy may reject playback.
      // Audio failure must never affect overlay rendering or game state.
    },
  );
}

export default function OverlayPage() {
  const params = useParams<{ id: string }>();
  const search = useSearchParams();
  const gameId = Number(params.id);
  const [game, setGame] = useState<Game | null>(null);
  const [now, setNow] = useState(() => Date.now());
  const [profile, setProfile] =
    useState<BroadcastSessionProfile | null>(null);
  const [sponsorIndex, setSponsorIndex] =
    useState(0);
  const [
    activeEffect,
    setActiveEffect,
  ] =
    useState<BroadcastEffectPayload | null>(
      null,
    );

  const load = useCallback(async () => {
    const response = await fetch(`${API}/public/games/${gameId}/scoreboard`, { cache: "no-store" });
    const body = (await response.json()) as { game: Game };
    setGame(body.game);
  }, [gameId]);

  const loadBroadcastProfile =
    useCallback(async () => {
      const response = await fetch(
        `${API}/public/games/${gameId}/broadcast-session`,
        { cache: "no-store" },
      );

      if (!response.ok) {
        setProfile(null);
        return;
      }

      const body =
        (await response.json()) as {
          data?: {
            profile?: BroadcastSessionProfile | null;
          };
        };

      setProfile(
        body.data?.profile ??
        null,
      );
    }, [gameId]);

  useEffect(() => {
    void load();
    void loadBroadcastProfile();
    const socket = createRealtimeSocket(API);
    let connectedOnce = false;

    socket.on("connect", () => {
      socket.emit("public-game:subscribe", { gameId });

      if (!connectedOnce) {
        connectedOnce = true;
        return;
      }

      void load();
      void loadBroadcastProfile();
    });

    const refresh = (payload: { id?: number; gameId?: number; game?: { id?: number } }) => {
      if ((payload.gameId ?? payload.game?.id ?? payload.id) === gameId) void load();
    };
    socket.on("game:scored", refresh);
    socket.on("game:updated", refresh);
    socket.on("game:clock-expired", refresh);
    socket.on("game:intermission-expired", refresh);
    socket.on("game:event-created", refresh);
    socket.on("game:event-voided", refresh);
    socket.on("game:penalties-updated", refresh);

    socket.on(
      "scoreboard:sound",
      (payload) => {
        if (
          Number(
            payload.gameId,
          ) !==
          gameId ||
          !profile?.soundEnabled
        ) {
          return;
        }

        const url =
          payload.type ===
            "GOAL"
            ? profile.goalSoundUrl
            : payload.type ===
                "PENALTY"
              ? profile.penaltySoundUrl
              : payload.type ===
                  "HORN"
                ? profile.hornSoundUrl
                : profile.intermissionSoundUrl;

        playBroadcastSound(
          url,
        );
      },
    );

    socket.on(
      "scoreboard:effect",
      (
        payload:
          BroadcastEffectPayload,
      ) => {
        if (
          Number(
            payload.gameId,
          ) !==
          gameId
        ) {
          return;
        }

        setActiveEffect(
          payload,
        );
      },
    );

    socket.on(
      "broadcast-session:updated",
      (payload: {
        gameId?: number | string;
        profile?: BroadcastSessionProfile | null;
      }) => {
        if (
          String(
            payload.gameId ??
            "",
          ) ===
          String(
            gameId,
          )
        ) {
          setProfile(
            payload.profile ??
            null,
          );
        }
      },
    );

    socket.on(
      "broadcast-session:deleted",
      (payload: {
        gameId?: number | string;
      }) => {
        if (
          String(
            payload.gameId ??
            "",
          ) ===
          String(
            gameId,
          )
        ) {
          setProfile(
            null,
          );
        }
      },
    );
    return () => {
      socket.disconnect();
    };
  }, [gameId, load, loadBroadcastProfile]);

  // Broadcast effect auto-clear
  useEffect(() => {
    if (!activeEffect) {
      return;
    }

    const durationMs =
      activeEffect.type ===
        "GOAL"
        ? 5000
        : 4000;

    const timer =
      window.setTimeout(
        () => {
          setActiveEffect(
            null,
          );
        },
        durationMs,
      );

    return () => {
      window.clearTimeout(
        timer,
      );
    };
  }, [
    activeEffect,
  ]);

  // Sponsor rotation timer
  useEffect(() => {
    const sponsors =
      profile?.sponsorUrls ??
      [];

    if (sponsors.length <= 1) {
      setSponsorIndex(0);
      return;
    }

    const seconds =
      Math.max(
        3,
        profile?.sponsorRotationSeconds ??
          10,
      );

    const timer =
      window.setInterval(
        () => {
          setSponsorIndex(
            (current) =>
              (current + 1) %
              sponsors.length,
          );
        },
        seconds * 1000,
      );

    return () => {
      window.clearInterval(timer);
    };
  }, [
    profile?.sponsorUrls,
    profile?.sponsorRotationSeconds,
  ]);

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

  const effectiveTitle =
    search.get("title") ??
    profile?.title ??
    game.organizationName;

  const effectiveSponsorUrl =
    search.get("sponsorUrl") ??
    profile?.sponsorUrl ??
    null;

  const rotatingSponsorUrl =
    profile?.sponsorUrls?.[
      sponsorIndex %
      Math.max(
        1,
        profile?.sponsorUrls?.length ??
          1,
      )
    ] ??
    effectiveSponsorUrl;

  const scenePreset =
    profile?.scenePreset ??
    "STANDARD";

  const showPowerPlay =
    search.get("showPowerPlay") === "0"
      ? false
      : search.get("showPowerPlay") === "1"
        ? true
        : profile?.showPowerPlay ?? true;

  const showTeamLogos =
    search.get("showTeamLogos") === "0"
      ? false
      : search.get("showTeamLogos") === "1"
        ? true
        : profile?.showTeamLogos ?? true;

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
      {activeEffect && (
        <BroadcastEffectCard
          effect={
            activeEffect
          }
          game={
            game
          }
        />
      )}

      <section
        className={styles.bar}
        data-scene-preset={scenePreset}
      >
        <div className={`${styles.team} ${styles.away}`}>
          <div className={styles.logo}>
            {showTeamLogos ? <Logo url={game.awayTeamLogoUrl} name={game.awayTeamName} /> : null}
          </div>
          {scenePreset !== "MINIMAL" && (
            <strong>{game.awayTeamName}</strong>
          )}
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
          {scenePreset !== "SPONSOR_FOCUS" &&
            showPowerPlay &&
            powerPlay && (
              <small>
                POWER PLAY · {powerPlay}
              </small>
            )}
        </div>
        <div className={`${styles.team} ${styles.home}`}>
          <b>{game.homeScore}</b>
          {scenePreset !== "MINIMAL" && (
            <strong>{game.homeTeamName}</strong>
          )}
          <div className={styles.logo}>
            {showTeamLogos ? <Logo url={game.homeTeamLogoUrl} name={game.homeTeamName} /> : null}
          </div>
        </div>
      </section>

      <section
        className={
          scenePreset === "SPONSOR_FOCUS"
            ? `${styles.brandStrip} ${styles.sponsorFocus}`
            : styles.brandStrip
        }
      >
        <span>{effectiveTitle}</span>
        {rotatingSponsorUrl && <img src={rotatingSponsorUrl} alt="Sponsor" />}
      </section>
    </main>
  );
}
