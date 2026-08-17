export type BroadcastTransportState =
  | "OFFLINE"
  | "CONNECTING"
  | "READY"
  | "LIVE"
  | "ERROR";

export type BroadcastOverlayState =
  | "DISABLED"
  | "READY"
  | "ACTIVE";

export type BroadcastSessionInput = {
  gameId: string;
  operatorAssigned: boolean;
  gameAuthorized: boolean;
  gameLive: boolean;
  transportState: BroadcastTransportState;
  overlayState: BroadcastOverlayState;
  streamKeyConfigured: boolean;
};

export type BroadcastSessionStatus =
  | "NOT_READY"
  | "READY"
  | "LIVE"
  | "DEGRADED";

export type BroadcastSessionSummary = {
  gameId: string;
  status: BroadcastSessionStatus;
  ready: boolean;
  canGoLive: boolean;
  overlayEligible: boolean;
  blockers: string[];
  warnings: string[];
};

export function buildBroadcastSessionSummary(
  input: BroadcastSessionInput,
): BroadcastSessionSummary {
  const blockers: string[] = [];
  const warnings: string[] = [];

  if (!input.operatorAssigned) {
    blockers.push("Broadcast operator is not assigned.");
  }

  if (!input.gameAuthorized) {
    blockers.push("Game start is not authorized.");
  }

  if (!input.streamKeyConfigured) {
    blockers.push("Stream destination is not configured.");
  }

  if (
    input.transportState === "OFFLINE" ||
    input.transportState === "ERROR"
  ) {
    blockers.push("Broadcast transport is not ready.");
  }

  if (input.overlayState === "DISABLED") {
    warnings.push("Broadcast overlay is disabled.");
  }

  if (
    input.gameLive &&
    input.transportState !== "LIVE"
  ) {
    warnings.push(
      "Game is live but broadcast transport is not live.",
    );
  }

  if (
    input.transportState === "LIVE" &&
    !input.gameLive
  ) {
    warnings.push(
      "Broadcast transport is live before the game is live.",
    );
  }

  const ready =
    blockers.length === 0 &&
    (
      input.transportState === "READY" ||
      input.transportState === "LIVE"
    );

  const canGoLive =
    ready &&
    input.transportState === "READY" &&
    !input.gameLive;

  const overlayEligible =
    input.overlayState !== "DISABLED" &&
    input.gameAuthorized;

  let status: BroadcastSessionStatus = "NOT_READY";

  if (
    input.transportState === "LIVE" &&
    input.gameLive &&
    blockers.length === 0
  ) {
    status =
      warnings.length > 0 ? "DEGRADED" : "LIVE";
  } else if (
    ready &&
    warnings.length === 0
  ) {
    status = "READY";
  } else if (
    ready ||
    (
      input.gameLive &&
      warnings.length > 0
    )
  ) {
    status = "DEGRADED";
  }

  return {
    gameId: input.gameId,
    status,
    ready,
    canGoLive,
    overlayEligible,
    blockers,
    warnings,
  };
}
