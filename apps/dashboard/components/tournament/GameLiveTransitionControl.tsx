"use client";

import { useMemo, useState } from "react";
import type { GameStartAuthorizationRecord } from "../../lib/tournament-game-start-authorization";
import {
  computeGameStartTiming,
  formatDelayLabel,
} from "../../lib/tournament-game-start-tracking";

type Props = {
  gameId: string;
  scheduledStart: string | null;
  authorization: GameStartAuthorizationRecord | null;
};

type LifecycleStartResponse = {
  game?: {
    clockStartedAt?: string | null;
    scheduledStart?: string;
    status?: string;
    gamePhase?: string;
  };
};

function formatTimestamp(value: string | null): string {
  if (!value) return "Not scheduled";

  const date = new Date(value);

  if (!Number.isFinite(date.getTime())) return value;

  return date.toLocaleString();
}

export function GameLiveTransitionControl({
  gameId,
  scheduledStart,
  authorization,
}: Props) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [actualStart, setActualStart] = useState<string | null>(null);
  const [startAccepted, setStartAccepted] = useState(false);

  const timing = useMemo(
    () => computeGameStartTiming(scheduledStart, actualStart),
    [actualStart, scheduledStart],
  );

  const requestLiveTransition = async () => {
    if (!authorization || pending || startAccepted) {
      return;
    }

    setPending(true);
    setError(null);

    try {
      const response = await fetch(
        `/api/tournament/game-operations/${encodeURIComponent(gameId)}/start`,
        {
          method: "POST",
        },
      );

      const body = await response.text();

      if (!response.ok) {
        throw new Error(
          body || `Game start request failed (${response.status}).`,
        );
      }

      let parsed: LifecycleStartResponse = {};

      try {
        parsed = body ? JSON.parse(body) : {};
      } catch {
        throw new Error(
          "Game start was accepted but the API response could not be parsed.",
        );
      }

      const authoritativeActualStart =
        parsed.game?.clockStartedAt ?? null;

      if (!authoritativeActualStart) {
        throw new Error(
          "Game start response did not include authoritative clockStartedAt.",
        );
      }

      setActualStart(authoritativeActualStart);
      setStartAccepted(true);
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : "Game start request failed.",
      );
    } finally {
      setPending(false);
    }
  };

  return (
    <section
      data-testid="live-game-transition-panel"
      className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="font-semibold text-slate-100">
            Live game state
          </h2>
          <p className="mt-1 text-xs leading-5 text-slate-500">
            Start the game through the authenticated SportsOS lifecycle API.
          </p>
        </div>

        <span
          data-testid="live-game-transition-status"
          className={
            startAccepted
              ? "text-sm font-semibold text-emerald-400"
              : "text-sm font-semibold text-slate-400"
          }
        >
          {startAccepted ? "LIVE start accepted" : "Awaiting start"}
        </span>
      </div>

      <div
        data-testid="game-start-timing"
        className="mt-4 grid gap-3 md:grid-cols-3"
      >
        <div className="rounded-lg border border-slate-800 bg-slate-950/60 p-3">
          <div className="text-[10px] font-semibold uppercase tracking-wide text-slate-500">
            Scheduled
          </div>
          <div className="mt-1 text-sm font-semibold text-slate-200">
            {formatTimestamp(scheduledStart)}
          </div>
        </div>

        <div className="rounded-lg border border-slate-800 bg-slate-950/60 p-3">
          <div className="text-[10px] font-semibold uppercase tracking-wide text-slate-500">
            Actual start
          </div>
          <div
            data-testid="actual-game-start"
            className="mt-1 text-sm font-semibold text-slate-200"
          >
            {formatTimestamp(actualStart)}
          </div>
        </div>

        <div className="rounded-lg border border-slate-800 bg-slate-950/60 p-3">
          <div className="text-[10px] font-semibold uppercase tracking-wide text-slate-500">
            Start variance
          </div>
          <div
            data-testid="game-start-delay"
            className={
              timing.state === "DELAYED"
                ? "mt-1 text-sm font-semibold text-amber-400"
                : timing.state === "EARLY"
                  ? "mt-1 text-sm font-semibold text-sky-400"
                  : timing.state === "ON_TIME"
                    ? "mt-1 text-sm font-semibold text-emerald-400"
                    : "mt-1 text-sm font-semibold text-slate-400"
            }
          >
            {formatDelayLabel(timing)}
          </div>
        </div>
      </div>

      {!authorization ? (
        <div className="mt-4 rounded-lg border border-amber-900/60 bg-amber-950/20 px-3 py-3 text-sm text-amber-300">
          Game-start authorization is required before a live transition can be
          requested.
        </div>
      ) : (
        <div className="mt-4">
          <div className="rounded-lg border border-slate-800 bg-slate-950/60 px-3 py-3 text-xs text-slate-400">
            Authorized by{" "}
            <span className="font-semibold text-slate-200">
              {authorization.authorizedBy}
            </span>
            {" · "}
            {authorization.mode === "normal"
              ? "normal readiness"
              : "testing-override operations record"}
          </div>

          <button
            type="button"
            data-testid="request-live-game-transition"
            disabled={pending || startAccepted}
            onClick={requestLiveTransition}
            className="mt-3 w-full rounded-lg border border-emerald-800/70 bg-emerald-950/20 px-3 py-2 text-sm font-semibold text-emerald-300 transition hover:border-emerald-600 disabled:cursor-not-allowed disabled:opacity-40"
          >
            {pending
              ? "Requesting start..."
              : startAccepted
                ? "Game start recorded"
                : "Start live game"}
          </button>
        </div>
      )}

      {error ? (
        <div
          data-testid="live-game-transition-error"
          className="mt-3 rounded-lg border border-red-900/60 bg-red-950/20 px-3 py-3 text-xs text-red-300"
        >
          {error}
        </div>
      ) : null}

      <p className="mt-3 text-xs leading-5 text-slate-500">
        Actual start comes from the API's authoritative clockStartedAt value.
        Delay is derived from actual start minus scheduled start; the browser
        does not invent the game-start timestamp.
      </p>
    </section>
  );
}
