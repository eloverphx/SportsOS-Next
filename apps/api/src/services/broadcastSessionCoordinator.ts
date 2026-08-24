import fs from "node:fs";
import path from "node:path";

import {
  recordBroadcastCoordinatorAudit,
} from "./broadcastCoordinatorAudit.js";

import {
  evaluateGameDayGoLivePreflight,
} from "./gameDayGoLivePreflight.js";

import {
  getStreamDestinationProfile,
} from "./streamDestinationProfile.js";

import {
  armGoLiveSession,
  completeGoLiveSession,
  getGoLiveSession,
  markGoLiveStarting,
  markGoLiveStopping,
} from "./goLiveSession.js";

import {
  encoderRuntimeSnapshot,
  startEncoderRuntime,
  stopEncoderRuntime,
} from "./encoderRuntime.js";

export type BroadcastCoordinatorIntent =
  | "IDLE"
  | "PREPARE"
  | "GO_LIVE"
  | "STOP";

export type BroadcastCoordinatorRecord = {
  gameId: string;
  intent: BroadcastCoordinatorIntent;
  correlationId: string;
  updatedAt: string;
  lastError: string | null;
};

export type BroadcastCoordinatorSnapshot = {
  coordinator: BroadcastCoordinatorRecord;
  preflight:
    ReturnType<
      typeof evaluateGameDayGoLivePreflight
    >;
  goLive:
    ReturnType<
      typeof getGoLiveSession
    >;
  runtime:
    ReturnType<
      typeof encoderRuntimeSnapshot
    >;
};

type Store = {
  version: 1;
  records:
    BroadcastCoordinatorRecord[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(
    process.cwd(),
    "data",
  );

const STORE_FILE =
  path.join(
    DATA_DIR,
    "broadcast-session-coordinator.json",
  );

let store =
  loadStore();

function loadStore(): Store {
  try {
    const parsed =
      JSON.parse(
        fs.readFileSync(
          STORE_FILE,
          "utf8",
        ),
      ) as Store;

    if (
      parsed.version !== 1 ||
      !Array.isArray(
        parsed.records,
      )
    ) {
      throw new Error(
        "Invalid broadcast coordinator store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      records: [],
    };
  }
}

function persistStore(): void {
  fs.mkdirSync(
    DATA_DIR,
    {
      recursive: true,
    },
  );

  const temp =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    temp,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );

  fs.renameSync(
    temp,
    STORE_FILE,
  );
}

function createCorrelationId(
  gameId: string,
): string {
  return `broadcast-${gameId}-${Date.now()}-${Math.random()
    .toString(36)
    .slice(2, 8)}`;
}

export function listKnownBroadcastCoordinatorGameIds(): string[] {
  return Array.from(
    new Set(
      store.records
        .map((record) => record.gameId)
        .filter(Boolean),
    ),
  );
}

export function listActiveBroadcastGameIds(): string[] {
  return listKnownBroadcastCoordinatorGameIds()
    .filter((gameId) => {
      const coordinator =
        getBroadcastCoordinatorRecord(
          gameId,
        );

      const goLive =
        getGoLiveSession(
          gameId,
        );

      const runtime =
        encoderRuntimeSnapshot(
          gameId,
        );

      const coordinatorActive =
        coordinator.intent !==
        "IDLE";

      const goLiveActive =
        [
          "ARMED",
          "STARTING",
          "LIVE",
          "DEGRADED",
          "STOPPING",
        ].includes(
          goLive.status,
        );

      const runtimeActive =
        ![
          "STOPPED",
          "ERROR",
        ].includes(
          runtime.session.status,
        );

      return (
        coordinatorActive ||
        goLiveActive ||
        runtimeActive
      );
    });
}

export function getBroadcastCoordinatorRecord(
  gameId: string,
): BroadcastCoordinatorRecord {
  const existing =
    store.records.find(
      (record) =>
        record.gameId ===
        gameId,
    );

  if (existing) {
    return {
      ...existing,
    };
  }

  return {
    gameId,
    intent:
      "IDLE",
    correlationId:
      createCorrelationId(
        gameId,
      ),
    updatedAt:
      new Date().toISOString(),
    lastError:
      null,
  };
}

export function setBroadcastCoordinatorIntent(input: {
  gameId: string;
  intent: BroadcastCoordinatorIntent;
  lastError?: string | null;
}): BroadcastCoordinatorRecord {
  const record: BroadcastCoordinatorRecord = {
    gameId:
      input.gameId,
    intent:
      input.intent,
    correlationId:
      createCorrelationId(
        input.gameId,
      ),
    updatedAt:
      new Date().toISOString(),
    lastError:
      input.lastError ??
      null,
  };

  store.records =
    store.records.filter(
      (item) =>
        item.gameId !==
        input.gameId,
    );

  store.records.push(
    record,
  );

  persistStore();

  recordBroadcastCoordinatorAudit({
    gameId:
      input.gameId,
    type:
      "INTENT_CHANGED",
    correlationId:
      record.correlationId,
    detail:
      `Intent changed to ${record.intent}.`,
  });

  return {
    ...record,
  };
}

export function getBroadcastCoordinatorSnapshot(
  gameId: string,
): BroadcastCoordinatorSnapshot {
  return {
    coordinator:
      getBroadcastCoordinatorRecord(
        gameId,
      ),
    preflight:
      evaluateGameDayGoLivePreflight(
        gameId,
      ),
    goLive:
      getGoLiveSession(
        gameId,
      ),
    runtime:
      encoderRuntimeSnapshot(
        gameId,
      ),
  };
}

export function prepareBroadcastSession(
  gameId: string,
): BroadcastCoordinatorSnapshot {
  const coordinator =
    getBroadcastCoordinatorRecord(
      gameId,
    );

  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "PREPARE_REQUESTED",
    correlationId:
      coordinator.correlationId,
  });

  const preflight =
    evaluateGameDayGoLivePreflight(
      gameId,
    );

  setBroadcastCoordinatorIntent({
    gameId,
    intent:
      "PREPARE",
    lastError:
      preflight.ready
        ? null
        : "Game-day go-live preflight is blocked.",
  });

  if (!preflight.ready) {
    recordBroadcastCoordinatorAudit({
      gameId,
      type:
        "PREPARE_BLOCKED",
      correlationId:
        getBroadcastCoordinatorRecord(
          gameId,
        ).correlationId,
      detail:
        "Game-day go-live preflight is blocked.",
    });
  }

  return getBroadcastCoordinatorSnapshot(
    gameId,
  );
}


