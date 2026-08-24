import fs from "node:fs";
import path from "node:path";

export type BroadcastCoordinatorAuditType =
  | "INTENT_CHANGED"
  | "PREPARE_REQUESTED"
  | "PREPARE_BLOCKED"
  | "START_REQUESTED"
  | "START_COMPLETED"
  | "START_BLOCKED"
  | "STOP_REQUESTED"
  | "STOP_COMPLETED"
  | "DRIFT_DETECTED"
  | "RECONCILE_REQUESTED"
  | "RECONCILE_COMPLETED"
  | "RECONCILE_REFUSED"
  | "RETRY_SCHEDULED"
  | "RETRY_ATTEMPTED"
  | "RETRY_EXHAUSTED"
  | "SUPERVISOR_TICK"
  | "SUPERVISOR_RETRY_EXECUTED"
  | "SUPERVISOR_RECONCILED"
  | "SUPERVISOR_ACTION_REFUSED"
  | "SUPERVISOR_STARTED"
  | "SUPERVISOR_STOPPED"
  | "SUPERVISOR_TICK_FAILED";

export type BroadcastCoordinatorAuditEvent = {
  id: string;
  gameId: string;
  type: BroadcastCoordinatorAuditType;
  timestamp: string;
  correlationId: string | null;
  detail: string | null;
};

type Store = {
  version: 1;
  events: BroadcastCoordinatorAuditEvent[];
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
    "broadcast-coordinator-audit.json",
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
        parsed.events,
      )
    ) {
      throw new Error(
        "Invalid coordinator audit store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      events: [],
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

  fs.writeFileSync(
    STORE_FILE,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );
}

export function recordBroadcastCoordinatorAudit(input: {
  gameId: string;
  type: BroadcastCoordinatorAuditType;
  correlationId?: string | null;
  detail?: string | null;
}): BroadcastCoordinatorAuditEvent {
  const event: BroadcastCoordinatorAuditEvent = {
    id:
      `broadcast-coordinator-audit-${input.gameId}-${Date.now()}-${Math.random()
        .toString(36)
        .slice(2, 8)}`,
    gameId:
      input.gameId,
    type:
      input.type,
    timestamp:
      new Date().toISOString(),
    correlationId:
      input.correlationId ??
      null,
    detail:
      input.detail ??
      null,
  };

  store.events.push(
    event,
  );

  if (
    store.events.length >
    2500
  ) {
    store.events =
      store.events.slice(
        -2500,
      );
  }

  persistStore();

  return {
    ...event,
  };
}

export function listBroadcastCoordinatorAudit(
  gameId: string,
  limit = 100,
): BroadcastCoordinatorAuditEvent[] {
  const safeLimit =
    Math.max(
      1,
      Math.min(
        Math.floor(
          limit,
        ),
        250,
      ),
    );

  return store.events
    .filter(
      (event) =>
        event.gameId ===
        gameId,
    )
    .slice(
      -safeLimit,
    )
    .reverse()
    .map(
      (event) => ({
        ...event,
      }),
    );
}
