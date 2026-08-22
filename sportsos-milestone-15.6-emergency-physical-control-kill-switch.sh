#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="15.6-emergency-physical-control-kill-switch"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && -n "$EXPECTED_REAL" ]] || {
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
}

[[ "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  exit 1
}

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/routes/scoreboardControlInputs.ts" \
  "$ROOT/apps/api/src/routes/scoreboardControlPolicy.ts" \
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

SERVICE="apps/api/src/services/scoreboardEmergencyControlLock.ts"
ROUTE="apps/api/src/routes/scoreboardControlPolicy.ts"
INPUT_ROUTE="apps/api/src/routes/scoreboardControlInputs.ts"
PANEL="apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
TEST="packages/core/test/emergency-physical-control-kill-switch-15.6.test.ts"

for file in "$SERVICE" "$ROUTE" "$INPUT_ROUTE" "$PANEL" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type EmergencyPhysicalControlLock = {
  active: boolean;
  reason: string | null;
  actorUserId: string | null;
  actorRoles: string[];
  changedAt: string | null;
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(process.cwd(), "data");

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-emergency-control-lock.json",
  );

const DEFAULT_STATE: EmergencyPhysicalControlLock = {
  active: false,
  reason: null,
  actorUserId: null,
  actorRoles: [],
  changedAt: null,
};

let state = load();

function load(): EmergencyPhysicalControlLock {
  try {
    const parsed =
      JSON.parse(
        fs.readFileSync(STORE_FILE, "utf8"),
      ) as EmergencyPhysicalControlLock;

    if (typeof parsed.active !== "boolean") {
      throw new Error("Invalid emergency lock store.");
    }

    return {
      active: parsed.active,
      reason:
        typeof parsed.reason === "string"
          ? parsed.reason
          : null,
      actorUserId:
        typeof parsed.actorUserId === "string"
          ? parsed.actorUserId
          : null,
      actorRoles:
        Array.isArray(parsed.actorRoles)
          ? parsed.actorRoles.filter(
              (role): role is string =>
                typeof role === "string",
            )
          : [],
      changedAt:
        typeof parsed.changedAt === "string"
          ? parsed.changedAt
          : null,
    };
  } catch {
    return { ...DEFAULT_STATE };
  }
}

function persist(): void {
  fs.mkdirSync(DATA_DIR, { recursive: true });

  const temporary =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    temporary,
    JSON.stringify(state, null, 2),
    "utf8",
  );

  fs.renameSync(
    temporary,
    STORE_FILE,
  );
}

export function getEmergencyPhysicalControlLock():
  EmergencyPhysicalControlLock {
  return {
    ...state,
    actorRoles: [...state.actorRoles],
  };
}

export function setEmergencyPhysicalControlLock(input: {
  active: boolean;
  reason?: string | null;
  actorUserId: string | null;
  actorRoles: string[];
}): EmergencyPhysicalControlLock {
  state = {
    active: input.active,
    reason:
      input.reason?.trim() ||
      null,
    actorUserId: input.actorUserId,
    actorRoles: [...input.actorRoles],
    changedAt: new Date().toISOString(),
  };

  persist();

  return getEmergencyPhysicalControlLock();
}
EOF

node <<'NODE'
const fs = require("fs");
const file =
  "apps/api/src/routes/scoreboardControlPolicy.ts";
let text = fs.readFileSync(file, "utf8");

const emergencyImport =
  'import { getEmergencyPhysicalControlLock, setEmergencyPhysicalControlLock } from "../services/scoreboardEmergencyControlLock.js";';

if (!text.includes(emergencyImport)) {
  const imports = text.match(/^(import[\s\S]*?;\n)+/);
  if (!imports) throw new Error("Unable to locate policy imports.");
  text = text.replace(
    imports[0],
    imports[0] + emergencyImport + "\n",
  );
}