export async function startCoordinatedBroadcast(
  gameId: string,
): Promise<BroadcastCoordinatorSnapshot> {
  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "START_REQUESTED",
    correlationId:
      getBroadcastCoordinatorRecord(
        gameId,
      ).correlationId,
  });

  const preflight =
    evaluateGameDayGoLivePreflight(
      gameId,
    );

  if (!preflight.ready) {
    setBroadcastCoordinatorIntent({
      gameId,
      intent:
        "GO_LIVE",
      lastError:
        "Final game-day go-live preflight is blocked.",
    });

    recordBroadcastCoordinatorAudit({
      gameId,
      type:
        "START_BLOCKED",
      correlationId:
        getBroadcastCoordinatorRecord(
          gameId,
        ).correlationId,
      detail:
        "Final game-day go-live preflight is blocked.",
    });

    throw new Error(
      "Final game-day go-live preflight is blocked.",
    );
  }

  const current =
    getGoLiveSession(
      gameId,
    );

  if (
    current.status !==
      "ARMED"
  ) {
    armGoLiveSession(
      gameId,
    );
  }

  const armed =
    getGoLiveSession(
      gameId,
    );

  if (
    armed.status !==
      "ARMED"
  ) {
    throw new Error(
      "Go-live session could not be armed.",
    );
  }

  const destination =
    getStreamDestinationProfile(
      gameId,
    );

  if (!destination) {
    throw new Error(
      "Stream destination is missing.",
    );
  }

  setBroadcastCoordinatorIntent({
    gameId,
    intent:
      "GO_LIVE",
    lastError:
      null,
  });

  markGoLiveStarting(
    gameId,
  );

  await startEncoderRuntime({
    gameId,
    destination,
  });

  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "START_COMPLETED",
    correlationId:
      getBroadcastCoordinatorRecord(
        gameId,
      ).correlationId,
  });

  return getBroadcastCoordinatorSnapshot(
    gameId,
  );
}

