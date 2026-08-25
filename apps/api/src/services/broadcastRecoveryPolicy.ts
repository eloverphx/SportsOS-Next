export type BroadcastRecoveryRuntimeState =
  | "idle"
  | "starting"
  | "live"
  | "stopping"
  | "failed"
  | "unknown";

export type BroadcastRecoveryCoordinatorIntent =
  | "idle"
  | "live"
  | "stopped";

export type BroadcastRecoveryAction =
  | "none"
  | "observe"
  | "reconcile-to-idle"
  | "request-controlled-start"
  | "request-controlled-stop"
  | "require-operator-review";

export type BroadcastRecoveryReason =
  | "state-consistent"
  | "startup-grace-period"
  | "runtime-missing"
  | "unexpected-runtime"
  | "runtime-transition-stale"
  | "runtime-failed"
  | "runtime-state-unknown";

export interface BroadcastRecoveryInput {
  coordinatorIntent: BroadcastRecoveryCoordinatorIntent;
  runtimeState: BroadcastRecoveryRuntimeState;
  stateAgeMs: number;
  startupGraceMs?: number;
  transitionTimeoutMs?: number;
}

export interface BroadcastRecoveryDecision {
  action: BroadcastRecoveryAction;
  reason: BroadcastRecoveryReason;
  automatic: boolean;
  destructive: boolean;
}

const DEFAULT_STARTUP_GRACE_MS = 30_000;
const DEFAULT_TRANSITION_TIMEOUT_MS = 45_000;

export function evaluateBroadcastRecovery(
  input: BroadcastRecoveryInput,
): BroadcastRecoveryDecision {
  const startupGraceMs =
    input.startupGraceMs ?? DEFAULT_STARTUP_GRACE_MS;
  const transitionTimeoutMs =
    input.transitionTimeoutMs ?? DEFAULT_TRANSITION_TIMEOUT_MS;

  if (!Number.isFinite(input.stateAgeMs) || input.stateAgeMs < 0) {
    return {
      action: "require-operator-review",
      reason: "runtime-state-unknown",
      automatic: false,
      destructive: false,
    };
  }

  if (input.runtimeState === "unknown") {
    return {
      action: "require-operator-review",
      reason: "runtime-state-unknown",
      automatic: false,
      destructive: false,
    };
  }

  if (input.runtimeState === "failed") {
    return {
      action: "require-operator-review",
      reason: "runtime-failed",
      automatic: false,
      destructive: false,
    };
  }

  if (
    (input.runtimeState === "starting" ||
      input.runtimeState === "stopping") &&
    input.stateAgeMs > transitionTimeoutMs
  ) {
    return {
      action: "require-operator-review",
      reason: "runtime-transition-stale",
      automatic: false,
      destructive: false,
    };
  }

  if (input.stateAgeMs < startupGraceMs) {
    return {
      action: "observe",
      reason: "startup-grace-period",
      automatic: true,
      destructive: false,
    };
  }

  if (
    input.coordinatorIntent === "live" &&
    input.runtimeState === "idle"
  ) {
    return {
      action: "request-controlled-start",
      reason: "runtime-missing",
      automatic: false,
      destructive: false,
    };
  }

  if (
    input.coordinatorIntent !== "live" &&
    input.runtimeState === "live"
  ) {
    return {
      action: "request-controlled-stop",
      reason: "unexpected-runtime",
      automatic: false,
      destructive: true,
    };
  }

  if (
    input.coordinatorIntent === "stopped" &&
    input.runtimeState === "idle"
  ) {
    return {
      action: "reconcile-to-idle",
      reason: "state-consistent",
      automatic: true,
      destructive: false,
    };
  }

  return {
    action: "none",
    reason: "state-consistent",
    automatic: true,
    destructive: false,
  };
}
