import { TournamentCompetitionOperationsDashboard } from "../../../components/tournament/TournamentCompetitionOperationsDashboard";

export default function TournamentCompetitionOperationsPage() {
  return (
    <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
      <div className="mb-6">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          SportsOS Tournament Operations
        </div>

        <h1 className="mt-2 text-3xl font-bold text-slate-100">
          Tournament Competition Dashboard
        </h1>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Monitor standings, seeding, bracket progression, and tournament
          completion from one operational surface.
        </p>
      </div>

      <TournamentCompetitionOperationsDashboard />
    </main>
  );
}