export async function stopCoordinatedBroadcast(
  gameId: string,
): Promise<BroadcastCoordinatorSnapshot> {
  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "STOP_REQUESTED",
    correlationId:
      getBroadcastCoordinatorRecord(
        gameId,
      ).correlationId,
  });

  setBroadcastCoordinatorIntent({
    gameId,
    intent:
      "STOP",
    lastError:
      null,
  });

  markGoLiveStopping(
    gameId,
  );

  await stopEncoderRuntime(
    gameId,
  );

  completeGoLiveSession(
    gameId,
  );

  setBroadcastCoordinatorIntent({
    gameId,
    intent:
      "IDLE",
    lastError:
      null,
  });

  return getBroadcastCoordinatorSnapshot(
    gameId,
  );
}


export type BroadcastCoordinatorHealth = {
  gameId: string;
  healthy: boolean;
  checkedAt: string;
  issues: Array<{
    id:
      | "INTENT_GO_LIVE_RUNTIME_STOPPED"
      | "INTENT_GO_LIVE_SESSION_NOT_ACTIVE"
      | "INTENT_STOP_RUNTIME_ACTIVE"
      | "GO_LIVE_LIVE_RUNTIME_NOT_LIVE"
      | "EMERGENCY_STOP_RUNTIME_ACTIVE";
    message: string;
  }>;
};

export function evaluateBroadcastCoordinatorHealth(
  gameId: string,
): BroadcastCoordinatorHealth {
  const snapshot =
    getBroadcastCoordinatorSnapshot(
      gameId,
    );

  const issues:
    BroadcastCoordinatorHealth["issues"] = [];

  if (
    snapshot.coordinator.intent ===
      "GO_LIVE" &&
    (
      snapshot.runtime.session.status ===
        "STOPPED" ||
      snapshot.runtime.session.status ===
        "ERROR"
    )
  ) {
    issues.push({
      id:
        "INTENT_GO_LIVE_RUNTIME_STOPPED",
      message:
        `Coordinator intent is GO_LIVE but encoder runtime is ${snapshot.runtime.session.status}.`,
    });
  }

  if (
    snapshot.coordinator.intent ===
      "GO_LIVE" &&
    ![
      "ARMED",
      "STARTING",
      "LIVE",
      "DEGRADED",
    ].includes(
      snapshot.goLive.status,
    )
  ) {
    issues.push({
      id:
        "INTENT_GO_LIVE_SESSION_NOT_ACTIVE",
      message:
        `Coordinator intent is GO_LIVE but go-live session is ${snapshot.goLive.status}.`,
    });
  }

  if (
    snapshot.coordinator.intent ===
      "STOP" &&
    ![
      "STOPPED",
      "ERROR",
    ].includes(
      snapshot.runtime.session.status,
    )
  ) {
    issues.push({
      id:
        "INTENT_STOP_RUNTIME_ACTIVE",
      message:
        `Coordinator intent is STOP but encoder runtime is ${snapshot.runtime.session.status}.`,
    });
  }

  if (
    snapshot.goLive.status ===
      "LIVE" &&
    snapshot.runtime.session.status !==
      "LIVE"
  ) {
    issues.push({
      id:
        "GO_LIVE_LIVE_RUNTIME_NOT_LIVE",
      message:
        `Go-live session is LIVE but encoder runtime is ${snapshot.runtime.session.status}.`,
    });
  }

  if (
    snapshot.goLive.status ===
      "EMERGENCY_STOPPED" &&
    ![
      "STOPPED",
      "ERROR",
    ].includes(
      snapshot.runtime.session.status,
    )
  ) {
    issues.push({
      id:
        "EMERGENCY_STOP_RUNTIME_ACTIVE",
      message:
        `Go-live session is EMERGENCY_STOPPED but encoder runtime is ${snapshot.runtime.session.status}.`,
    });
  }

  if (issues.length > 0) {
    recordBroadcastCoordinatorAudit({
      gameId,
      type:
        "DRIFT_DETECTED",
      correlationId:
        snapshot.coordinator.correlationId,
      detail:
        issues
          .map(
            (issue) =>
              `${issue.id}: ${issue.message}`,
          )
          .join(" | "),
    });
  }

  return {
    gameId,
    healthy:
      issues.length ===
      0,
    checkedAt:
      new Date().toISOString(),
    issues,
  };
}


export type BroadcastCoordinatorReconciliationAction =
  | "NONE"
  | "RESET_INTENT"
  | "STOP_RUNTIME"
  | "REFUSE_AMBIGUOUS";

