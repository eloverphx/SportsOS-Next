import {
  ScoreboardDeviceOperations,
} from "../../components/scoreboards/ScoreboardDeviceOperations";

export default function ScoreboardsPage() {
  return (
    <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
      <div className="mb-6">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          SportsOS Hardware
        </div>

        <h1 className="mt-2 text-3xl font-bold text-slate-100">
          Scoreboard Devices
        </h1>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Monitor physical and simulated scoreboard devices connected through
          MQTT, review telemetry and state, and send safe device test commands.
        </p>
      </div>

      <ScoreboardDeviceOperations />
    </main>
  );
}
