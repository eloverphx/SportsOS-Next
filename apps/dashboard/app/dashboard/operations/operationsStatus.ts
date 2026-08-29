
/* SPORTSOS_M35_5_ESCALATION_STATUS_TYPES */
export type IncidentEscalationEvent = {
  observedAt: string | null;
  incidentId: string | null;
  severity: string | null;
  action: string | null;
  result: string | null;
  detail: string | null;
};

export type IncidentEscalationStatus = {
  schemaVersion: 1;
  available: boolean;
  stateFilePresent: boolean;
  auditFilePresent: boolean;
  trackedIncidents: number;
  auditEventCount: number;
  recentEventCount: number;
  recentDeliveryFailureCount: number;
  lastEvent: IncidentEscalationEvent | null;
  recentEvents: IncidentEscalationEvent[];
};

export type OperationsSeverityReason = {
  severity: string;
  reason: string;
};

export type OperationsModeMetric = {
  mode: string;
  total: number;
  passed: number;
  failed: number;
  failureRatePercent: number;
  currentFailureStreak: number;
  latestStatus: string;
  latestFinishedAt: string | null;
};

import "server-only";

export type ReliabilityIssue = {
  type: string;
  mode: string;
  message: string;
};

export type OperationResult = {
  mode: string;
  status: string;
  exitCode: number;
  finishedAt: string | null;
};

export type OperationsStatusSnapshot = {
  recovery?: OperationsRecoveryStatus;
  schemaVersion: number;
  generatedAt: string;
  windowHours: number;
  overallStatus: string;
  severity: {
    status: string;
    reasons: OperationsSeverityReason[];
    summary: {
      totalRuns: number;
      passedRuns: number;
      failedRuns: number;
      failureRatePercent: number;
      maxFailureStreak: number;
    };
    modes: OperationsModeMetric[];
  };
  reliability: null | {
    generatedAt: string | null;
    overallStatus: string;
    issueCount: number;
    issues: ReliabilityIssue[];
  };
  latest: {
    health: OperationResult | null;
    backup: OperationResult | null;
    persistentBackup: OperationResult | null;
    recovery: OperationResult | null;
    restoreRehearsal: OperationResult | null;
    reliabilityAlert: OperationResult | null;
  };
  recent: {
    totalRuns: number;
    failedRuns: number;
    passedRuns: number;
  };

  incidentEscalation?: IncidentEscalationStatus; // SPORTSOS_M35_5_5_SNAPSHOT_ESCALATION_TYPE
};

type OperationsStatusResponse = {
  success: boolean;
  data?: OperationsStatusSnapshot;
  error?: string;
};

export async function getOperationsStatus(): Promise<
  OperationsStatusResponse
> {
  const enabled =
    process.env.SPORTSOS_OPERATIONS_DASHBOARD_ENABLED === "true";

  if (!enabled) {
    return {
      success: false,
      error: "Operations dashboard is disabled.",
    };
  }

  const token =
    process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN ?? "";

  if (token.length < 32) {
    return {
      success: false,
      error: "Operations status token is not configured.",
    };
  }

  const apiBase =
    process.env.SPORTSOS_API_INTERNAL_URL ??
    process.env.SPORTSOS_API_URL ??
    "http://api:4001";

  const response = await fetch(
    `${apiBase.replace(/\/$/, "")}/deployment/operations/status`,
    {
      method: "GET",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
      },
      cache: "no-store",
    },
  );

  let body: OperationsStatusResponse | null = null;

  try {
    body =
      (await response.json()) as OperationsStatusResponse;
  } catch {
    body = null;
  }

  if (!response.ok || !body?.success || !body.data) {
    return {
      success: false,
      error:
        body?.error ??
        `Operations status request failed (${response.status}).`,
    };
  }

  return body;
}


// SPORTSOS_M33_3_RECOVERY_TYPES
export type OperationsRecoveryAction = {
  timestamp: number | null;
  time: string | null;
  service: string;
  container: string;
  action: string;
  result: string;
};

