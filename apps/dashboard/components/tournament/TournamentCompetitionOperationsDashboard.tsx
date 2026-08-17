"use client";

import { useEffect, useMemo, useState } from "react";
import {
  buildTournamentCompetitionOperationsSummary,
} from "../../lib/tournament-competition-operations";
import type {
  TournamentStandingRow,
} from "../../lib/tournament-standings";
import type {
  TournamentBracketTree,
} from "../../lib/tournament-bracket-rounds";

type StandingsPayload = {
  teams?: unknown[];
  games?: Array<{
    status?: string;
  }>;
  standings?: TournamentStandingRow[];
};

type BracketPayload = {
  tree?: TournamentBracketTree;
};

function isFinalStatus(status: string | undefined) {
  const normalized = (status ?? "").trim().toUpperCase();

  return (
    normalized === "FINAL" ||
    normalized === "COMPLETE" ||
    normalized === "COMPLETED"
  );
}

export function TournamentCompetitionOperationsDashboard() {
  const [standings, setStandings] =
    useState<StandingsPayload | null>(null);
  const [bracket, setBracket] =
    useState<BracketPayload | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    const load = async () => {
      try {
        const [standingsResponse, bracketResponse] =
          await Promise.all([
            fetch("/api/tournament/standings", {
              cache: "no-store",
            }),
            fetch("/api/tournament/bracket", {
              cache: "no-store",
            }),
          ]);

        if (!standingsResponse.ok) {
          throw new Error(
            "Unable to load tournament standings.",
          );
        }

        if (!bracketResponse.ok) {
          throw new Error(
            "Unable to load tournament bracket.",
          );
        }

        const standingsPayload =
          (await standingsResponse.json()) as StandingsPayload;

        const bracketPayload =
          (await bracketResponse.json()) as BracketPayload;

        if (active) {
          setStandings(standingsPayload);
          setBracket(bracketPayload);
        }
      } catch (cause) {
        if (active) {
          setError(
            cause instanceof Error
              ? cause.message
              : "Unable to load tournament operations.",
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

  const summary = useMemo(() => {
    const games = standings?.games ?? [];
    const tree = bracket?.tree;

    const totalBracketMatchups =
      tree?.rounds.reduce(
        (total, round) => total + round.matchups.length,
        0,
      ) ?? 0;

    const resolvedBracketMatchups =
      tree?.rounds.reduce(
        (total, round) =>
          total +
          round.matchups.filter(
            (matchup) =>
              matchup.bye ||
              Boolean(
                matchup.homeSeed &&
                  matchup.awaySeed,
              ),
          ).length,
        0,
      ) ?? 0;

    return buildTournamentCompetitionOperationsSummary({
      totalTeams: standings?.teams?.length ?? 0,
      finalizedGames: games.filter((game) =>
        isFinalStatus(game.status),
      ).length,
      scheduledGames: games.length,
      seededTeams:
        standings?.standings?.length ?? 0,
      resolvedBracketMatchups,
      totalBracketMatchups,
      championResolved: Boolean(tree?.champion),
    });
  }, [bracket, standings]);

  if (loading) {
    return (
      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5 text-sm text-slate-400">
        Loading tournament competition operations...
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

  return (
    <section
      data-testid="tournament-competition-operations-dashboard"
      className="space-y-5"
    >
      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
              Competition stage
            </div>

            <div className="mt-1 text-2xl font-bold text-slate-100">
              {summary.stage.replaceAll("_", " ")}
            </div>
          </div>

          <div className="text-right">
            <div className="text-3xl font-bold text-slate-100">
              {summary.progressPercent}%
            </div>
            <div className="text-xs text-slate-500">
              tournament progress
            </div>
          </div>
        </div>

        <div className="mt-4 h-2 overflow-hidden rounded-full bg-slate-900">
          <div
            className="h-full bg-slate-400 transition-all"
            style={{
              width: `${summary.progressPercent}%`,
            }}
          />
        </div>

        {summary.alerts.length > 0 ? (
          <div className="mt-4 grid gap-2 md:grid-cols-2">
            {summary.alerts.map((alert) => (
              <div
                key={alert}
                className="rounded-lg border border-amber-900/50 bg-amber-950/20 px-3 py-2 text-xs text-amber-200"
              >
                {alert}
              </div>
            ))}
          </div>
        ) : null}
      </div>

      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Teams
          </div>
          <div className="mt-2 text-2xl font-bold text-slate-100">
            {standings?.teams?.length ?? 0}
          </div>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Scheduled games
          </div>
          <div className="mt-2 text-2xl font-bold text-slate-100">
            {standings?.games?.length ?? 0}
          </div>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Seeded teams
          </div>
          <div className="mt-2 text-2xl font-bold text-slate-100">
            {standings?.standings?.length ?? 0}
          </div>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Champion
          </div>
          <div className="mt-2 truncate text-lg font-bold text-slate-100">
            {bracket?.tree?.champion?.teamName ?? "TBD"}
          </div>
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <a
          href="/tournament/standings"
          className="rounded-xl border border-slate-800 bg-slate-950/40 p-5 transition hover:border-slate-700"
        >
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            Standings
          </div>
          <div className="mt-2 text-lg font-bold text-slate-100">
            Open tournament standings
          </div>
        </a>

        <a
          href="/tournament/bracket"
          className="rounded-xl border border-slate-800 bg-slate-950/40 p-5 transition hover:border-slate-700"
        >
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            Bracket
          </div>
          <div className="mt-2 text-lg font-bold text-slate-100">
            Open tournament bracket
          </div>
        </a>
      </div>
    </section>
  );
}
