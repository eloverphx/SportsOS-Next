import { EnrollmentTrustPanel } from "./EnrollmentTrustPanel";
import {
  ScoreboardHardwareOperationsDashboard,
} from "../../../components/scoreboards/ScoreboardHardwareOperationsDashboard";
import { PhysicalControlDiagnosticsPanel } from "./PhysicalControlDiagnosticsPanel";
import { PhysicalControlPolicyPanel } from "./PhysicalControlPolicyPanel";
import { ScoreboardCommissioningWizard } from "./ScoreboardCommissioningWizard";
import { GameDayHardwarePreflightPanel } from "./GameDayHardwarePreflightPanel";
import { BroadcastSessionPanel } from "./BroadcastSessionPanel";
import { StreamDestinationPanel } from "./StreamDestinationPanel";

export default function ScoreboardOperationsPage() {
  return (
    <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
      <EnrollmentTrustPanel />
      <div className="mb-6">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          SportsOS Hardware Operations
        </div>

        <h1 className="mt-2 text-3xl font-bold text-slate-100">
          Scoreboard Hardware Operations
        </h1>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Monitor physical and simulated scoreboards, manage game assignments,
          review device readiness, and manually reconcile hardware to the latest
          authoritative SportsOS game state.
        </p>
      </div>

      <ScoreboardHardwareOperationsDashboard />
    
      <a
        href="/scoreboards/firmware"
        className="rounded-lg border border-slate-700 px-3 py-2 text-sm"
      >
        Firmware Fleet
      </a>
      <ScoreboardCommissioningWizard />
      <GameDayHardwarePreflightPanel />
      <PhysicalControlPolicyPanel />
      <PhysicalControlDiagnosticsPanel />
      <BroadcastSessionPanel />
      <StreamDestinationPanel />
</main>
  );
}
