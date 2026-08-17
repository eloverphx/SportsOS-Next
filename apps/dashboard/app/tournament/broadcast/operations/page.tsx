import { TournamentBroadcastOperationsDashboard } from "../../../../components/tournament/TournamentBroadcastOperationsDashboard";

export default function TournamentBroadcastOperationsPage() {
  return (
    <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
      <div className="mb-6">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          SportsOS Broadcast Operations
        </div>

        <h1 className="mt-2 text-3xl font-bold text-slate-100">
          Broadcast Operations Dashboard
        </h1>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Monitor streaming readiness, browser-source output, realtime health,
          overlay eligibility, and operator branding from one workflow.
        </p>
      </div>

      <TournamentBroadcastOperationsDashboard />
    </main>
  );
}
