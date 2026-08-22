#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="15.5-policy-change-audit-actor-attribution"
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
  "$ROOT/apps/api/src/routes/scoreboardControlPolicy.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlPolicy.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlAuthorization.ts" \
  "$ROOT/apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

AUDIT_SERVICE="apps/api/src/services/scoreboardControlPolicyAudit.ts"
POLICY_SERVICE="apps/api/src/services/scoreboardControlPolicy.ts"
POLICY_ROUTE="apps/api/src/routes/scoreboardControlPolicy.ts"
PANEL="apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
TEST="packages/core/test/policy-change-audit-actor-attribution-15.5.test.ts"

for file in \
  "$AUDIT_SERVICE" \
  "$POLICY_SERVICE" \
  "$POLICY_ROUTE" \
  "$PANEL" \
  "$TEST"
do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
  fi
done

mkdir -p \
  "$(dirname "$AUDIT_SERVICE")" \
  "$(dirname "$TEST")"

cat > "$AUDIT_SERVICE" <<'EOF'
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
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/scoreboardControlPolicy.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !text.includes(
    "getScoreboardPhysicalControlPolicyByScope",
  )
) {
  const marker =
    "export function setScoreboardPhysicalControlPolicy(";

  const idx =
    text.indexOf(
      marker,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate setScoreboardPhysicalControlPolicy().",
    );
  }

  const helper = `export function getScoreboardPhysicalControlPolicyByScope(
  scope: ScoreboardPhysicalControlPolicyScope,
): ScoreboardPhysicalControlPolicy | null {
  const key =
    keyOf(scope);

  return (
    store.policies.find(
      (item) =>
        keyOf(item) ===
        key,
    ) ?? null
  );
}

`;

  text =
    text.slice(0, idx) +
    helper +
    text.slice(idx);
}

fs.writeFileSync(
  file,
  text,
);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardControlPolicy.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const auditImport =
  'import { listScoreboardControlPolicyAudit, recordScoreboardControlPolicyAudit } from "../services/scoreboardControlPolicyAudit.js";';

const principalImport =
  'import { getScoreboardControlPrincipal } from "../services/scoreboardControlAuthorization.js";';

if (!text.includes(auditImport)) {
  const imports =
    text.match(
      /^(import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate control policy import block.",
    );
  }

  text =
    text.replace(
      imports[0],
      imports[0] +
        auditImport +
        "\n",
    );
}

if (!text.includes(principalImport)) {
  const imports =
    text.match(
      /^(import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate control policy import block.",
    );
  }

  text =
    text.replace(
      imports[0],
      imports[0] +
        principalImport +
        "\n",
    );
}

if (
  !text.includes(
    "getScoreboardPhysicalControlPolicyByScope",
  )
) {
  text =
    text.replace(
`import {
  deleteScoreboardPhysicalControlPolicy,
  listScoreboardPhysicalControlPolicies,
  setScoreboardPhysicalControlPolicy,
} from "../services/scoreboardControlPolicy.js";`,
`import {
  deleteScoreboardPhysicalControlPolicy,
  getScoreboardPhysicalControlPolicyByScope,
  listScoreboardPhysicalControlPolicies,
  setScoreboardPhysicalControlPolicy,
} from "../services/scoreboardControlPolicy.js";`,
    );
}

if (
  !text.includes(
    "/scoreboard-control-policy-audit",
  )
) {
  const registrationMarker =
    "export async function registerScoreboardControlPolicyRoutes";

  const idx =
    text.indexOf(
      registrationMarker,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate control policy route registration.",
    );
  }

  const open =
    text.indexOf(
      "{",
      idx,
    );

  if (open === -1) {
    throw new Error(
      "Unable to locate control policy route function opening brace.",
    );
  }

  text =
    text.slice(0, open + 1) +
    `
  app.get(
    "/scoreboard-control-policy-audit",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy read permission required.",
        });
      }

      const query =
        request.query as {
          limit?: string;
        };

      const limit =
        query.limit
          ? Number.parseInt(
              query.limit,
              10,
            )
          : 100;

      return {
        success: true,
        data: {
          records:
            listScoreboardControlPolicyAudit(
              Number.isFinite(limit)
                ? limit
                : 100,
            ),
        },
      };
    },
  );

` +
    text.slice(open + 1);
}

