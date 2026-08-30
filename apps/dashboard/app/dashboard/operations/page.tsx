import {
  getOperationsIncidents,
  getOperationsStatus,
  type OperationResult,
  type OperationsSeverityReason,
} from "./operationsStatus";


type RecoveryGuardrailService = {
  service: string;
  policy: "auto" | "monitor";
  restartCount?: number;
  guardrailState:
    | "ready"
    | "cooldown"
    | "budget-exhausted"
    | "monitor-only";
  eligible: boolean;
  blockedReason:
    | "cooldown"
    | "budget-exhausted"
    | "monitor-only"
    | null;
  successfulActionsInWindow: number;
  remainingBudget: number;
  cooldownRemainingSeconds: number;
};

// SPORTSOS_M33_6_5_DASHBOARD_GUARDRAILS
export const dynamic = "force-dynamic";

function statusText(result: OperationResult | null): string {
  if (!result) return "No recent run";
  return result.status;
}

function finishedText(result: OperationResult | null): string {
  if (!result?.finishedAt) return "No timestamp";
  return new Date(result.finishedAt).toLocaleString();
}

function OperationCard({
  title,
  result,
}: {
  title: string;
  result: OperationResult | null;
}) {
  return (
    <div className="rounded-xl border border-slate-800 bg-slate-950/50 p-4">
      <div className="text-xs font-medium uppercase tracking-wide text-slate-500">
        {title}
      </div>
      <div className="mt-2 text-lg font-semibold text-slate-100">
        {statusText(result)}
      </div>
      <div className="mt-1 text-sm text-slate-400">
        {finishedText(result)}
      </div>
      {result ? (
        <div className="mt-2 text-xs text-slate-500">
          Exit code: {result.exitCode}
        </div>
      ) : null}
    </div>
  );
}

function SeverityReason({
  item,
}: {
  item: OperationsSeverityReason;
}) {
  return (
    <li className="rounded-lg border border-slate-800 p-3">
      <span className="font-semibold uppercase text-slate-300">
        {item.severity}
      </span>
      <span className="text-slate-400"> — {item.reason}</span>
    </li>
  );
}

