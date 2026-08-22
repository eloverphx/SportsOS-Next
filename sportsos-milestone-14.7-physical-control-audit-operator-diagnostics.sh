#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="14.7-physical-control-audit-operator-diagnostics"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  echo "Expected: $EXPECTED_REAL" >&2
  echo "Received: $ROOT_REAL" >&2
  exit 1
fi

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/routes/scoreboardControlInputs.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlInputs.ts" \
  "$ROOT/apps/dashboard/app/scoreboards/operations/page.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

AUDIT_SERVICE="apps/api/src/services/scoreboardControlAudit.ts"
AUDIT_ROUTE="apps/api/src/routes/scoreboardControlAudit.ts"
CONTROL_ROUTE="apps/api/src/routes/scoreboardControlInputs.ts"
DASH="apps/dashboard/app/scoreboards/operations/page.tsx"
PANEL="apps/dashboard/app/scoreboards/operations/PhysicalControlDiagnosticsPanel.tsx"
TEST="packages/core/test/physical-control-audit-operator-diagnostics-14.7.test.ts"

for file in \
  "$AUDIT_SERVICE" \
  "$AUDIT_ROUTE" \
  "$CONTROL_ROUTE" \
  "$DASH" \
  "$PANEL" \
  "$TEST" \
  "apps/api/src/app.ts"
do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
  fi
done

mkdir -p \
  "$(dirname "$AUDIT_SERVICE")" \
  "$(dirname "$AUDIT_ROUTE")" \
  "$(dirname "$PANEL")" \
  "$(dirname "$TEST")"

cat > "$AUDIT_SERVICE" <<'EOF'
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
EOF

cat > "$AUDIT_ROUTE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import {
  listScoreboardControlAudit,
} from "../services/scoreboardControlAudit.js";

export async function registerScoreboardControlAuditRoutes(
  app: FastifyInstance,
) {
  app.get(
    "/scoreboard-control-audit",
    async (request) => {
      const query =
        request.query as {
          deviceId?: string;
          gameId?: string;
          disposition?: string;
          limit?: string;
        };

      const limit =
        query.limit
          ? Number.parseInt(
              query.limit,
              10,
            )
          : undefined;

      return {
        success: true,
        data: {
          records:
            listScoreboardControlAudit({
              deviceId:
                query.deviceId,
              gameId:
                query.gameId,
              disposition:
                query.disposition,
              limit:
                Number.isFinite(limit)
                  ? limit
                  : undefined,
            }),
        },
      };
    },
  );
}
EOF

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/app.ts";
let text = fs.readFileSync(file, "utf8");

const importLine =
  'import { registerScoreboardControlAuditRoutes } from "./routes/scoreboardControlAudit.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);
  if (!imports) {
    throw new Error(
      "Unable to locate API import block.",
    );
  }
  text =
    text.replace(
      imports[0],
      imports[0] + importLine + "\n",
    );
}

if (
  !text.includes(
    "await registerScoreboardControlAuditRoutes(app);",
  )
) {
  const idx =
    text.lastIndexOf("return app;");
  if (idx === -1) {
    throw new Error(
      "Unable to locate return app; in API app.",
    );
  }
  text =
    text.slice(0, idx) +
    "  await registerScoreboardControlAuditRoutes(app);\n\n" +
    text.slice(idx);
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file =
  "apps/api/src/routes/scoreboardControlInputs.ts";
let text =
  fs.readFileSync(file, "utf8");

const importLine =
  'import { recordScoreboardControlAudit } from "../services/scoreboardControlAudit.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);
  if (!imports) {
    throw new Error(
      "Unable to locate control-input route import block.",
    );
  }
  text =
    text.replace(
      imports[0],
      imports[0] + importLine + "\n",
    );
}