export type BroadcastCoordinatorReconciliation = {
  gameId: string;
  action:
    BroadcastCoordinatorReconciliationAction;
  repaired: boolean;
  message: string;
  health:
    BroadcastCoordinatorHealth;
  snapshot:
    BroadcastCoordinatorSnapshot;
};

export async function reconcileBroadcastCoordinator(
  gameId: string,
): Promise<BroadcastCoordinatorReconciliation> {
  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "RECONCILE_REQUESTED",
    correlationId:
      getBroadcastCoordinatorRecord(
        gameId,
      ).correlationId,
  });

  const before =
    evaluateBroadcastCoordinatorHealth(
      gameId,
    );

  if (before.healthy) {
    return {
      gameId,
      action:
        "NONE",
      repaired:
        false,
      message:
        "Coordinator state is already healthy.",
      health:
        before,
      snapshot:
        getBroadcastCoordinatorSnapshot(
          gameId,
        ),
    };
  }

  const ids =
    new Set(
      before.issues.map(
        (issue) =>
          issue.id,
      ),
    );

  if (
    ids.has(
      "EMERGENCY_STOP_RUNTIME_ACTIVE",
    ) ||
    ids.has(
      "INTENT_STOP_RUNTIME_ACTIVE",
    )
  ) {
    await stopEncoderRuntime(
      gameId,
    );

    setBroadcastCoordinatorIntent({
      gameId,
      intent:
        "IDLE",
      lastError:
        null,
    });

    const health =
      evaluateBroadcastCoordinatorHealth(
        gameId,
      );

    recordBroadcastCoordinatorAudit({
      gameId,
      type:
        "RECONCILE_COMPLETED",
      correlationId:
        getBroadcastCoordinatorRecord(
          gameId,
        ).correlationId,
      detail:
        "STOP_RUNTIME",
    });

    return {
      gameId,
      action:
        "STOP_RUNTIME",
      repaired:
        health.healthy,
      message:
        health.healthy
          ? "Unexpected active runtime was stopped and coordinator intent reset."
          : "Runtime stop was attempted, but coordinator health still reports drift.",
      health,
      snapshot:
        getBroadcastCoordinatorSnapshot(
          gameId,
        ),
    };
  }

  if (
    ids.has(
      "INTENT_GO_LIVE_RUNTIME_STOPPED",
    ) &&
    ids.has(
      "INTENT_GO_LIVE_SESSION_NOT_ACTIVE",
    )
  ) {
    setBroadcastCoordinatorIntent({
      gameId,
      intent:
        "IDLE",
      lastError:
        null,
    });

    const health =
      evaluateBroadcastCoordinatorHealth(
        gameId,
      );

    recordBroadcastCoordinatorAudit({
      gameId,
      type:
        "RECONCILE_COMPLETED",
      correlationId:
        getBroadcastCoordinatorRecord(
          gameId,
        ).correlationId,
      detail:
        "RESET_INTENT",
    });

    return {
      gameId,
      action:
        "RESET_INTENT",
      repaired:
        health.healthy,
      message:
        health.healthy
          ? "Stale GO_LIVE intent was reset to IDLE."
          : "Coordinator intent was reset, but health still reports drift.",
      health,
      snapshot:
        getBroadcastCoordinatorSnapshot(
          gameId,
        ),
    };
  }

  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "RECONCILE_REFUSED",
    correlationId:
      getBroadcastCoordinatorRecord(
        gameId,
      ).correlationId,
    detail:
      "Coordinator drift is ambiguous and requires operator review.",
  });

  return {
    gameId,
    action:
      "REFUSE_AMBIGUOUS",
    repaired:
      false,
    message:
      "Coordinator drift is ambiguous and requires operator review.",
    health:
      before,
    snapshot:
      getBroadcastCoordinatorSnapshot(
        gameId,
      ),
  };
}


export type BroadcastCoordinatorRetryState =
  | "IDLE"
  | "SCHEDULED"
  | "RETRYING"
  | "EXHAUSTED";

export type BroadcastCoordinatorRetry = {
  gameId: string;
  state: BroadcastCoordinatorRetryState;
  attempts: number;
  maxAttempts: number;
  backoffSeconds: number;
  nextRetryAt: string | null;
  lastError: string | null;
};

const coordinatorRetry =
  new Map<
    string,
    BroadcastCoordinatorRetry
  >();

