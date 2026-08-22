import fs from "node:fs";
import path from "node:path";

import type {
  ScoreboardPhysicalControlPolicy,
} from "@sportsos/core";

export type ScoreboardControlPolicyAuditAction =
  | "SET"
  | "DELETE";

export type ScoreboardControlPolicyAuditRecord = {
  auditId: string;
  action:
    ScoreboardControlPolicyAuditAction;
  actorUserId: string | null;
  actorRoles: string[];
  previousPolicy:
    ScoreboardPhysicalControlPolicy | null;
  nextPolicy:
    ScoreboardPhysicalControlPolicy | null;
  reason: string | null;
  createdAt: string;
};

type Store = {
  version: 1;
  records:
    ScoreboardControlPolicyAuditRecord[];
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
    "scoreboard-control-policy-audit.json",
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
        "Invalid scoreboard control policy audit store.",
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

export function recordScoreboardControlPolicyAudit(
  record:
    ScoreboardControlPolicyAuditRecord,
): ScoreboardControlPolicyAuditRecord {
  store.records.push(
    record,
  );

  if (
    store.records.length >
    2000
  ) {
    store.records =
      store.records.slice(
        -2000,
      );
  }

  persistStore();

  return record;
}

export function listScoreboardControlPolicyAudit(
  limit = 100,
): ScoreboardControlPolicyAuditRecord[] {
  return [...store.records]
    .sort(
      (a, b) =>
        b.createdAt.localeCompare(
          a.createdAt,
        ),
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
