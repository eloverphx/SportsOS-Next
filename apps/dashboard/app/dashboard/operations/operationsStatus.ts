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