export function getBroadcastCoordinatorRetry(
  gameId: string,
): BroadcastCoordinatorRetry {
  return (
    coordinatorRetry.get(
      gameId,
    ) ?? {
      gameId,
      state:
        "IDLE",
      attempts:
        0,
      maxAttempts:
        3,
      backoffSeconds:
        10,
      nextRetryAt:
        null,
      lastError:
        null,
    }
  );
}

export function configureBroadcastCoordinatorRetry(input: {
  gameId: string;
  maxAttempts?: number;
  backoffSeconds?: number;
}): BroadcastCoordinatorRetry {
  const current =
    getBroadcastCoordinatorRetry(
      input.gameId,
    );

  const next: BroadcastCoordinatorRetry = {
    ...current,
    maxAttempts:
      Number.isFinite(
        input.maxAttempts,
      )
        ? Math.max(
            0,
            Math.min(
              10,
              Math.floor(
                Number(
                  input.maxAttempts,
                ),
              ),
            ),
          )
        : current.maxAttempts,
    backoffSeconds:
      Number.isFinite(
        input.backoffSeconds,
      )
        ? Math.max(
            1,
            Math.min(
              300,
              Math.floor(
                Number(
                  input.backoffSeconds,
                ),
              ),
            ),
          )
        : current.backoffSeconds,
  };

  coordinatorRetry.set(
    input.gameId,
    next,
  );

  return next;
}

export function scheduleBroadcastCoordinatorRetry(
  gameId: string,
  error: string,
): BroadcastCoordinatorRetry {
  const current =
    getBroadcastCoordinatorRetry(
      gameId,
    );

  if (
    current.attempts >=
    current.maxAttempts
  ) {
    const exhausted: BroadcastCoordinatorRetry = {
      ...current,
      state:
        "EXHAUSTED",
      nextRetryAt:
        null,
      lastError:
        error,
    };

    coordinatorRetry.set(
      gameId,
      exhausted,
    );

    recordBroadcastCoordinatorAudit({
      gameId,
      type:
        "RETRY_EXHAUSTED",
      correlationId:
        getBroadcastCoordinatorRecord(
          gameId,
        ).correlationId,
      detail:
        error,
    });

    return exhausted;
  }

  const nextAttempt =
    current.attempts +
    1;

  const nextRetryAt =
    new Date(
      Date.now() +
        current.backoffSeconds *
          1000 *
          nextAttempt,
    ).toISOString();

  const scheduled: BroadcastCoordinatorRetry = {
    ...current,
    state:
      "SCHEDULED",
    attempts:
      nextAttempt,
    nextRetryAt,
    lastError:
      error,
  };

  coordinatorRetry.set(
    gameId,
    scheduled,
  );

  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "RETRY_SCHEDULED",
    correlationId:
      getBroadcastCoordinatorRecord(
        gameId,
      ).correlationId,
    detail:
      `Attempt ${nextAttempt}/${scheduled.maxAttempts} at ${nextRetryAt}: ${error}`,
  });

  return scheduled;
}

export async function executeBroadcastCoordinatorRetry(
  gameId: string,
): Promise<{
  retry:
    BroadcastCoordinatorRetry;
  snapshot:
    BroadcastCoordinatorSnapshot;
}> {
  const current =
    getBroadcastCoordinatorRetry(
      gameId,
    );

  if (
    current.state !==
    "SCHEDULED"
  ) {
    throw new Error(
      "Coordinator retry is not scheduled.",
    );
  }

  if (
    current.nextRetryAt &&
    Date.now() <
      Date.parse(
        current.nextRetryAt,
      )
  ) {
    throw new Error(
      "Coordinator retry backoff has not elapsed.",
    );
  }

  const retrying: BroadcastCoordinatorRetry = {
    ...current,
    state:
      "RETRYING",
  };

  coordinatorRetry.set(
    gameId,
    retrying,
  );

  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "RETRY_ATTEMPTED",
    correlationId:
      getBroadcastCoordinatorRecord(
        gameId,
      ).correlationId,
    detail:
      `Attempt ${retrying.attempts}/${retrying.maxAttempts}`,
  });

  const preflight =
    evaluateGameDayGoLivePreflight(
      gameId,
    );

  if (!preflight.ready) {
    const retry =
      scheduleBroadcastCoordinatorRetry(
        gameId,
        "Final game-day go-live preflight is still blocked.",
      );

    return {
      retry,
      snapshot:
        getBroadcastCoordinatorSnapshot(
          gameId,
        ),
    };
  }

  const idle: BroadcastCoordinatorRetry = {
    ...retrying,
    state:
      "IDLE",
    attempts:
      0,
    nextRetryAt:
      null,
    lastError:
      null,
  };

  coordinatorRetry.set(
    gameId,
    idle,
  );

  return {
    retry:
      idle,
    snapshot:
      prepareBroadcastSession(
        gameId,
      ),
  };
}