import { IncidentActions } from "./IncidentActions"; // SPORTSOS_M34_7_DASHBOARD_ACTIONS
export default async function OperationsPage() {
  const incidentsResponse = await getOperationsIncidents();
  const incidentData = incidentsResponse.data;

  const response = await getOperationsStatus();

  if (!response.success || !response.data) {
    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-slate-100">
            Production Operations
          </h1>
          <p className="mt-1 text-slate-400">
            Protected production reliability and recovery status.
          </p>
        </div>

        <div className="rounded-xl border border-amber-900/50 bg-amber-950/20 p-5">
          <h2 className="font-semibold text-amber-200">
            Operations status unavailable
          </h2>
          <p className="mt-2 text-sm text-amber-100/80">
            {response.error ?? "Unable to load operations status."}
          </p>
        </div>
      </div>
    );
  }

  const data = response.data;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-100">
          Production Operations
        </h1>
        <p className="mt-1 text-slate-400">
          Protected production reliability and recovery status.
        </p>
        <p className="mt-1 text-xs text-slate-500">
          Snapshot generated {new Date(data.generatedAt).toLocaleString()}
        </p>
      </div>

      <section className="rounded-xl border border-slate-800 bg-slate-950/50 p-5">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="text-lg font-semibold text-slate-100">
              Operations severity
            </h2>
            <p className="mt-1 text-sm text-slate-400">
              Normalized production reliability state for the last{" "}
              {data.windowHours} hours.
            </p>
          </div>
          <div className="rounded-full border border-slate-700 px-3 py-1 text-sm font-semibold uppercase tracking-wide text-slate-200">
            {data.severity.status}
          </div>
        </div>

        <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs uppercase tracking-wide text-slate-500">
              Failure rate
            </div>
            <div className="mt-1 text-xl font-semibold text-slate-100">
              {data.severity.summary.failureRatePercent}%
            </div>
          </div>

          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs uppercase tracking-wide text-slate-500">
              Failed runs
            </div>
            <div className="mt-1 text-xl font-semibold text-slate-100">
              {data.severity.summary.failedRuns}
            </div>
          </div>

          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs uppercase tracking-wide text-slate-500">
              Passed runs
            </div>
            <div className="mt-1 text-xl font-semibold text-slate-100">
              {data.severity.summary.passedRuns}
            </div>
          </div>

          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs uppercase tracking-wide text-slate-500">
              Failure streak
            </div>
            <div className="mt-1 text-xl font-semibold text-slate-100">
              {data.severity.summary.maxFailureStreak}
            </div>
          </div>
        </div>

        {data.severity.reasons.length > 0 ? (
          <div className="mt-5">
            <h3 className="text-sm font-medium text-slate-300">
              Severity reasons
            </h3>
            <ul className="mt-2 space-y-2 text-sm">
              {data.severity.reasons.map((item, index) => (
                <SeverityReason
                  key={`${item.severity}-${index}`}
                  item={item}
                />
              ))}
            </ul>
          </div>
        ) : null}
      </section>

      <section>
        <h2 className="mb-3 text-lg font-semibold text-slate-100">
          Latest production operations
        </h2>
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          <OperationCard title="Health" result={data.latest.health} />
          <OperationCard title="MySQL backup" result={data.latest.backup} />
          <OperationCard
            title="Persistent backup"
            result={data.latest.persistentBackup}
          />
          <OperationCard title="Recovery" result={data.latest.recovery} />
          <OperationCard
            title="Restore rehearsal"
            result={data.latest.restoreRehearsal}
          />
          <OperationCard
            title="Reliability alert"
            result={data.latest.reliabilityAlert}
          />
        </div>
      </section>

      <section className="rounded-xl border border-slate-800 bg-slate-950/50 p-5">
        <h2 className="text-lg font-semibold text-slate-100">
          Recent operations
        </h2>
        <div className="mt-4 grid gap-3 sm:grid-cols-3">
          <div>
            <div className="text-xs uppercase tracking-wide text-slate-500">
              Total
            </div>
            <div className="mt-1 text-xl font-semibold text-slate-100">
              {data.recent.totalRuns}
            </div>
          </div>
          <div>
            <div className="text-xs uppercase tracking-wide text-slate-500">
              Passed
            </div>
            <div className="mt-1 text-xl font-semibold text-slate-100">
              {data.recent.passedRuns}
            </div>
          </div>
          <div>
            <div className="text-xs uppercase tracking-wide text-slate-500">
              Failed
            </div>
            <div className="mt-1 text-xl font-semibold text-slate-100">
              {data.recent.failedRuns}
            </div>
          </div>
        </div>
      </section>

      {data.reliability?.issues.length ? (
        <section className="rounded-xl border border-slate-800 bg-slate-950/50 p-5">
          <h2 className="text-lg font-semibold text-slate-100">
            Reliability issues
          </h2>
          <ul className="mt-3 space-y-2 text-sm text-slate-400">
            {data.reliability.issues.map((issue, index) => (
              <li
                key={`${issue.type}-${issue.mode}-${index}`}
                className="rounded-lg border border-slate-800 p-3"
              >
                <div className="font-medium text-slate-300">
                  {issue.type} / {issue.mode}
                </div>
                <div className="mt-1">{issue.message}</div>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {/* SPORTSOS_M33_3_RECOVERY_DASHBOARD */}
      {response.data?.recovery ? (
        <section className="mt-8 space-y-4">
          <div>
            <h2 className="text-xl font-semibold">Runtime Recovery</h2>
            <p className="text-sm text-slate-400">
              Bounded production self-healing status and recent recovery activity.
            </p>
          </div>

          <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
            <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
              <div className="text-sm text-slate-400">Recovery mode</div>
              <div className="mt-1 text-lg font-semibold capitalize">
                {response.data?.recovery.mode}
              </div>
            </div>
            <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
              <div className="text-sm text-slate-400">Successful recoveries</div>
              <div className="mt-1 text-lg font-semibold">
                {response.data?.recovery.summary.totalSuccessfulRecoveries}
              </div>
            </div>
            <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
              <div className="text-sm text-slate-400">Blocked recoveries</div>
              <div className="mt-1 text-lg font-semibold">
                {response.data?.recovery.summary.totalBlockedRecoveries}
              </div>
            </div>
            <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
              <div className="text-sm text-slate-400">Failed recoveries</div>
              <div className="mt-1 text-lg font-semibold">
                {response.data?.recovery.summary.totalFailedRecoveries}
              </div>
            </div>
          </div>

          <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
            <h3 className="font-semibold">Recovery guardrails</h3>
            <div className="mt-3 grid gap-3 text-sm sm:grid-cols-2 lg:grid-cols-4">
              <div>Cooldown: {response.data?.recovery.defaults.cooldownSeconds}s</div>
              <div>
                Budget: {response.data?.recovery.defaults.maxActionsPerWindow} /{" "}
                {response.data?.recovery.defaults.budgetWindowSeconds}s
              </div>
              <div>
                Restart delta: {response.data?.recovery.defaults.restartDeltaThreshold}
              </div>
              <div>
                Health timeout: {response.data?.recovery.defaults.postRecoveryTimeoutSeconds}s
              </div>
            </div>
          </div>

          <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
            <h3 className="font-semibold">Service recovery policy</h3>
            <div className="mt-3 overflow-x-auto">
              <table className="w-full text-left text-sm">
                <thead className="text-slate-400">
                  <tr>
                    <th className="py-2 pr-4">Service</th>
                    <th className="py-2 pr-4">Policy</th>
                    <th className="py-2">Restart count</th>
                  </tr>
                </thead>
                <tbody>
                  {response.data?.recovery.services.map((service) => (
                    <tr key={service.service} className="border-t border-slate-800">
                      <td className="py-2 pr-4">{service.service}</td>
                      <td className="py-2 pr-4">
                        {service.policy === "auto" ? "Auto recovery" : "Monitor only"}
                      </td>
                      <td className="py-2">{service.restartCount}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
            <h3 className="font-semibold">Recent recovery activity</h3>
            {response.data?.recovery.recentActions.length > 0 ? (
              <div className="mt-3 space-y-2">
                {response.data?.recovery.recentActions.slice(0, 10).map((entry, index) => (
                  <div
                    key={`${entry.timestamp ?? "none"}-${entry.service}-${index}`}
                    className="rounded-lg border border-slate-800 p-3 text-sm"
                  >
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <span className="font-medium">{entry.service}</span>
                      <span className="text-slate-400">
                        {entry.time ?? "Unknown time"}
                      </span>
                    </div>
                    <div className="mt-1 text-slate-300">
                      {entry.action}: {entry.result}
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <p className="mt-3 text-sm text-slate-400">
                No recovery actions recorded.
              </p>
            )}
          </div>
        
        <section className="mt-6">
          <h3 className="text-lg font-semibold">Recovery Guardrails</h3>
          <p className="mt-1 text-sm text-slate-400">
            Live bounded-recovery eligibility. Observability only.
          </p>
          <div className="mt-3 grid gap-3 md:grid-cols-2 xl:grid-cols-3">
            {(((response.data?.recovery?.services ?? []) as unknown) as RecoveryGuardrailService[]).map(
              (service) => (
                <div
                  key={`guardrail-${service.service}`}
                  className="rounded-lg border border-slate-800 p-4"
                >
                  <div className="flex items-center justify-between gap-3">
                    <span className="font-medium">{service.service}</span>
                    <span className="text-sm font-semibold">
                      {service.guardrailState === "ready"
                        ? "READY"
                        : service.guardrailState === "cooldown"
                          ? "COOLDOWN"
                          : service.guardrailState === "budget-exhausted"
                            ? "BUDGET EXHAUSTED"
                            : "MONITOR ONLY"}
                    </span>
                  </div>
                  <div className="mt-2 text-xs text-slate-400">
                    Policy: {service.policy} · Eligible:{" "}
                    {service.eligible ? "yes" : "no"}
                  </div>
                  <div className="mt-1 text-xs text-slate-400">
                    Successful in window: {service.successfulActionsInWindow} ·
                    Remaining budget: {service.remainingBudget}
                  </div>
                  <div className="mt-1 text-xs text-slate-400">
                    Cooldown remaining: {service.cooldownRemainingSeconds}s
                  </div>
                </div>
              ),
            )}
          </div>
        </section>
</section>
      ) : null}

    
      {/* SPORTSOS_M34_5_INCIDENT_PANEL */}
      
      {/* SPORTSOS_M35_5_ESCALATION_DASHBOARD */}
      {/* SPORTSOS_M35_5_4_RESPONSE_DATA_BINDING */}
      <section className="mt-6 rounded-xl border border-slate-800 bg-slate-950/50 p-5">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 className="text-lg font-semibold">Incident Escalation Delivery</h2>
            <p className="mt-1 text-sm text-slate-400">
              Notification delivery telemetry from the production incident escalation engine.
            </p>
          </div>
          <div className="text-right text-sm text-slate-400">
            <div>
              {response.data?.incidentEscalation?.available
                ? "Telemetry active"
                : "No delivery telemetry yet"}
            </div>
            <div>
              {response.data?.incidentEscalation?.recentDeliveryFailureCount ?? 0} recent delivery failures
            </div>
          </div>
        </div>

        <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs uppercase tracking-wide text-slate-500">
              Tracked incidents
            </div>
            <div className="mt-1 text-2xl font-semibold">
              {response.data?.incidentEscalation?.trackedIncidents ?? 0}
            </div>
          </div>

          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs uppercase tracking-wide text-slate-500">
              Audit events
            </div>
            <div className="mt-1 text-2xl font-semibold">
              {response.data?.incidentEscalation?.auditEventCount ?? 0}
            </div>
          </div>

          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs uppercase tracking-wide text-slate-500">
              Recent events
            </div>
            <div className="mt-1 text-2xl font-semibold">
              {response.data?.incidentEscalation?.recentEventCount ?? 0}
            </div>
          </div>

          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs uppercase tracking-wide text-slate-500">
              Delivery failures
            </div>
            <div className="mt-1 text-2xl font-semibold">
              {response.data?.incidentEscalation?.recentDeliveryFailureCount ?? 0}
            </div>
          </div>
        </div>

        <div className="mt-4">
          <h3 className="text-sm font-medium text-slate-300">
            Recent escalation activity
          </h3>

          {(response.data?.incidentEscalation?.recentEvents.length ?? 0) === 0 ? (
            <p className="mt-2 text-sm text-slate-500">
              No escalation delivery events have been recorded yet.
            </p>
          ) : (
            <div className="mt-2 space-y-2">
              {response.data?.incidentEscalation?.recentEvents
                .slice(0, 8)
                .map((event, index) => (
                  <div
                    key={`${event.observedAt ?? "unknown"}-${event.incidentId ?? "none"}-${index}`}
                    className="rounded-lg border border-slate-800 px-3 py-2 text-sm"
                  >
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <div className="font-medium text-slate-200">
                        {event.severity ?? "unknown"} · {event.action ?? "event"} ·{" "}
                        {event.result ?? "unknown"}
                      </div>
                      <div className="text-xs text-slate-500">
                        {event.observedAt ?? "unknown time"}
                      </div>
                    </div>

                    {event.incidentId ? (
                      <div className="mt-1 font-mono text-xs text-slate-500">
                        Incident {event.incidentId}
                      </div>
                    ) : null}

                    {event.detail ? (
                      <div className="mt-1 text-xs text-slate-400">
                        {event.detail}
                      </div>
                    ) : null}
                  </div>
                ))}
            </div>
          )}
        </div>
      </section>

<section className="mt-6 rounded-xl border border-slate-800 bg-slate-950/60 p-5">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 className="text-xl font-semibold text-slate-100">
              Production Incidents
            </h2>
            <p className="mt-1 text-sm text-slate-400">
              Read-only incident visibility synthesized from production operations,
              reliability, and bounded recovery telemetry.
            </p>
          </div>
          {incidentData ? (
            <div className="text-right text-sm text-slate-300">
              <div>
                Active: {incidentData.summary.open + incidentData.summary.acknowledged}
              </div>
              <div className="text-slate-500">
                Critical {incidentData.summary.critical} · Warning {incidentData.summary.warning}
              </div>
            </div>
          ) : null}
        </div>

        {!incidentData ? (
          <div className="mt-4 rounded-lg border border-slate-800 bg-slate-900/50 p-4 text-sm text-slate-400">
            Incident telemetry is currently unavailable.
          </div>
        ) : incidentData.incidents.length === 0 ? (
          <div className="mt-4 rounded-lg border border-slate-800 bg-slate-900/50 p-4">
            <div className="font-medium text-slate-200">No incidents recorded</div>
            <div className="mt-1 text-sm text-slate-400">
              No production incident has been synthesized into the durable incident journal.
            </div>
          </div>
        ) : (
          <div className="mt-4 space-y-3">
            {incidentData.incidents.map((incident) => (
              <article
                key={incident.id}
                className="rounded-lg border border-slate-800 bg-slate-900/50 p-4"
              >
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-semibold text-slate-100">
                        {incident.title}
                      </span>
                      <span className="rounded border border-slate-700 px-2 py-0.5 text-xs uppercase text-slate-300">
                        {incident.severity}
                      </span>
                      <span className="rounded border border-slate-700 px-2 py-0.5 text-xs uppercase text-slate-300">
                        {incident.status}
                      </span>
                    </div>
                    <p className="mt-2 text-sm text-slate-300">
                      {incident.summary}
                    </p>
                  </div>
                  <div className="text-right text-xs text-slate-500">
                    <div>{incident.source}</div>
                    {incident.service ? <div>{incident.service}</div> : null}
                  </div>
                </div>

                <div className="mt-3 grid gap-2 text-xs text-slate-400 sm:grid-cols-2 lg:grid-cols-4">
                  <div>Occurrences: {incident.occurrences}</div>
                  <div>First seen: {incident.firstSeenAt}</div>
                  <div>Last seen: {incident.lastSeenAt}</div>
                  <div>Events: {incident.events.length}</div>
                </div>
                <IncidentActions incidentId={incident.id} status={incident.status} />
              </article>
            ))}
          </div>
        )}

        <p className="mt-4 text-xs text-slate-500">
          Operator actions are authenticated server-side and recorded in the durable incident journal.
        </p>
      </section>

      </div>
  );
}
