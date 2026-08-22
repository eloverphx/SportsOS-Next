import fs from "node:fs";
import path from "node:path";

export type ScoreboardControlAuditRecord = {
  auditId: string;
  deviceId: string;
  gameId: string | null;
  inputId: string;
  inputType: string;
  sequence: number;
  disposition:
    | "ACCEPTED"
    | "REJECTED"
    | "IGNORED_DUPLICATE"
    | "EXECUTION_FAILED";
  command: unknown;
  execution: unknown;
  reconciliation: unknown;
  error: string | null;
  createdAt: string;
};

type AuditStore = {
  version: 1;
  records: ScoreboardControlAuditRecord[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(process.cwd(), "data");

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-control-audit.json",
  );

let store = loadStore();

function loadStore(): AuditStore {
  try {
    const parsed =
      JSON.parse(
        fs.readFileSync(
          STORE_FILE,
          "utf8",
        ),
      ) as AuditStore;

    if (
      parsed.version !== 1 ||
      !Array.isArray(parsed.records)
    ) {
      throw new Error(
        "Invalid scoreboard control audit store.",
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
    { recursive: true },
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

export function recordScoreboardControlAudit(
  record: ScoreboardControlAuditRecord,
): ScoreboardControlAuditRecord {
  store.records.push(record);

  if (store.records.length > 2000) {
    store.records =
      store.records.slice(-2000);
  }

  persistStore();
  return record;
}

export function listScoreboardControlAudit(input?: {
  deviceId?: string;
  gameId?: string;
  disposition?: string;
  limit?: number;
}): ScoreboardControlAuditRecord[] {
  const limit =
    Math.max(
      1,
      Math.min(
        input?.limit ?? 100,
        500,
      ),
    );

  return store.records
    .filter(
      (record) =>
        (!input?.deviceId ||
          record.deviceId === input.deviceId) &&
        (!input?.gameId ||
          record.gameId === input.gameId) &&
        (!input?.disposition ||
          record.disposition === input.disposition),
    )
    .sort(
      (a, b) =>
        b.createdAt.localeCompare(
          a.createdAt,
        ),
    )
    .slice(0, limit);
}


export type ScoreboardControlIncident = {
  auditId: string;
  deviceId: string;
  gameId: string | null;
  inputId: string;
  inputType: string;
  sequence: number;
  disposition: string;
  error: string | null;
  createdAt: string;
};

export function listScoreboardControlIncidents(
  limit = 100,
): ScoreboardControlIncident[] {
  return listScoreboardControlAudit({
    limit:
      Math.max(
        100,
        Math.min(
          limit * 5,
          1000,
        ),
      ),
  })
    .filter(
      (record) =>
        record.disposition === "REJECTED" ||
        Boolean(record.error),
    )
    .map(
      (record) => ({
        auditId: record.auditId,
        deviceId: record.deviceId,
        gameId: record.gameId ?? null,
        inputId: record.inputId,
        inputType: record.inputType,
        sequence: record.sequence,
        disposition: record.disposition,
        error: record.error ?? null,
        createdAt: record.createdAt,
      }),
    )
    .slice(
      0,
      Math.max(
        1,
        Math.min(
          limit,
          500,
        ),
      ),
    );
}


export type ScoreboardControlReadinessEvent = {
  auditId: string;
  deviceId: string;
  gameId: string | null;
  eventType:
    | "DEVICE_READINESS_DEGRADED"
    | "DEVICE_READINESS_RESTORED";
  disposition: string;
  error: string | null;
  createdAt: string;
};

export function listScoreboardControlReadinessEvents(
  limit = 100,
): ScoreboardControlReadinessEvent[] {
  return listScoreboardControlAudit({
    limit:
      Math.max(
        100,
        Math.min(
          limit * 5,
          1000,
        ),
      ),
  })
    .filter(
      (record) =>
        record.inputType ===
          "DEVICE_READINESS_DEGRADED" ||
        record.inputType ===
          "DEVICE_READINESS_RESTORED",
    )
    .map(
      (record) => ({
        auditId:
          record.auditId,
        deviceId:
          record.deviceId,
        gameId:
          record.gameId ??
          null,
        eventType:
          record.inputType as
            | "DEVICE_READINESS_DEGRADED"
            | "DEVICE_READINESS_RESTORED",
        disposition:
          record.disposition,
        error:
          record.error ??
          null,
        createdAt:
          record.createdAt,
      }),
    )
    .slice(
      0,
      Math.max(
        1,
        Math.min(
          limit,
          500,
        ),
      ),
    );
}
