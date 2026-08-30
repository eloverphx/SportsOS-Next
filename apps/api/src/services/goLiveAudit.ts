import fs from "node:fs";
import path from "node:path";

export type GoLiveAuditEventType =
  | "ARMED"
  | "START_REQUESTED"
  | "STARTING"
  | "LIVE_CONFIRMED"
  | "DEGRADED"
  | "RECOVERED"
  | "INCIDENT_ACKNOWLEDGED"
  | "INCIDENT_RETRY"
  | "STOP_REQUESTED"
  | "COMPLETE"
  | "EMERGENCY_STOP"
  | "RESET"
  | "ERROR";

export type GoLiveAuditEvent = {
  id: string;
  gameId: string;
  type: GoLiveAuditEventType;
  timestamp: string;
  detail: string | null;
  operator: string | null;
};

type Store = {
  version: 1;
  events: GoLiveAuditEvent[];
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
    "go-live-audit.json",
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
        "Invalid go-live audit store.",
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

export function recordGoLiveAuditEvent(input: {
  gameId: string;
  type: GoLiveAuditEventType;
  detail?: string | null;
  operator?: string | null;
}): GoLiveAuditEvent {
  const event: GoLiveAuditEvent = {
    id:
      `go-live-audit-${input.gameId}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    gameId:
      input.gameId,
    type:
      input.type,
    timestamp:
      new Date().toISOString(),
    detail:
      input.detail ??
      null,
    operator:
      input.operator ??
      null,
  };

  store.events.push(
    event,
  );

  if (
    store.events.length >
    2000
  ) {
    store.events =
      store.events.slice(
        -2000,
      );
  }

  persistStore();

  return {
    ...event,
  };
}

export function listGoLiveAuditEvents(
  gameId: string,
  limit = 100,
): GoLiveAuditEvent[] {
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
