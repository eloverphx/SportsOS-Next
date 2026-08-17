"use client";

import { useState } from "react";
import {
  buildFinalizedGameResult,
  resultLabel,
  type FinalizedGameResult,
} from "../../lib/tournament-game-result-finalization";

type Props = {
  gameId: string;
};

type LifecycleFinalizeResponse = {
  game?: {
    id?: string;
    homeScore?: number;
    awayScore?: number;
    status?: string;
    gamePhase?: string | null;
  };
};

export function GameResultFinalizationControl({
  gameId,
}: Props) {
  const [pending, setPending] = useState(false);
  const [confirmation, setConfirmation] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] =
    useState<FinalizedGameResult | null>(null);

  const finalizeGame = async () => {
    if (!confirmation || pending || result) return;

    setPending(true);
    setError(null);

    try {
      const response = await fetch(
        `/api/tournament/game-operations/${encodeURIComponent(gameId)}/finalize`,
        { method: "POST" },
      );

      const body = await response.text();

      if (!response.ok) {
        throw new Error(
          body ||
            `Game finalization request failed (${response.status}).`,
        );
      }

      let parsed: LifecycleFinalizeResponse;

      try {
        parsed = JSON.parse(body) as LifecycleFinalizeResponse;
      } catch {
        throw new Error(
          "Game finalization succeeded but the API response could not be parsed.",
        );
      }

      if (!parsed.game) {
        throw new Error(
          "Game finalization response did not include the authoritative game.",
        );
      }

      setResult(
        buildFinalizedGameResult({
          gameId: parsed.game.id ?? gameId,
          homeScore: parsed.game.homeScore,
          awayScore: parsed.game.awayScore,
          status: parsed.game.status,
          gamePhase: parsed.game.gamePhase,
        }),
      );
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : "Game finalization failed.",
      );
    } finally {
      setPending(false);
    }
  };

  return (
    <section
      data-testid="game-result-finalization-panel"
      className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="font-semibold text-slate-100">
            Game completion
          </h2>
          <p className="mt-1 text-xs leading-5 text-slate-500">
            Finalize the game through the authenticated lifecycle API and
            capture the authoritative final result.
          </p>
        </div>

        <span
          data-testid="game-result-finalization-status"
          className={
            result
              ? "text-sm font-semibold text-emerald-400"
              : "text-sm font-semibold text-slate-400"
          }
        >
          {result ? "FINAL" : "Not finalized"}
        </span>
      </div>

      {result ? (
        <div className="mt-4 rounded-lg border border-emerald-900/70 bg-emerald-950/20 p-4">
          <div className="text-xs font-semibold uppercase tracking-wide text-emerald-400">
            Authoritative final result
          </div>

          <div
            data-testid="final-game-score"
            className="mt-2 text-3xl font-bold text-slate-100"
          >
            {result.homeScore} – {result.awayScore}
          </div>

          <div className="mt-2 text-sm text-slate-300">
            {resultLabel(result)}
            {" · "}
            status {result.status}
            {result.gamePhase
              ? ` · phase ${result.gamePhase}`
              : ""}
          </div>
        </div>
      ) : (
        <div className="mt-4 space-y-3">
          <label className="flex items-start gap-3 rounded-lg border border-amber-900/60 bg-amber-950/20 p-3">
            <input
              type="checkbox"
              data-testid="confirm-game-finalization"
              checked={confirmation}
              onChange={(event) =>
                setConfirmation(event.target.checked)
              }
              className="mt-0.5"
            />

            <span className="text-xs leading-5 text-amber-200">
              I have reviewed the scoreboard and understand this will request
              the server's final game lifecycle transition.
            </span>
          </label>

          <button
            type="button"
            data-testid="finalize-game-result"
            disabled={!confirmation || pending}
            onClick={finalizeGame}
            className="w-full rounded-lg border border-red-900/70 bg-red-950/20 px-3 py-2 text-sm font-semibold text-red-300 transition hover:border-red-700 disabled:cursor-not-allowed disabled:opacity-40"
          >
            {pending ? "Finalizing..." : "Finalize game result"}
          </button>
        </div>
      )}

      {error ? (
        <div
          data-testid="game-result-finalization-error"
          className="mt-3 rounded-lg border border-red-900/60 bg-red-950/20 px-3 py-3 text-xs text-red-300"
        >
          {error}
        </div>
      ) : null}

      <p className="mt-3 text-xs leading-5 text-slate-500">
        The API remains authoritative. Invalid phase, permission, or lifecycle
        transitions are rejected server-side.
      </p>
    </section>
  );
}