if (
  !text.includes(
    "previousPolicy",
  )
) {
  text =
    text.replace(
`      const policy =
        setScoreboardPhysicalControlPolicy(
          scope,
          body.mode as
            ScoreboardPhysicalControlPolicyMode,
          body.reason,
        );`,
`      const previousPolicy =
        getScoreboardPhysicalControlPolicyByScope(
          scope,
        );

      const policy =
        setScoreboardPhysicalControlPolicy(
          scope,
          body.mode as
            ScoreboardPhysicalControlPolicyMode,
          body.reason,
        );

      const principal =
        getScoreboardControlPrincipal(
          request,
        );

      recordScoreboardControlPolicyAudit({
        auditId:
          \`\${Date.now()}-\${Math.random().toString(36).slice(2)}\`,
        action:
          "SET",
        actorUserId:
          principal.userId,
        actorRoles:
          principal.roles,
        previousPolicy,
        nextPolicy:
          policy,
        reason:
          body.reason?.trim() ||
          null,
        createdAt:
          new Date().toISOString(),
      });`,
    );

  text =
    text.replace(
`      return {
        success: true,
        data: {
          deleted:
            deleteScoreboardPhysicalControlPolicy(
              scope,
            ),
        },
      };`,
`      const previousPolicy =
        getScoreboardPhysicalControlPolicyByScope(
          scope,
        );

      const deleted =
        deleteScoreboardPhysicalControlPolicy(
          scope,
        );

      if (deleted) {
        const principal =
          getScoreboardControlPrincipal(
            request,
          );

        recordScoreboardControlPolicyAudit({
          auditId:
            \`\${Date.now()}-\${Math.random().toString(36).slice(2)}\`,
          action:
            "DELETE",
          actorUserId:
            principal.userId,
          actorRoles:
            principal.roles,
          previousPolicy,
          nextPolicy:
            null,
          reason:
            previousPolicy?.reason ??
            null,
          createdAt:
            new Date().toISOString(),
        });
      }

      return {
        success: true,
        data: {
          deleted,
        },
      };`,
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !text.includes(
    "type PolicyAuditRecord",
  )
) {
  const marker =
    "const API_BASE";

  const idx =
    text.indexOf(
      marker,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate API_BASE in policy panel.",
    );
  }

  const typeBlock = `type PolicyAuditRecord = {
  auditId: string;
  action:
    | "SET"
    | "DELETE";
  actorUserId: string | null;
  actorRoles: string[];
  previousPolicy:
    Policy | null;
  nextPolicy:
    Policy | null;
  reason: string | null;
  createdAt: string;
};

`;

  text =
    text.slice(0, idx) +
    typeBlock +
    text.slice(idx);
}

if (
  !text.includes(
    "const [auditRecords",
  )
) {
  const marker =
    'const [error, setError] = useState<string | null>(null);';

  if (!text.includes(marker)) {
    throw new Error(
      "Unable to locate policy panel state anchor.",
    );
  }

  text =
    text.replace(
      marker,
      marker +
        `

  const [auditRecords, setAuditRecords] =
    useState<PolicyAuditRecord[]>([]);`,
    );
}

