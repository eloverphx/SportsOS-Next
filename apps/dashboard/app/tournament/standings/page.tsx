import { TournamentStandingsTable } from "../../../components/tournament/TournamentStandingsTable";

export default function TournamentStandingsPage() {
  return (
    <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
      <div className="mb-6">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          SportsOS Tournament Operations
        </div>

        <h1 className="mt-2 text-3xl font-bold text-slate-100">
          Tournament Standings
        </h1>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Standings are calculated from authoritative SportsOS game results.
          Games that are not finalized do not affect the table.
        </p>
      </div>

      <TournamentStandingsTable />
    </main>
  );
}