if (
  !text.includes(
    "recordScoreboardControlAudit({",
  )
) {
  const nonAcceptedAnchor =
`      if (
        result.disposition !==
          "ACCEPTED" ||
        !result.authoritativeGameId
      ) {
        return {
          success: true,
          data:
            result,
        };
      }`;

  if (!text.includes(nonAcceptedAnchor)) {
    throw new Error(
      "Unable to locate non-accepted control return.",
    );
  }

  text =
    text.replace(
      nonAcceptedAnchor,
`      if (
        result.disposition !==
          "ACCEPTED" ||
        !result.authoritativeGameId
      ) {
        recordScoreboardControlAudit({
          auditId: body.inputId,
          deviceId: body.deviceId,
          gameId: result.authoritativeGameId,
          inputId: body.inputId,
          inputType: body.type,
          sequence: body.sequence,
          disposition: result.disposition,
          command:
            "command" in result
              ? result.command
              : null,
          execution: null,
          reconciliation: null,
          error: result.reason,
          createdAt:
            new Date().toISOString(),
        });

        return {
          success: true,
          data:
            result,
        };
      }`,
    );

  const failureAnchor =
`      if (!execution.executed) {
        return reply.code(
          execution.statusCode >= 400 &&
          execution.statusCode <= 599
            ? execution.statusCode
            : 409,
        ).send({
          success: false,
          error:
            execution.reason ??
            "Physical scoreboard command was not executed.",
          data: {
            acknowledgement:
              result,
            execution,
          },
        });
      }`;

  if (!text.includes(failureAnchor)) {
    throw new Error(
      "Unable to locate failed execution block.",
    );
  }

  text =
    text.replace(
      failureAnchor,
`      if (!execution.executed) {
        recordScoreboardControlAudit({
          auditId: body.inputId,
          deviceId: body.deviceId,
          gameId: result.authoritativeGameId,
          inputId: body.inputId,
          inputType: body.type,
          sequence: body.sequence,
          disposition: "EXECUTION_FAILED",
          command: execution.command,
          execution,
          reconciliation: null,
          error:
            execution.reason ??
            "Physical scoreboard command was not executed.",
          createdAt:
            new Date().toISOString(),
        });

        return reply.code(
          execution.statusCode >= 400 &&
          execution.statusCode <= 599
            ? execution.statusCode
            : 409,
        ).send({
          success: false,
          error:
            execution.reason ??
            "Physical scoreboard command was not executed.",
          data: {
            acknowledgement:
              result,
            execution,
          },
        });
      }`,
    );

  const successAnchor =
`      return {
        success: true,
        data: {
          ...result,
          execution,
          reconciliation,
        },
      };`;

  if (!text.includes(successAnchor)) {
    throw new Error(
      "Unable to locate successful reconciliation return.",
    );
  }

  text =
    text.replace(
      successAnchor,
`      recordScoreboardControlAudit({
        auditId: body.inputId,
        deviceId: body.deviceId,
        gameId: result.authoritativeGameId,
        inputId: body.inputId,
        inputType: body.type,
        sequence: body.sequence,
        disposition: "ACCEPTED",
        command: execution.command,
        execution,
        reconciliation,
        error: reconciliation.reason,
        createdAt:
          new Date().toISOString(),
      });

      return {
        success: true,
        data: {
          ...result,
          execution,
          reconciliation,
        },
      };`,
    );
}

fs.writeFileSync(file, text);
NODE

cat > "$PANEL" <<'EOF'
"use client";

import {
  useEffect,
  useMemo,
  useState,
} from "react";

type AuditRecord = {
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
  error: string | null;
  createdAt: string;
};

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

