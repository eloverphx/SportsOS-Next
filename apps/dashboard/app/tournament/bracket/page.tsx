import { TournamentBracketView } from "../../../components/tournament/TournamentBracketView";

export default function TournamentBracketPage() {
  return (
    <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
      <div className="mb-6">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          SportsOS Tournament Operations
        </div>

        <h1 className="mt-2 text-3xl font-bold text-slate-100">
          Tournament Bracket
        </h1>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Bracket seeds are generated directly from the current tournament
          standings. Seeding logic remains centralized in the shared bracket
          engine.
        </p>
      </div>

      <TournamentBracketView />
    </main>
  );
}