if (
  !text.includes(
    "/scoreboard-control-policy-audit",
  )
) {
  text =
    text.replace(
`      const response = await fetch(
        \`\${API_BASE}/scoreboard-control-policies\`,
        { cache: "no-store" },
      );`,
`      const [
        response,
        auditResponse,
      ] = await Promise.all([
        fetch(
          \`\${API_BASE}/scoreboard-control-policies\`,
          { cache: "no-store" },
        ),
        fetch(
          \`\${API_BASE}/scoreboard-control-policy-audit?limit=25\`,
          { cache: "no-store" },
        ),
      ]);`,
    );

  text =
    text.replace(
`      const json = await response.json();
      setPolicies(json?.data?.policies ?? []);`,
`      const json = await response.json();
      const auditJson =
        auditResponse.ok
          ? await auditResponse.json()
          : null;

      setPolicies(json?.data?.policies ?? []);
      setAuditRecords(
        auditJson?.data?.records ?? [],
      );`,
    );
}

if (
  !text.includes(
    "Recent Policy Changes",
  )
) {
  const footer =
`      <p className="mt-5 text-xs text-slate-500">
        Dashboard state is informational only. The API policy store remains authoritative.
      </p>`;

  if (!text.includes(footer)) {
    throw new Error(
      "Unable to locate policy panel footer.",
    );
  }

  text =
    text.replace(
      footer,
`      <div className="mt-6">
        <h3 className="font-semibold">
          Recent Policy Changes
        </h3>

        {auditRecords.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">
            No policy changes recorded yet.
          </p>
        ) : (
          <div className="mt-3 space-y-2">
            {auditRecords.map(
              (record) => (
                <div
                  key={record.auditId}
                  className="rounded-lg border border-slate-800 p-3 text-sm"
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="font-medium">
                      {record.action}
                    </span>
                    <span className="text-xs text-slate-500">
                      {record.createdAt}
                    </span>
                  </div>

                  <div className="mt-1 text-slate-400">
                    Actor:{" "}
                    <span className="font-mono text-xs">
                      {record.actorUserId ?? "unknown"}
                    </span>
                  </div>

                  <div className="mt-1 text-slate-400">
                    Roles:{" "}
                    {record.actorRoles.length
                      ? record.actorRoles.join(", ")
                      : "unknown"}
                  </div>

                  {record.reason && (
                    <div className="mt-1 text-slate-400">
                      Reason: {record.reason}
                    </div>
                  )}
                </div>
              ),
            )}
          </div>
        )}
      </div>

${footer}`,
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 15.5 policy change audit / actor attribution", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlPolicyAudit.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlPolicy.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("persists dedicated policy audit records", () => {
    expect(service).toContain(
      "scoreboard-control-policy-audit.json",
    );

    expect(service).toContain(
      "previousPolicy",
    );

    expect(service).toContain(
      "nextPolicy",
    );
  });

  it("records actor identity and roles", () => {
    expect(service).toContain(
      "actorUserId",
    );

    expect(service).toContain(
      "actorRoles",
    );

    expect(route).toContain(
      "getScoreboardControlPrincipal",
    );
  });

  it("audits set and delete operations", () => {
    expect(route).toContain(
      'action:',
    );

    expect(route).toContain(
      '"SET"',
    );

    expect(route).toContain(
      '"DELETE"',
    );
  });

  it("exposes policy audit API", () => {
    expect(route).toContain(
      "/scoreboard-control-policy-audit",
    );

    expect(route).toContain(
      "CONTROL_POLICY_READ",
    );
  });

  it("shows recent policy changes in operator UI", () => {
    expect(panel).toContain(
      "Recent Policy Changes",
    );

    expect(panel).toContain(
      "actorUserId",
    );

    expect(panel).toContain(
      "actorRoles",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 15.5 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - persistent control-policy audit store"
echo "  - SET / DELETE policy audit actions"
echo "  - actor user ID attribution"
echo "  - actor role attribution"
echo "  - previous/next policy capture"
echo "  - operator reason capture"
echo "  - GET /scoreboard-control-policy-audit"
echo "  - Recent Policy Changes operator UI"
echo "  - Milestone 15.5 tests"
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
echo "  Milestone 15.6 - Emergency Physical Control Kill Switch"