if (!text.includes("/scoreboard-control-emergency-lock")) {
  const marker =
    "export async function registerScoreboardControlPolicyRoutes";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate route registration.");
  const open = text.indexOf("{", idx);
  if (open === -1) throw new Error("Unable to locate registration body.");

  const routes = `
  app.get(
    "/scoreboard-control-emergency-lock",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error: "Physical control policy read permission required.",
        });
      }

      return {
        success: true,
        data: {
          emergencyLock:
            getEmergencyPhysicalControlLock(),
        },
      };
    },
  );

  app.put(
    "/scoreboard-control-emergency-lock",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_WRITE",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error: "Physical control policy write permission required.",
        });
      }

      const body =
        request.body as {
          active?: boolean;
          reason?: string | null;
        };

      if (typeof body?.active !== "boolean") {
        return reply.code(400).send({
          success: false,
          error: "Emergency lock active state is required.",
        });
      }

      if (
        body.active &&
        !body.reason?.trim()
      ) {
        return reply.code(400).send({
          success: false,
          error: "A reason is required to activate the emergency lock.",
        });
      }

      const principal =
        getScoreboardControlPrincipal(request);

      const previous =
        getEmergencyPhysicalControlLock();

      const emergencyLock =
        setEmergencyPhysicalControlLock({
          active: body.active,
          reason: body.reason,
          actorUserId: principal.userId,
          actorRoles: principal.roles,
        });

      recordScoreboardControlPolicyAudit({
        auditId:
          \`\${Date.now()}-\${Math.random().toString(36).slice(2)}\`,
        action: "SET",
        actorUserId: principal.userId,
        actorRoles: principal.roles,
        previousPolicy: null,
        nextPolicy: null,
        reason:
          body.reason?.trim() ||
          (
            body.active
              ? "Emergency physical-control lock activated."
              : "Emergency physical-control lock cleared."
          ),
        createdAt:
          new Date().toISOString(),
      });

      return {
        success: true,
        data: {
          previousEmergencyLock: previous,
          emergencyLock,
        },
      };
    },
  );

`;

  text =
    text.slice(0, open + 1) +
    routes +
    text.slice(open + 1);
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file =
  "apps/api/src/routes/scoreboardControlInputs.ts";
let text = fs.readFileSync(file, "utf8");

const importLine =
  'import { getEmergencyPhysicalControlLock } from "../services/scoreboardEmergencyControlLock.js";';

if (!text.includes(importLine)) {
  const imports = text.match(/^(import[\s\S]*?;\n)+/);
  if (!imports) throw new Error("Unable to locate control-input imports.");
  text = text.replace(
    imports[0],
    imports[0] + importLine + "\n",
  );
}

if (!text.includes("emergencyPhysicalControlLock")) {
  const anchor =
`      const policyDecision =
        evaluateScoreboardPhysicalControlPolicy(`;

  const idx = text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate physical-control policy enforcement anchor.",
    );
  }

  const insertion = `      const emergencyPhysicalControlLock =
        getEmergencyPhysicalControlLock();

      if (emergencyPhysicalControlLock.active) {
        recordScoreboardControlAudit({
          auditId: body.inputId,
          deviceId: body.deviceId,
          gameId: result.authoritativeGameId,
          inputId: body.inputId,
          inputType: body.type,
          sequence: body.sequence,
          disposition: "REJECTED",
          command:
            "command" in result
              ? result.command
              : null,
          execution: null,
          reconciliation: null,
          error:
            emergencyPhysicalControlLock.reason ??
            "Emergency physical-control lock is active.",
          createdAt: new Date().toISOString(),
        });

        return reply.code(423).send({
          success: false,
          error:
            emergencyPhysicalControlLock.reason ??
            "Emergency physical-control lock is active.",
          data: {
            acknowledgement: {
              ...result,
              disposition: "REJECTED",
              reason:
                emergencyPhysicalControlLock.reason ??
                "Emergency physical-control lock is active.",
            },
            emergencyLock:
              emergencyPhysicalControlLock,
          },
        });
      }

`;

  text =
    text.slice(0, idx) +
    insertion +
    text.slice(idx);
}

const emergencyIndex =
  text.indexOf("emergencyPhysicalControlLock");
const executionIndex =
  text.indexOf("executePhysicalScoreboardControl(");

if (
  emergencyIndex === -1 ||
  executionIndex === -1 ||
  emergencyIndex > executionIndex
) {
  throw new Error(
    "Emergency lock is not enforced before authoritative execution.",
  );
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file =
  "apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("type EmergencyLock")) {
  const marker = "type PolicyAuditRecord";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate policy audit type.");

  text =
    text.slice(0, idx) +
`type EmergencyLock = {
  active: boolean;
  reason: string | null;
  actorUserId: string | null;
  actorRoles: string[];
  changedAt: string | null;
};

` +
    text.slice(idx);
}

if (!text.includes("const [emergencyLock")) {
  const marker =
    "const [auditRecords, setAuditRecords] =";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate audit state.");

  text =
    text.slice(0, idx) +
`const [emergencyLock, setEmergencyLock] =
    useState<EmergencyLock | null>(null);

  const [emergencyReason, setEmergencyReason] =
    useState("");

  ` +
    text.slice(idx);
}

if (!text.includes("scoreboard-control-emergency-lock")) {
  text = text.replace(
`        fetch(
          \`\${API_BASE}/scoreboard-control-policy-audit?limit=25\`,
          { cache: "no-store" },
        ),
      ]);`,
`        fetch(
          \`\${API_BASE}/scoreboard-control-policy-audit?limit=25\`,
          { cache: "no-store" },
        ),
        fetch(
          \`\${API_BASE}/scoreboard-control-emergency-lock\`,
          { cache: "no-store" },
        ),
      ]);`
  );

  text = text.replace(
`      const [
        response,
        auditResponse,
      ] = await Promise.all([`,
`      const [
        response,
        auditResponse,
        emergencyResponse,
      ] = await Promise.all([`
  );

  text = text.replace(
`      setAuditRecords(
        auditJson?.data?.records ?? [],
      );`,
`      setAuditRecords(
        auditJson?.data?.records ?? [],
      );

      if (emergencyResponse.ok) {
        const emergencyJson =
          await emergencyResponse.json();

        setEmergencyLock(
          emergencyJson?.data?.emergencyLock ??
          null,
        );
      }`
  );
}

