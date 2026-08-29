import {
  openOrUpdateOperationsIncident,
  type OperationsIncidentSeverity,
  type OperationsIncidentSource,
} from "./operationsIncidentJournal.js";

export interface RecoveryTelemetryService {
  readonly service?: string;
  readonly policy?: string;
  readonly guardrailState?: string;
  readonly eligible?: boolean;
  readonly blockedReason?: string | null;
  readonly successfulActionsInWindow?: number;
  readonly remainingBudget?: number;
  readonly cooldownRemainingSeconds?: number;
}

export interface RecoveryTelemetry {
  readonly summary?: {
    readonly totalFailedRecoveries?: number;
    readonly totalBlockedRecoveries?: number;
    readonly recentFailedRecoveries?: number;
    readonly recentBlockedRecoveries?: number;
  };
  readonly lastFailedRecovery?: Record<string, unknown> | null;
  readonly services?: readonly RecoveryTelemetryService[];
}

export interface SeverityTelemetry {
  readonly status?: string;
  readonly reasons?: readonly {
    readonly severity?: string;
    readonly reason?: string;
  }[];
}

export interface OperationsStatusForIncidentSynthesis {
  readonly schemaVersion?: number;
  readonly overallStatus?: string;
  readonly severity?: SeverityTelemetry;
  readonly recent?: {
    readonly totalRuns?: number;
    readonly failedRuns?: number;
    readonly passedRuns?: number;
  };
  readonly recovery?: RecoveryTelemetry;
}

export interface OperationsIncidentCandidate {
  readonly fingerprint: string;
  readonly source: OperationsIncidentSource;
  readonly severity: OperationsIncidentSeverity;
  readonly title: string;
  readonly summary: string;
  readonly service: string | null;
  readonly metadata: Record<string, unknown>;
}

function normalizeSeverity(
  value: string | undefined,
): OperationsIncidentSeverity | null {
  const normalized = value?.trim().toLowerCase();
  if (normalized === "critical") {
    return "critical";
  }
  if (normalized === "warning") {
    return "warning";
  }
  return null;
}

function slug(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 120);
}

function stableReasonFingerprint(
  severity: OperationsIncidentSeverity,
  reason: string,
): string {
  return `reliability:${severity}:${slug(reason) || "unspecified"}`;
}

export function synthesizeOperationsIncidentCandidates(
  status: OperationsStatusForIncidentSynthesis,
): readonly OperationsIncidentCandidate[] {
  const candidates: OperationsIncidentCandidate[] = [];
  const seen = new Set<string>();

  const add = (candidate: OperationsIncidentCandidate): void => {
    if (seen.has(candidate.fingerprint)) {
      return;
    }
    seen.add(candidate.fingerprint);
    candidates.push(candidate);
  };

  for (const reason of status.severity?.reasons ?? []) {
    const severity = normalizeSeverity(reason.severity);
    const summary = reason.reason?.trim();

    if (!severity || !summary) {
      continue;
    }

    add({
      fingerprint: stableReasonFingerprint(severity, summary),
      source: "reliability",
      severity,
      title:
        severity === "critical"
          ? "Production reliability is critical"
          : "Production reliability is degraded",
      summary,
      service: null,
      metadata: {
        overallStatus:
          status.overallStatus ??
          status.severity?.status ??
          "unknown",
      },
    });
  }

  const recovery = status.recovery;
  const recentFailed = Number(
    recovery?.summary?.recentFailedRecoveries ??
      recovery?.summary?.totalFailedRecoveries ??
      0,
  );

  if (Number.isFinite(recentFailed) && recentFailed > 0) {
    add({
      fingerprint: "recovery:recent-failure",
      source: "recovery",
      severity: "critical",
      title: "Bounded recovery failed",
      summary:
        "At least one recent bounded recovery action failed or did not restore service health.",
      service: null,
      metadata: {
        recentFailedRecoveries: recentFailed,
        lastFailedRecovery: recovery?.lastFailedRecovery ?? null,
      },
    });
  }

  for (const service of recovery?.services ?? []) {
    const serviceName = service.service?.trim();
    const state = service.guardrailState?.trim().toLowerCase();

    if (!serviceName || !state) {
      continue;
    }

    if (state === "budget-exhausted") {
      add({
        fingerprint: `recovery:${slug(serviceName)}:budget-exhausted`,
        source: "recovery",
        severity: "critical",
        title: `Recovery budget exhausted for ${serviceName}`,
        summary:
          "Automatic recovery is blocked because the bounded recovery budget has been exhausted.",
        service: serviceName,
        metadata: {
          policy: service.policy ?? null,
          blockedReason: service.blockedReason ?? null,
          successfulActionsInWindow:
            service.successfulActionsInWindow ?? 0,
          remainingBudget: service.remainingBudget ?? 0,
        },
      });
      continue;
    }

    if (
      state === "cooldown" &&
      Number(service.cooldownRemainingSeconds ?? 0) > 0
    ) {
      add({
        fingerprint: `recovery:${slug(serviceName)}:cooldown`,
        source: "recovery",
        severity: "warning",
        title: `Recovery cooldown active for ${serviceName}`,
        summary:
          "Automatic recovery is temporarily blocked by the bounded recovery cooldown.",
        service: serviceName,
        metadata: {
          policy: service.policy ?? null,
          blockedReason: service.blockedReason ?? null,
          cooldownRemainingSeconds:
            service.cooldownRemainingSeconds ?? 0,
          remainingBudget: service.remainingBudget ?? null,
        },
      });
    }
  }

  const failedRuns = Number(status.recent?.failedRuns ?? 0);
  if (
    Number.isFinite(failedRuns) &&
    failedRuns > 0 &&
    candidates.length === 0
  ) {
    add({
      fingerprint: "operations:recent-run-failure",
      source: "operations",
      severity: "warning",
      title: "Recent production operation failed",
      summary:
        "One or more recent scheduled production operations reported failure.",
      service: null,
      metadata: {
        totalRuns: status.recent?.totalRuns ?? 0,
        failedRuns,
        passedRuns: status.recent?.passedRuns ?? 0,
      },
    });
  }

  return candidates.sort((left, right) =>
    left.fingerprint.localeCompare(right.fingerprint),
  );
}

export async function persistSynthesizedOperationsIncidents(
  status: OperationsStatusForIncidentSynthesis,
  observedAt?: string,
): Promise<readonly string[]> {
  const candidates =
    synthesizeOperationsIncidentCandidates(status);
  const incidentIds: string[] = [];

  for (const candidate of candidates) {
    const incident = await openOrUpdateOperationsIncident({
      ...candidate,
      observedAt,
    });
    incidentIds.push(incident.id);
  }

  return incidentIds;
}