export type OperationsRecoveryService = {
  service: string;
  policy: "auto" | "monitor";
  restartCount: number;
};

export type OperationsRecoveryStatus = {
  schemaVersion: number;
  generatedAt: string;
  mode: "bounded";
  defaults: {
    restartDeltaThreshold: number;
    cooldownSeconds: number;
    budgetWindowSeconds: number;
    maxActionsPerWindow: number;
    postRecoveryTimeoutSeconds: number;
  };
  summary: {
    servicesMonitored: number;
    autoRecoveryServices: number;
    monitorOnlyServices: number;
    totalSuccessfulRecoveries: number;
    totalBlockedRecoveries: number;
    totalFailedRecoveries: number;
    recentSuccessfulRecoveries: number;
    recentBlockedRecoveries: number;
  };
  lastSuccessfulRecovery: OperationsRecoveryAction | null;
  lastBlockedRecovery: OperationsRecoveryAction | null;
  lastFailedRecovery: OperationsRecoveryAction | null;
  services: OperationsRecoveryService[];
  recentActions: OperationsRecoveryAction[];
};


// SPORTSOS_M34_5_INCIDENT_FETCH
export interface OperationsIncidentEventView {
  eventId: string;
  incidentId: string;
  timestamp: string;
  type: "opened" | "acknowledged" | "resolved" | "reopened" | "updated";
  actor: string;
  note: string | null;
  payload: Record<string, unknown>;
}

export interface OperationsIncidentView {
  id: string;
  fingerprint: string;
  source: "operations" | "recovery" | "reliability" | "health";
  severity: "warning" | "critical";
  status: "open" | "acknowledged" | "resolved";
  title: string;
  summary: string;
  service: string | null;
  firstSeenAt: string;
  lastSeenAt: string;
  acknowledgedAt: string | null;
  acknowledgedBy: string | null;
  resolvedAt: string | null;
  resolvedBy: string | null;
  occurrences: number;
  metadata: Record<string, unknown>;
  events: OperationsIncidentEventView[];
}

export interface OperationsIncidentsResponse {
  success: boolean;
  data?: {
    schemaVersion: 1;
    incidents: OperationsIncidentView[];
    summary: {
      total: number;
      open: number;
      acknowledged: number;
      resolved: number;
      critical: number;
      warning: number;
    };
  };
  error?: {
    code?: string;
    message?: string;
  };
}

export async function getOperationsIncidents(): Promise<OperationsIncidentsResponse> {
  const enabled =
    process.env.SPORTSOS_OPERATIONS_DASHBOARD_ENABLED?.trim().toLowerCase() ===
    "true";

  if (!enabled) {
    return {
      success: false,
      error: {
        code: "OPERATIONS_DASHBOARD_DISABLED",
        message: "Operations Dashboard is disabled.",
      },
    };
  }

  const token = process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN?.trim() ?? "";
  if (token.length < 32) {
    return {
      success: false,
      error: {
        code: "OPERATIONS_STATUS_MISCONFIGURED",
        message: "Operations incident access is not configured.",
      },
    };
  }

  const baseUrl =
    process.env.SPORTSOS_API_INTERNAL_URL?.trim().replace(/\/$/, "") ||
    "http://api:4001";

  try {
    const response = await fetch(
      `${baseUrl}/deployment/operations/incidents`,
      {
        method: "GET",
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: "application/json",
        },
        cache: "no-store",
      },
    );

    const body = (await response.json()) as OperationsIncidentsResponse;

    if (!response.ok) {
      return {
        success: false,
        error: body.error ?? {
          code: "OPERATIONS_INCIDENTS_UNAVAILABLE",
          message: `Operations incident API returned HTTP ${response.status}.`,
        },
      };
    }

    return body;
  } catch (error) {
    return {
      success: false,
      error: {
        code: "OPERATIONS_INCIDENTS_UNAVAILABLE",
        message:
          error instanceof Error
            ? error.message
            : "Operations incident API request failed.",
      },
    };
  }
}