export type BroadcastCoordinatorSupervisorAction =
  | "NONE"
  | "RETRY_EXECUTED"
  | "RECONCILED"
  | "REFUSED";

export type BroadcastCoordinatorSupervisorResult = {
  gameId: string;
  action: BroadcastCoordinatorSupervisorAction;
  checkedAt: string;
  message: string;
  health: BroadcastCoordinatorHealth;
  retry: BroadcastCoordinatorRetry;
  snapshot: BroadcastCoordinatorSnapshot;
};

export async function runBroadcastCoordinatorSupervisorTick(
  gameId: string,
): Promise<BroadcastCoordinatorSupervisorResult> {
  recordBroadcastCoordinatorAudit({
    gameId,
    type: "SUPERVISOR_TICK",
    correlationId: getBroadcastCoordinatorRecord(gameId).correlationId,
  });

  const retry = getBroadcastCoordinatorRetry(gameId);

  if (
    retry.state === "SCHEDULED" &&
    retry.nextRetryAt &&
    Date.now() >= Date.parse(retry.nextRetryAt)
  ) {
    const result = await executeBroadcastCoordinatorRetry(gameId);
    recordBroadcastCoordinatorAudit({
      gameId,
      type: "SUPERVISOR_RETRY_EXECUTED",
      correlationId: getBroadcastCoordinatorRecord(gameId).correlationId,
      detail: result.retry.state,
    });
    return {
      gameId,
      action: "RETRY_EXECUTED",
      checkedAt: new Date().toISOString(),
      message: "Scheduled coordinator retry was executed.",
      health: evaluateBroadcastCoordinatorHealth(gameId),
      retry: result.retry,
      snapshot: result.snapshot,
    };
  }

  const health = evaluateBroadcastCoordinatorHealth(gameId);
  if (!health.healthy) {
    const ids = new Set(health.issues.map((issue) => issue.id));
    const repairable =
      ids.has("EMERGENCY_STOP_RUNTIME_ACTIVE") ||
      ids.has("INTENT_STOP_RUNTIME_ACTIVE") ||
      (
        ids.has("INTENT_GO_LIVE_RUNTIME_STOPPED") &&
        ids.has("INTENT_GO_LIVE_SESSION_NOT_ACTIVE")
      );

    if (repairable) {
      const result = await reconcileBroadcastCoordinator(gameId);
      const refused = result.action === "REFUSE_AMBIGUOUS";
      recordBroadcastCoordinatorAudit({
        gameId,
        type: refused ? "SUPERVISOR_ACTION_REFUSED" : "SUPERVISOR_RECONCILED",
        correlationId: getBroadcastCoordinatorRecord(gameId).correlationId,
        detail: result.action,
      });
      return {
        gameId,
        action: refused ? "REFUSED" : "RECONCILED",
        checkedAt: new Date().toISOString(),
        message: result.message,
        health: result.health,
        retry: getBroadcastCoordinatorRetry(gameId),
        snapshot: result.snapshot,
      };
    }

    recordBroadcastCoordinatorAudit({
      gameId,
      type: "SUPERVISOR_ACTION_REFUSED",
      correlationId: getBroadcastCoordinatorRecord(gameId).correlationId,
      detail: "Drift requires operator review.",
    });
    return {
      gameId,
      action: "REFUSED",
      checkedAt: new Date().toISOString(),
      message: "Coordinator drift requires operator review.",
      health,
      retry,
      snapshot: getBroadcastCoordinatorSnapshot(gameId),
    };
  }

  return {
    gameId,
    action: "NONE",
    checkedAt: new Date().toISOString(),
    message: "Coordinator is healthy and no retry is due.",
    health,
    retry,
    snapshot: getBroadcastCoordinatorSnapshot(gameId),
  };
}
