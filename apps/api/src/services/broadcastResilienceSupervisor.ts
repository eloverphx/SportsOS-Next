import {
  evaluateBroadcastRecovery,
  type BroadcastRecoveryCoordinatorIntent,
  type BroadcastRecoveryDecision,
  type BroadcastRecoveryRuntimeState,
} from "./broadcastRecoveryPolicy.js";

import {
  evaluateBroadcastRuntimeHeartbeat,
  type BroadcastRuntimeHeartbeat,
} from "./broadcastRuntimeHeartbeat.js";

export type BroadcastResilienceSupervisorInput = {
  coordinatorIntent: string;
  runtimeStatus: string;
  lastActivityAt: string | null;
  stateAgeMs: number;
  nowMs?: number;
};

export type BroadcastResilienceSupervisorDecision = {
  heartbeat:
    BroadcastRuntimeHeartbeat;
  recovery:
    BroadcastRecoveryDecision;
};

function normalizeCoordinatorIntent(
  value: string,
): BroadcastRecoveryCoordinatorIntent {
  const normalized =
    value
      .trim()
      .toUpperCase();

  if (
    normalized ===
      "GO_LIVE" ||
    normalized ===
      "LIVE"
  ) {
    return "live";
  }

  if (
    normalized ===
      "STOP" ||
    normalized ===
      "STOPPED" ||
    normalized ===
      "COMPLETE"
  ) {
    return "stopped";
  }

  return "idle";
}

function normalizeRuntimeState(
  value: string,
): BroadcastRecoveryRuntimeState {
  const normalized =
    value
      .trim()
      .toUpperCase();

  if (
    normalized ===
      "STARTING"
  ) {
    return "starting";
  }

  if (
    normalized ===
      "LIVE" ||
    normalized ===
      "RUNNING"
  ) {
    return "live";
  }

  if (
    normalized ===
      "STOPPING"
  ) {
    return "stopping";
  }

  if (
    normalized ===
      "ERROR" ||
    normalized ===
      "FAILED"
  ) {
    return "failed";
  }

  if (
    normalized ===
      "STOPPED" ||
    normalized ===
      "IDLE"
  ) {
    return "idle";
  }

  return "unknown";
}

export function evaluateBroadcastResilienceSupervisor(
  input: BroadcastResilienceSupervisorInput,
): BroadcastResilienceSupervisorDecision {
  const heartbeat =
    evaluateBroadcastRuntimeHeartbeat({
      runtimeStatus:
        input.runtimeStatus,
      lastActivityAt:
        input.lastActivityAt,
      nowMs:
        input.nowMs,
    });

  let runtimeState =
    normalizeRuntimeState(
      input.runtimeStatus,
    );

  if (
    heartbeat.state ===
      "STALE" ||
    heartbeat.state ===
      "MISSING" ||
    heartbeat.state ===
      "UNKNOWN"
  ) {
    runtimeState =
      "unknown";
  }

  if (
    heartbeat.state ===
      "FAILED"
  ) {
    runtimeState =
      "failed";
  }

  const recovery =
    evaluateBroadcastRecovery({
      coordinatorIntent:
        normalizeCoordinatorIntent(
          input.coordinatorIntent,
        ),
      runtimeState,
      stateAgeMs:
        input.stateAgeMs,
    });

  return {
    heartbeat,
    recovery,
  };
}
