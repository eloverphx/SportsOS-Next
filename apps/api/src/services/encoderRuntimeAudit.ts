import fs from "node:fs";
import path from "node:path";

export type EncoderAuditEventType =
  | "START_REQUESTED"
  | "RUNTIME_STARTED"
  | "RUNTIME_LIVE"
  | "STOP_REQUESTED"
  | "RUNTIME_STOPPED"
  | "RUNTIME_ERROR"
  | "RESTART_SCHEDULED"
  | "RESTARTING"
  | "RESTART_EXHAUSTED";

export type EncoderAuditEvent = {
  id: string;
  gameId: string;
  type: EncoderAuditEventType;
  timestamp: string;
  detail: string | null;
  attempt: number | null;
};

type Store = {
  version: 1;
  events: EncoderAuditEvent[];
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
    "encoder-runtime-audit.json",
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
        "Invalid encoder runtime audit store.",
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

export function recordEncoderAuditEvent(input: {
  gameId: string;
  type: EncoderAuditEventType;
  detail?: string | null;
  attempt?: number | null;
}): EncoderAuditEvent {
  const timestamp =
    new Date().toISOString();

  const event: EncoderAuditEvent = {
    id:
      `encoder-audit-${input.gameId}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    gameId:
      input.gameId,
    type:
      input.type,
    timestamp,
    detail:
      input.detail ??
      null,
    attempt:
      input.attempt ??
      null,
  };

  store.events.push(
    event,
  );

  if (
    store.events.length >
    1000
  ) {
    store.events =
      store.events.slice(
        -1000,
      );
  }

  persistStore();

  return {
    ...event,
  };
}

export function listEncoderAuditEvents(
  gameId: string,
  limit = 50,
): EncoderAuditEvent[] {
  const safeLimit =
    Math.max(
      1,
      Math.min(
        Math.floor(
          limit,
        ),
        200,
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