if (!text.includes("async function updateEmergencyLock")) {
  const marker = "  async function savePolicy";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate savePolicy.");

  text =
    text.slice(0, idx) +
`  async function updateEmergencyLock(
    active: boolean,
  ) {
    if (
      active &&
      !emergencyReason.trim()
    ) {
      setError(
        "Enter a reason before activating the emergency lock.",
      );
      return;
    }

    setSaving(true);

    try {
      const response = await fetch(
        \`\${API_BASE}/scoreboard-control-emergency-lock\`,
        {
          method: "PUT",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            active,
            reason:
              emergencyReason.trim() ||
              (
                active
                  ? null
                  : "Emergency lock cleared by operator."
              ),
          }),
        },
      );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          \`Emergency lock update failed (\${response.status}).\`,
        );
      }

      setEmergencyReason("");
      setError(null);
      await loadPolicies();
    } catch (updateError) {
      setError(
        updateError instanceof Error
          ? updateError.message
          : "Unable to update emergency physical-control lock.",
      );
    } finally {
      setSaving(false);
    }
  }

` +
    text.slice(idx);
}

if (!text.includes("Emergency Physical Control Lock")) {
  const formMarker = "      <form\n        onSubmit={savePolicy}";
  const idx = text.indexOf(formMarker);
  if (idx === -1) throw new Error("Unable to locate policy form.");

  const block = `      <div className="mt-5 rounded-xl border border-amber-800/60 bg-amber-950/20 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="font-semibold">
              Emergency Physical Control Lock
            </h3>
            <p className="mt-1 text-sm text-slate-400">
              Immediately blocks all physical scoreboard button mutations.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-3 py-1 text-sm font-medium">
            {emergencyLock?.active
              ? "ACTIVE"
              : "CLEAR"}
          </span>
        </div>

        <input
          value={emergencyReason}
          onChange={(event) =>
            setEmergencyReason(
              event.target.value,
            )
          }
          placeholder={
            emergencyLock?.active
              ? "Reason for clearing lock"
              : "Required reason for emergency lock"
          }
          className="mt-4 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm"
        />

        <div className="mt-3 flex flex-wrap gap-2">
          {!emergencyLock?.active ? (
            <button
              type="button"
              disabled={saving}
              onClick={() =>
                void updateEmergencyLock(true)
              }
              className="rounded-lg border border-amber-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
            >
              Activate Emergency Lock
            </button>
          ) : (
            <button
              type="button"
              disabled={saving}
              onClick={() =>
                void updateEmergencyLock(false)
              }
              className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
            >
              Clear Emergency Lock
            </button>
          )}
        </div>

        {emergencyLock?.active &&
          emergencyLock.reason && (
            <p className="mt-3 text-sm text-amber-200">
              Active reason: {emergencyLock.reason}
            </p>
          )}
      </div>

`;

  text =
    text.slice(0, idx) +
    block +
    text.slice(idx);
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

describe("Milestone 15.6 emergency physical control kill switch", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardEmergencyControlLock.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const policyRoute = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlPolicy.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const inputRoute = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlInputs.ts",
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

  it("persists emergency lock state", () => {
    expect(service).toContain(
      "scoreboard-emergency-control-lock.json",
    );
    expect(service).toContain("active");
    expect(service).toContain("actorUserId");
  });

  it("requires policy permissions to operate emergency lock", () => {
    expect(policyRoute).toContain(
      "/scoreboard-control-emergency-lock",
    );
    expect(policyRoute).toContain(
      '"CONTROL_POLICY_WRITE"',
    );
    expect(policyRoute).toContain(
      '"CONTROL_POLICY_READ"',
    );
  });

  it("requires a reason when activating the emergency lock", () => {
    expect(policyRoute).toContain(
      "A reason is required to activate the emergency lock.",
    );
  });

  it("rejects physical mutation before execution while emergency lock is active", () => {
    const lockIndex =
      inputRoute.indexOf(
        "emergencyPhysicalControlLock",
      );
    const executionIndex =
      inputRoute.indexOf(
        "executePhysicalScoreboardControl",
      );

    expect(lockIndex).toBeGreaterThan(-1);
    expect(executionIndex).toBeGreaterThan(lockIndex);
    expect(inputRoute).toContain("reply.code(423)");
  });

  it("exposes emergency lock controls in operator UI", () => {
    expect(panel).toContain(
      "Emergency Physical Control Lock",
    );
    expect(panel).toContain(
      "Activate Emergency Lock",
    );
    expect(panel).toContain(
      "Clear Emergency Lock",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 15.6 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - persistent global emergency physical-control lock"
echo "  - authorized GET/PUT emergency-lock API"
echo "  - required activation reason"
echo "  - actor attribution"
echo "  - audit integration"
echo "  - HTTP 423 rejection before authoritative mutation"
echo "  - operator emergency lock UI"
echo "  - Milestone 15.6 regression tests"
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
echo "  Milestone 15.7 - Physical Control Health / Safety Status Surface"
