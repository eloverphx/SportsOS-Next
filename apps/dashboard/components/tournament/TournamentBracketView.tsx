"use client";

import { useEffect, useState } from "react";
import type {
  TournamentBracketTree,
} from "../../lib/tournament-bracket-rounds";

type BracketResponse = {
  tree?: TournamentBracketTree;
  error?: string;
};

function TeamSlot({
  seed,
  name,
  emptyLabel,
}: {
  seed: number | null;
  name: string | null;
  emptyLabel: string;
}) {
  return (
    <div className="flex items-center gap-3 rounded-lg border border-slate-800 bg-slate-950/60 px-3 py-2">
      <div className="w-8 text-center text-xs font-bold text-slate-500">
        {seed ?? "—"}
      </div>

      <div className="min-w-0 flex-1 truncate text-sm font-semibold text-slate-200">
        {name ?? emptyLabel}
      </div>
    </div>
  );
}

export function TournamentBracketView() {
  const [tree, setTree] =
    useState<TournamentBracketTree | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    const load = async () => {
      try {
        const response = await fetch("/api/tournament/bracket", {
          cache: "no-store",
        });

        const payload = (await response.json()) as BracketResponse;

        if (!response.ok) {
          throw new Error(
            payload.error ?? "Unable to load tournament bracket.",
          );
        }

        if (active) {
          setTree(payload.tree ?? null);
        }
      } catch (cause) {
        if (active) {
          setError(
            cause instanceof Error
              ? cause.message
              : "Unable to load tournament bracket.",
          );
        }
      } finally {
        if (active) {
          setLoading(false);
        }
      }
    };

    void load();

    return () => {
      active = false;
    };
  }, []);

  if (loading) {
    return (
      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5 text-sm text-slate-400">
        Loading tournament bracket...
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-xl border border-red-900/60 bg-red-950/20 p-5 text-sm text-red-300">
        {error}
      </div>
    );
  }

  if (!tree || tree.fieldSize === 0) {
    return (
      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5 text-sm text-slate-400">
        No seeded teams are available yet.
      </div>
    );
  }

  return (
    <section
      data-testid="tournament-bracket-view"
      className="space-y-5"
    >
      {tree.champion ? (
        <div
          data-testid="tournament-bracket-champion"
          className="rounded-xl border border-emerald-900/60 bg-emerald-950/20 p-5"
        >
          <div className="text-xs font-semibold uppercase tracking-wide text-emerald-400">
            Tournament champion
          </div>

          <div className="mt-2 text-2xl font-bold text-slate-100">
            #{tree.champion.seed} {tree.champion.teamName}
          </div>
        </div>
      ) : null}

      <div className="overflow-x-auto pb-2">
        <div className="flex min-w-max gap-5">
          {tree.rounds.map((round) => (
            <section
              key={round.round}
              data-testid={`tournament-bracket-round-${round.round}`}
              className="w-[320px] shrink-0 rounded-xl border border-slate-800 bg-slate-950/40 p-4"
            >
              <div className="mb-4">
                <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Round {round.round}
                </div>
                <h2 className="mt-1 text-lg font-bold text-slate-100">
                  {round.name}
                </h2>
              </div>

              <div className="space-y-4">
                {round.matchups.map((matchup) => (
                  <div
                    key={matchup.id}
                    data-testid={`bracket-matchup-${matchup.id}`}
                    className="rounded-xl border border-slate-800 bg-slate-950/50 p-3"
                  >
                    <div className="mb-3 flex items-center justify-between gap-2">
                      <span className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                        Matchup {matchup.slot}
                      </span>

                      {matchup.bye ? (
                        <span className="rounded-full border border-emerald-900/60 bg-emerald-950/20 px-2 py-1 text-[10px] font-semibold uppercase tracking-wide text-emerald-300">
                          Bye
                        </span>
                      ) : null}
                    </div>

                    <div className="space-y-2">
                      <TeamSlot
                        seed={matchup.homeSeed?.seed ?? null}
                        name={matchup.homeSeed?.teamName ?? null}
                        emptyLabel="TBD"
                      />

                      <TeamSlot
                        seed={matchup.awaySeed?.seed ?? null}
                        name={matchup.awaySeed?.teamName ?? null}
                        emptyLabel={
                          matchup.bye ? "BYE" : "TBD"
                        }
                      />
                    </div>
                  </div>
                ))}
              </div>
            </section>
          ))}
        </div>
      </div>
    </section>
  );
}
