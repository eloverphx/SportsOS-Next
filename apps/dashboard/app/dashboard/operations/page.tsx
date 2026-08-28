import {
  getOperationsStatus,
  type OperationResult,
  type OperationsSeverityReason,
} from "./operationsStatus";

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

export default async function OperationsPage() {
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
    </div>
  );
}
