"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { io, type Socket } from "socket.io-client";
import type {
  BroadcastOverlaySnapshot,
} from "../../lib/broadcast-overlay-contract";
import {
  deriveSmoothedRemainingMs,
  formatOverlayClock,
} from "../../lib/broadcast-overlay-clock";
import {
  buildBroadcastOverlayTheme,
  overlayDensityClasses,
} from "../../lib/broadcast-overlay-theme";
import {
  BROADCAST_THEME_CHANGED_EVENT,
  readBroadcastOverlayThemeSettings,
} from "../../lib/broadcast-overlay-theme-sync";

type Props = {
  gameId: string;
};

type RealtimePayload = {
  gameId?: string;
};

const SOCKET_URL =
  process.env.NEXT_PUBLIC_SPORTSOS_SOCKET_URL ??
  process.env.NEXT_PUBLIC_API_URL ??
  "";

export function BroadcastOverlayClient({
  gameId,
}: Props) {
  const [snapshot, setSnapshot] =
    useState<BroadcastOverlaySnapshot | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [realtimeConnected, setRealtimeConnected] =
    useState(false);
  const [themeSettings, setThemeSettings] = useState(() =>
    buildBroadcastOverlayTheme(),
  );
  const [clockNowMs, setClockNowMs] = useState(
    () => Date.now(),
  );
  const clockAnchorRef = useRef<{
    remainingMs: number;
    running: boolean;
    capturedAtMs: number;
  } | null>(null);

  const loadInFlight = useRef(false);

  useEffect(() => {
    let active = true;
    let fallbackTimer: ReturnType<typeof setInterval> | null =
      null;
    let socket: Socket | null = null;

    const load = async () => {
      if (loadInFlight.current) {
        return;
      }

      loadInFlight.current = true;

      try {
        const response = await fetch(
          `/api/tournament/broadcast/overlay/${encodeURIComponent(gameId)}`,
          {
            cache: "no-store",
          },
        );

        if (!response.ok) {
          throw new Error(
            `Overlay snapshot request failed (${response.status}).`,
          );
        }

        const payload =
          (await response.json()) as BroadcastOverlaySnapshot;

        if (active) {
          setSnapshot(payload);
          clockAnchorRef.current = {
            remainingMs: payload.clock.remainingMs,
            running: payload.clock.running,
            capturedAtMs: Date.now(),
          };
          setClockNowMs(Date.now());
          setError(null);
        }
      } catch (cause) {
        if (active) {
          setError(
            cause instanceof Error
              ? cause.message
              : "Unable to load overlay snapshot.",
          );
        }
      } finally {
        loadInFlight.current = false;
      }
    };

    const refreshIfGameMatches = (
      payload?: RealtimePayload,
    ) => {
      if (
        !payload?.gameId ||
        payload.gameId === gameId
      ) {
        void load();
      }
    };

    void load();

    fallbackTimer = setInterval(() => {
      void load();
    }, 5000);

    if (SOCKET_URL) {
      socket = io(SOCKET_URL, {
        transports: ["websocket", "polling"],
        withCredentials: true,
      });

      socket.on("connect", () => {
        if (active) {
          setRealtimeConnected(true);
        }

        socket?.emit("game:join", {
          gameId,
        });

        void load();
      });

      socket.on("disconnect", () => {
        if (active) {
          setRealtimeConnected(false);
        }
      });

      socket.on("game:updated", refreshIfGameMatches);
      socket.on("game:event", refreshIfGameMatches);
      socket.on("scoreboard:update", refreshIfGameMatches);
      socket.on("game:state", refreshIfGameMatches);
    }

    return () => {
      active = false;

      if (fallbackTimer) {
        clearInterval(fallbackTimer);
      }

      if (socket) {
        socket.emit("game:leave", {
          gameId,
        });

        socket.disconnect();
      }
    };
  }, [gameId]);

  useEffect(() => {
    const timer = setInterval(() => {
      setClockNowMs(Date.now());
    }, 100);

    return () => {
      clearInterval(timer);
    };
  }, []);

  useEffect(() => {
    const refreshTheme = () => {
      setThemeSettings(
        buildBroadcastOverlayTheme(
          readBroadcastOverlayThemeSettings(
            window.localStorage,
          ),
        ),
      );
    };

    refreshTheme();

    const onStorage = (event: StorageEvent) => {
      if (
        !event.key ||
        event.key === "sportsos:broadcast-overlay-theme"
      ) {
        refreshTheme();
      }
    };

    window.addEventListener("storage", onStorage);
    window.addEventListener(
      BROADCAST_THEME_CHANGED_EVENT,
      refreshTheme,
    );

    return () => {
      window.removeEventListener("storage", onStorage);
      window.removeEventListener(
        BROADCAST_THEME_CHANGED_EVENT,
        refreshTheme,
      );
    };
  }, []);

  const displayedRemainingMs = useMemo(() => {
    const anchor = clockAnchorRef.current;

    if (!anchor) {
      return snapshot?.clock.remainingMs ?? 0;
    }

    return deriveSmoothedRemainingMs(
      anchor,
      clockNowMs,
    );
  }, [clockNowMs, snapshot]);

  const theme = useMemo(
    () => buildBroadcastOverlayTheme(themeSettings),
    [themeSettings],
  );

  const density = useMemo(
    () => overlayDensityClasses(theme.density),
    [theme.density],
  );

  const powerPlayLabel = useMemo(() => {
    if (!snapshot?.powerPlay) {
      return null;
    }

    const team =
      snapshot.powerPlay.teamId === snapshot.home.id
        ? snapshot.home
        : snapshot.powerPlay.teamId === snapshot.away.id
          ? snapshot.away
          : null;

    if (!team) {
      return null;
    }

    return `${team.shortName ?? team.name} PP ${formatOverlayClock(
      snapshot.powerPlay.remainingMs,
    )}`;
  }, [snapshot]);

  if (error && !snapshot) {
    return (
      <div
        data-testid="broadcast-overlay-error"
        className="flex h-screen w-screen items-center justify-center bg-transparent text-sm font-semibold text-red-400"
      >
        {error}
      </div>
    );
  }

  if (!snapshot) {
    return (
      <div className="h-screen w-screen bg-transparent" />
    );
  }

  return (
    <main
      data-testid="broadcast-browser-overlay"
      className="pointer-events-none relative h-screen w-screen overflow-hidden bg-transparent font-sans"
    >
      <div
        className="absolute inset-x-0 bottom-8 mx-auto flex w-[min(94vw,1200px)] items-stretch overflow-hidden rounded-2xl border border-white/15 shadow-2xl backdrop-blur"
        style={{
          backgroundColor: theme.panelBackground,
          color: theme.textColor,
        }}
      >
        <div
          className={`flex min-w-0 flex-1 items-center gap-4 ${density.padding}`}
          style={{
            borderLeft: "6px solid",
            borderLeftColor: theme.homeAccent,
          }}
        >
          {theme.showLogos && snapshot.home.logoUrl ? (
            <img
              src={snapshot.home.logoUrl}
              alt=""
              className="h-12 w-12 shrink-0 object-contain"
            />
          ) : null}

          <div className="min-w-0 flex-1">
            <div className={`truncate ${density.team} font-semibold uppercase tracking-wide`}
              style={{ color: theme.mutedTextColor }}>
              {snapshot.home.shortName ??
                snapshot.home.name}
            </div>
            <div
              data-testid="overlay-home-score"
              className={`${density.score} font-black leading-none`}
            >
              {snapshot.home.score}
            </div>
          </div>
        </div>

        <div className="flex min-w-[190px] flex-col items-center justify-center border-x border-white/10 px-5 py-3 text-center">
          <div
            data-testid="overlay-clock"
            className={`font-mono ${density.clock} font-black tabular-nums`}
          >
            {formatOverlayClock(displayedRemainingMs)}
          </div>

          <div className="mt-1 text-xs font-bold uppercase tracking-[0.18em] text-slate-400">
            {snapshot.period !== null
              ? `Period ${snapshot.period}`
              : snapshot.phase ?? snapshot.status}
          </div>

          {powerPlayLabel ? (
            <div
              data-testid="overlay-power-play"
              className="mt-2 rounded-full border border-amber-400/40 bg-amber-400/10 px-3 py-1 text-[11px] font-bold uppercase tracking-wide text-amber-300"
            >
              {powerPlayLabel}
            </div>
          ) : null}
        </div>

        <div className="flex min-w-0 flex-1 items-center gap-4 px-5 py-4 text-right">
          <div className="min-w-0 flex-1">
            <div className={`truncate ${density.team} font-semibold uppercase tracking-wide`}
              style={{ color: theme.mutedTextColor }}>
              {snapshot.away.shortName ??
                snapshot.away.name}
            </div>
            <div
              data-testid="overlay-away-score"
              className={`${density.score} font-black leading-none`}
            >
              {snapshot.away.score}
            </div>
          </div>

          {theme.showLogos && snapshot.away.logoUrl ? (
            <img
              src={snapshot.away.logoUrl}
              alt=""
              className="h-12 w-12 shrink-0 object-contain"
            />
          ) : null}
        </div>
      </div>

      <div className="absolute right-4 top-4 flex items-center gap-2">
        <span
          data-testid="overlay-realtime-state"
          className={
            realtimeConnected
              ? "rounded-full bg-emerald-950/80 px-3 py-1 text-[10px] font-bold uppercase tracking-wide text-emerald-300"
              : "rounded-full bg-amber-950/80 px-3 py-1 text-[10px] font-bold uppercase tracking-wide text-amber-300"
          }
        >
          {realtimeConnected
            ? "Realtime"
            : "Fallback polling"}
        </span>

        {error ? (
          <span className="rounded-lg bg-red-950/80 px-3 py-2 text-xs font-semibold text-red-300">
            Data reconnecting
          </span>
        ) : null}
      </div>
    </main>
  );
}
