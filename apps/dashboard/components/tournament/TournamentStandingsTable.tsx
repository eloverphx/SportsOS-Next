"use client";

import { useEffect, useState } from "react";
import type {
  TournamentStandingRow,
} from "../../lib/tournament-standings";

type PoolStandingsResponse = {
  poolId: string;
  poolName: string;
  standings: TournamentStandingRow[];
};

type StandingsResponse = {
  standings?: TournamentStandingRow[];
  poolStandings?: PoolStandingsResponse[];
  error?: string;
};

export function TournamentStandingsTable() {
  const [rows, setRows] = useState<TournamentStandingRow[]>([]);
  const [poolRows, setPoolRows] =
    useState<PoolStandingsResponse[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    const load = async () => {
      try {
        const response = await fetch("/api/tournament/standings", {
          cache: "no-store",
        });

        const payload = (await response.json()) as StandingsResponse;

        if (!response.ok) {
          throw new Error(
            payload.error ?? "Unable to load standings.",
          );
        }

        if (active) {
          setRows(payload.standings ?? []);
          setPoolRows(payload.poolStandings ?? []);
        }
      } catch (cause) {
        if (active) {
          setError(
            cause instanceof Error
              ? cause.message
              : "Unable to load standings.",
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
        Loading tournament standings...
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
      data-testid="tournament-standings-table"
      className="overflow-hidden rounded-xl border border-slate-800 bg-slate-950/40"
    >
      <div className="border-b border-slate-800 px-5 py-4">
        <h2 className="font-semibold text-slate-100">
          Current standings
        </h2>
        <p className="mt-1 text-xs text-slate-500">
          Finalized games only. Ranking: points, wins, goal differential,
          goals for, then team name.
        </p>
      </div>

      {poolRows.length > 1 ? (
        <div
          data-testid="tournament-pool-standings"
          className="border-b border-slate-800 px-5 py-4"
        >
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            Pools / divisions
          </div>

          <div className="mt-3 flex flex-wrap gap-2">
            {poolRows.map((pool) => (
              <span
                key={pool.poolId}
                className="rounded-full border border-slate-700 px-3 py-1 text-xs font-semibold text-slate-300"
              >
                {pool.poolName}: {pool.standings.length} teams
              </span>
            ))}
          </div>
        </div>
      ) : null}

      {rows.length === 0 ? (
        <div className="p-5 text-sm text-slate-400">
          No tournament games are available for standings yet.
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-slate-950/80 text-left text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-4 py-3">Rank</th>
                <th className="px-4 py-3">Team</th>
                <th className="px-4 py-3 text-center">GP</th>
                <th className="px-4 py-3 text-center">W</th>
                <th className="px-4 py-3 text-center">L</th>
                <th className="px-4 py-3 text-center">T</th>
                <th className="px-4 py-3 text-center">GF</th>
                <th className="px-4 py-3 text-center">GA</th>
                <th className="px-4 py-3 text-center">GD</th>
                <th className="px-4 py-3 text-center">PTS</th>
              </tr>
            </thead>

            <tbody>
              {rows.map((row) => (
                <tr
                  key={row.teamId}
                  data-testid={`standings-row-${row.teamId}`}
                  className="border-t border-slate-900 text-slate-200"
                >
                  <td className="px-4 py-3 font-bold">
                    {row.rank}
                  </td>
                  <td className="px-4 py-3 font-semibold">
                    {row.teamName}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {row.gamesPlayed}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {row.wins}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {row.losses}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {row.ties}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {row.goalsFor}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {row.goalsAgainst}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {row.goalDifferential}
                  </td>
                  <td className="px-4 py-3 text-center font-bold">
                    {row.points}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