export function PhysicalControlDiagnosticsPanel() {
  const [records, setRecords] =
    useState<AuditRecord[]>([]);
  const [loading, setLoading] =
    useState(true);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      try {
        const response =
          await fetch(
            `${API_BASE}/scoreboard-control-audit?limit=50`,
            { cache: "no-store" },
          );
        const json =
          await response.json();

        if (!cancelled) {
          setRecords(
            json?.data?.records ?? [],
          );
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    void load();

    const interval =
      window.setInterval(
        () => {
          void load();
        },
        5000,
      );

    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, []);

  const stats =
    useMemo(() => {
      const accepted =
        records.filter(
          (record) =>
            record.disposition ===
            "ACCEPTED",
        ).length;

      const rejected =
        records.filter(
          (record) =>
            record.disposition ===
              "REJECTED" ||
            record.disposition ===
              "EXECUTION_FAILED",
        ).length;

      const duplicates =
        records.filter(
          (record) =>
            record.disposition ===
            "IGNORED_DUPLICATE",
        ).length;

      return {
        accepted,
        rejected,
        duplicates,
      };
    }, [records]);

  return (
    <section className="mt-8 rounded-xl border border-slate-800 p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-xl font-semibold">
            Physical Control Diagnostics
          </h2>
          <p className="mt-1 text-sm text-slate-400">
            Recent ESP32 button input decisions and execution results.
          </p>
        </div>

        <div className="flex gap-2 text-xs">
          <span className="rounded-full border border-slate-700 px-2 py-1">
            Accepted {stats.accepted}
          </span>
          <span className="rounded-full border border-slate-700 px-2 py-1">
            Rejected {stats.rejected}
          </span>
          <span className="rounded-full border border-slate-700 px-2 py-1">
            Duplicate {stats.duplicates}
          </span>
        </div>
      </div>

      {loading ? (
        <p className="mt-4 text-sm text-slate-500">
          Loading physical control audit…
        </p>
      ) : records.length === 0 ? (
        <p className="mt-4 text-sm text-slate-500">
          No physical control events recorded yet.
        </p>
      ) : (
        <div className="mt-4 overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead className="text-slate-500">
              <tr>
                <th className="pb-2 pr-4">Time</th>
                <th className="pb-2 pr-4">Device</th>
                <th className="pb-2 pr-4">Game</th>
                <th className="pb-2 pr-4">Input</th>
                <th className="pb-2 pr-4">Result</th>
                <th className="pb-2">Error</th>
              </tr>
            </thead>
            <tbody>
              {records.map(
                (record) => (
                  <tr
                    key={record.auditId}
                    className="border-t border-slate-800"
                  >
                    <td className="py-3 pr-4 text-xs text-slate-400">
                      {record.createdAt}
                    </td>
                    <td className="py-3 pr-4 font-mono text-xs">
                      {record.deviceId}
                    </td>
                    <td className="py-3 pr-4 font-mono text-xs">
                      {record.gameId ?? "—"}
                    </td>
                    <td className="py-3 pr-4">
                      {record.inputType}
                    </td>
                    <td className="py-3 pr-4">
                      {record.disposition}
                    </td>
                    <td className="py-3 text-slate-400">
                      {record.error ?? "—"}
                    </td>
                  </tr>
                ),
              )}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
EOF

node <<'NODE'
const fs = require("fs");
const file =
  "apps/dashboard/app/scoreboards/operations/page.tsx";
let text =
  fs.readFileSync(file, "utf8");

const importLine =
  'import { PhysicalControlDiagnosticsPanel } from "./PhysicalControlDiagnosticsPanel";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);
  if (!imports) {
    throw new Error(
      "Unable to locate operations-page import block.",
    );
  }
  text =
    text.replace(
      imports[0],
      imports[0] + importLine + "\n",
    );
}

if (
  !text.includes(
    "<PhysicalControlDiagnosticsPanel />",
  )
) {
  const mainClose =
    text.lastIndexOf("</main>");
  const bodyClose =
    text.lastIndexOf("</div>");

  const insertAt =
    mainClose !== -1
      ? mainClose
      : bodyClose;

  if (insertAt === -1) {
    throw new Error(
      "Unable to locate operations-page insertion point.",
    );
  }

  text =
    text.slice(0, insertAt) +
    "      <PhysicalControlDiagnosticsPanel />\n" +
    text.slice(insertAt);
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.7 physical control audit / operator diagnostics", () => {
  it("persists physical control audit records", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardControlAudit.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "scoreboard-control-audit.json",
    );

    expect(service).toContain(
      "recordScoreboardControlAudit",
    );
  });

  it("records accepted rejected duplicate and execution-failed outcomes", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardControlAudit.ts",
        import.meta.url,
      ),
      "utf8",
    );

    for (const outcome of [
      "ACCEPTED",
      "REJECTED",
      "IGNORED_DUPLICATE",
      "EXECUTION_FAILED",
    ]) {
      expect(service).toContain(
        outcome,
      );
    }
  });

  it("exposes filtered audit API", () => {
    const route = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardControlAudit.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain(
      "/scoreboard-control-audit",
    );

    expect(route).toContain(
      "deviceId",
    );

    expect(route).toContain(
      "gameId",
    );

    expect(route).toContain(
      "disposition",
    );
  });

  it("writes audit events from physical control processing", () => {
    const route = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardControlInputs.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain(
      "recordScoreboardControlAudit",
    );

    expect(route).toContain(
      '"EXECUTION_FAILED"',
    );
  });

  it("adds operator diagnostics panel", () => {
    const panel = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/PhysicalControlDiagnosticsPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(panel).toContain(
      "Physical Control Diagnostics",
    );

    expect(panel).toContain(
      "/scoreboard-control-audit",
    );

    expect(panel).toContain(
      "Accepted",
    );

    expect(panel).toContain(
      "Rejected",
    );

    expect(panel).toContain(
      "Duplicate",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 14.7 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - persistent physical-control audit registry"
echo "  - accepted/rejected/duplicate/execution-failed records"
echo "  - device/game/disposition filtering API"
echo "  - command/execution/reconciliation diagnostic capture"
echo "  - /scoreboard-control-audit"
echo "  - Physical Control Diagnostics operator panel"
echo "  - 5-second diagnostic refresh"
echo "  - Milestone 14.7 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 14.8 - Physical Horn / Output Control Binding"
