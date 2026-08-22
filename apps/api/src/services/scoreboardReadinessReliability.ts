import {
  listScoreboardReadinessMetrics,
  readinessAvailabilityPercent,
  type ScoreboardReadinessMetric,
} from "./scoreboardReadinessMetrics.js";

export type ScoreboardReliabilityRisk =
  | "HEALTHY"
  | "WATCH"
  | "AT_RISK"
  | "OFFLINE";

export type ScoreboardReliabilityClassification = {
  deviceId: string;
  risk: ScoreboardReliabilityRisk;
  availabilityPercent: number;
  degradedTransitions: number;
  readyTransitions: number;
  currentState:
    | "READY"
    | "NOT_READY";
  lastChangedAt: string;
  reasons: string[];
};

export type ScoreboardReliabilityThresholds = {
  watchAvailabilityPercent: number;
  atRiskAvailabilityPercent: number;
  watchDegradedTransitions: number;
  atRiskDegradedTransitions: number;
};

function numericEnv(
  name: string,
  fallback: number,
): number {
  const parsed =
    Number.parseFloat(
      process.env[name] ??
        "",
    );

  return Number.isFinite(
    parsed,
  )
    ? parsed
    : fallback;
}

export function getScoreboardReliabilityThresholds():
  ScoreboardReliabilityThresholds {
  const watchAvailabilityPercent =
    Math.max(
      0,
      Math.min(
        100,
        numericEnv(
          "SPORTSOS_RELIABILITY_WATCH_AVAILABILITY_PERCENT",
          99,
        ),
      ),
    );

  const atRiskAvailabilityPercent =
    Math.max(
      0,
      Math.min(
        watchAvailabilityPercent,
        numericEnv(
          "SPORTSOS_RELIABILITY_AT_RISK_AVAILABILITY_PERCENT",
          95,
        ),
      ),
    );

  const watchDegradedTransitions =
    Math.max(
      1,
      Math.floor(
        numericEnv(
          "SPORTSOS_RELIABILITY_WATCH_DEGRADED_TRANSITIONS",
          2,
        ),
      ),
    );

  const atRiskDegradedTransitions =
    Math.max(
      watchDegradedTransitions,
      Math.floor(
        numericEnv(
          "SPORTSOS_RELIABILITY_AT_RISK_DEGRADED_TRANSITIONS",
          5,
        ),
      ),
    );

  return {
    watchAvailabilityPercent,
    atRiskAvailabilityPercent,
    watchDegradedTransitions,
    atRiskDegradedTransitions,
  };
}

export function classifyScoreboardReliability(
  metric: ScoreboardReadinessMetric,
  thresholds =
    getScoreboardReliabilityThresholds(),
): ScoreboardReliabilityClassification {
  const availabilityPercent =
    readinessAvailabilityPercent(
      metric,
    );

  const reasons:
    string[] =
      [];

  if (
    metric.currentState ===
      "NOT_READY"
  ) {
    reasons.push(
      "Device is currently not ready.",
    );

    return {
      deviceId:
        metric.deviceId,
      risk:
        "OFFLINE",
      availabilityPercent,
      degradedTransitions:
        metric.degradedTransitions,
      readyTransitions:
        metric.readyTransitions,
      currentState:
        metric.currentState,
      lastChangedAt:
        metric.lastChangedAt,
      reasons,
    };
  }

  if (
    availabilityPercent <
      thresholds.atRiskAvailabilityPercent
  ) {
    reasons.push(
      `Availability ${availabilityPercent.toFixed(2)}% is below the ${thresholds.atRiskAvailabilityPercent.toFixed(2)}% at-risk threshold.`,
    );
  }

  if (
    metric.degradedTransitions >=
      thresholds.atRiskDegradedTransitions
  ) {
    reasons.push(
      `${metric.degradedTransitions} degradation transitions meet the at-risk threshold of ${thresholds.atRiskDegradedTransitions}.`,
    );
  }

  if (
    reasons.length >
    0
  ) {
    return {
      deviceId:
        metric.deviceId,
      risk:
        "AT_RISK",
      availabilityPercent,
      degradedTransitions:
        metric.degradedTransitions,
      readyTransitions:
        metric.readyTransitions,
      currentState:
        metric.currentState,
      lastChangedAt:
        metric.lastChangedAt,
      reasons,
    };
  }

  if (
    availabilityPercent <
      thresholds.watchAvailabilityPercent
  ) {
    reasons.push(
      `Availability ${availabilityPercent.toFixed(2)}% is below the ${thresholds.watchAvailabilityPercent.toFixed(2)}% watch threshold.`,
    );
  }

  if (
    metric.degradedTransitions >=
      thresholds.watchDegradedTransitions
  ) {
    reasons.push(
      `${metric.degradedTransitions} degradation transitions meet the watch threshold of ${thresholds.watchDegradedTransitions}.`,
    );
  }

  return {
    deviceId:
      metric.deviceId,
    risk:
      reasons.length >
        0
        ? "WATCH"
        : "HEALTHY",
    availabilityPercent,
    degradedTransitions:
      metric.degradedTransitions,
    readyTransitions:
      metric.readyTransitions,
    currentState:
      metric.currentState,
    lastChangedAt:
      metric.lastChangedAt,
    reasons,
  };
}

export function listScoreboardReliabilityClassifications():
  ScoreboardReliabilityClassification[] {
  const thresholds =
    getScoreboardReliabilityThresholds();

  return listScoreboardReadinessMetrics()
    .map(
      (metric) =>
        classifyScoreboardReliability(
          metric,
          thresholds,
        ),
    )
    .sort(
      (a, b) => {
        const priority:
          Record<
            ScoreboardReliabilityRisk,
            number
          > = {
            OFFLINE: 0,
            AT_RISK: 1,
            WATCH: 2,
            HEALTHY: 3,
          };

        return (
          priority[a.risk] -
            priority[b.risk] ||
          a.deviceId.localeCompare(
            b.deviceId,
          )
        );
      },
    );
}
