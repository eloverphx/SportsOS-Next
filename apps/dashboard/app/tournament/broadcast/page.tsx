import { TournamentBroadcastOperatorPanel } from "../../../components/tournament/TournamentBroadcastOperatorPanel";

export default function TournamentBroadcastPage() {
  return (
    <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
      <div className="mb-6">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          SportsOS Broadcast Operations
        </div>

        <h1 className="mt-2 text-3xl font-bold text-slate-100">
          Broadcast Operator
        </h1>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Validate per-game streaming readiness before connecting an
          external transport such as OBS, RTMP, or another broadcast backend.
        </p>
      </div>

      <TournamentBroadcastOperatorPanel />
    </main>
  );
}
