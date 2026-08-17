export type BroadcastOperationsStage =
  | "NOT_READY"
  | "READY"
  | "LIVE"
  | "DEGRADED";

export type BroadcastOperationsInput = {
  sessionReady: boolean;
  canGoLive: boolean;
  gameLive: boolean;
  transportLive: boolean;
  overlayEligible: boolean;
  realtimeConnected: boolean;
};

export type BroadcastOperationsSummary = {
  stage: BroadcastOperationsStage;
  progressPercent: number;
  alerts: string[];
};

export function buildBroadcastOperationsSummary(
  input: BroadcastOperationsInput,
): BroadcastOperationsSummary {
  const alerts: string[] = [];

  if (!input.sessionReady) {
    alerts.push("Broadcast session is not ready.");
  }

  if (!input.overlayEligible) {
    alerts.push("Broadcast overlay is not eligible.");
  }

  if (!input.realtimeConnected) {
    alerts.push("Overlay realtime connection is unavailable.");
  }

  if (input.gameLive && !input.transportLive) {
    alerts.push("Game is live but transport is not live.");
  }

  let stage: BroadcastOperationsStage = "NOT_READY";

  if (
    input.gameLive &&
    input.transportLive &&
    input.sessionReady
  ) {
    stage = input.realtimeConnected
      ? "LIVE"
      : "DEGRADED";
  } else if (
    input.sessionReady &&
    input.canGoLive
  ) {
    stage = "READY";
  } else if (
    input.sessionReady ||
    input.gameLive ||
    input.transportLive
  ) {
    stage = "DEGRADED";
  }

  const checks = [
    input.sessionReady,
    input.overlayEligible,
    input.realtimeConnected,
    input.gameLive === input.transportLive,
  ];

  const progressPercent = Math.round(
    (checks.filter(Boolean).length / checks.length) * 100,
  );

  return {
    stage,
    progressPercent,
    alerts,
  };
}
