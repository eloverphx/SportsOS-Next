export type BroadcastRuntimeHeartbeatState =
  | "HEALTHY"
  | "STALE"
  | "MISSING"
  | "STOPPED"
  | "FAILED"
  | "UNKNOWN";

export type BroadcastRuntimeHeartbeatInput = {
  runtimeStatus: string;
  lastActivityAt: string | null;
  nowMs?: number;
  staleAfterMs?: number;
};

export type BroadcastRuntimeHeartbeat = {
  state:
    BroadcastRuntimeHeartbeatState;
  stale:
    boolean;
  ageMs:
    number | null;
  staleAfterMs:
    number;
  reason:
    string;
};

const DEFAULT_STALE_AFTER_MS =
  20_000;

export function evaluateBroadcastRuntimeHeartbeat(
  input: BroadcastRuntimeHeartbeatInput,
): BroadcastRuntimeHeartbeat {
  const staleAfterMs =
    Math.max(
      1_000,
      Math.min(
        input.staleAfterMs ??
        DEFAULT_STALE_AFTER_MS,
        300_000,
      ),
    );

  const nowMs =
    input.nowMs ??
    Date.now();

  const status =
    input.runtimeStatus
      .trim()
      .toUpperCase();

  if (
    status ===
      "STOPPED" ||
    status ===
      "IDLE"
  ) {
    return {
      state:
        "STOPPED",
      stale:
        false,
      ageMs:
        null,
      staleAfterMs,
      reason:
        "Encoder runtime is stopped.",
    };
  }

  if (
    status ===
      "ERROR" ||
    status ===
      "FAILED"
  ) {
    return {
      state:
        "FAILED",
      stale:
        false,
      ageMs:
        null,
      staleAfterMs,
      reason:
        "Encoder runtime reports a failure state.",
    };
  }

  if (
    !input.lastActivityAt
  ) {
    return {
      state:
        "MISSING",
      stale:
        true,
      ageMs:
        null,
      staleAfterMs,
      reason:
        "No encoder runtime heartbeat/activity timestamp is available.",
    };
  }

  const activityMs =
    Date.parse(
      input.lastActivityAt,
    );

  if (
    !Number.isFinite(
      activityMs,
    )
  ) {
    return {
      state:
        "UNKNOWN",
      stale:
        true,
      ageMs:
        null,
      staleAfterMs,
      reason:
        "Encoder runtime heartbeat timestamp is invalid.",
    };
  }

  const ageMs =
    Math.max(
      0,
      nowMs -
        activityMs,
    );

  if (
    ageMs >
    staleAfterMs
  ) {
    return {
      state:
        "STALE",
      stale:
        true,
      ageMs,
      staleAfterMs,
      reason:
        `Encoder runtime activity is stale by ${ageMs} ms.`,
    };
  }

  return {
    state:
      "HEALTHY",
    stale:
      false,
    ageMs,
    staleAfterMs,
    reason:
      "Encoder runtime activity is fresh.",
  };
}
