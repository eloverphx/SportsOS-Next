#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-15.7-physical-control-health-safety-status-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/routes/scoreboardControlPolicy.ts" \
  "$ROOT/apps/api/src/services/scoreboardEmergencyControlLock.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlPolicy.ts" \
  "$ROOT/apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

SERVICE="apps/api/src/services/scoreboardPhysicalControlHealth.ts"
ROUTE="apps/api/src/routes/scoreboardControlPolicy.ts"
PANEL="apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
TEST="packages/core/test/physical-control-health-safety-status-15.7.test.ts"

for file in "$SERVICE" "$ROUTE" "$PANEL" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import {
  getEmergencyPhysicalControlLock,
} from "./scoreboardEmergencyControlLock.js";

import {
  listScoreboardPhysicalControlPolicies,
} from "./scoreboardControlPolicy.js";

export type PhysicalControlSafetyLevel =
  | "SAFE"
  | "RESTRICTED"
  | "EMERGENCY_LOCKED";

export type PhysicalControlHealthStatus = {
  level: PhysicalControlSafetyLevel;
  acceptingPhysicalControls: boolean;
  emergencyLockActive: boolean;
  activePolicyCount: number;
  lockedPolicyCount: number;
  generatedAt: string;
  summary: string;
};

export function getPhysicalControlHealthStatus():
  PhysicalControlHealthStatus {
  const emergencyLock =
    getEmergencyPhysicalControlLock();

  const policies =
    listScoreboardPhysicalControlPolicies();

  const lockedPolicies =
    policies.filter(
      (policy) =>
        policy.mode === "LOCKED",
    );

  if (emergencyLock.active) {
    return {
      level: "EMERGENCY_LOCKED",
      acceptingPhysicalControls: false,
      emergencyLockActive: true,
      activePolicyCount: policies.length,
      lockedPolicyCount: lockedPolicies.length,
      generatedAt: new Date().toISOString(),
      summary:
        emergencyLock.reason ??
        "Emergency physical-control lock is active.",
    };
  }

  if (lockedPolicies.length > 0) {
    return {
      level: "RESTRICTED",
      acceptingPhysicalControls: true,
      emergencyLockActive: false,
      activePolicyCount: policies.length,
      lockedPolicyCount: lockedPolicies.length,
      generatedAt: new Date().toISOString(),
      summary:
        `${lockedPolicies.length} physical-control policy scope(s) are locked.`,
    };
  }

  return {
    level: "SAFE",
    acceptingPhysicalControls: true,
    emergencyLockActive: false,
    activePolicyCount: policies.length,
    lockedPolicyCount: 0,
    generatedAt: new Date().toISOString(),
    summary:
      "Physical controls are globally available subject to device, assignment, lifecycle, and sequence validation.",
  };
}
EOF

node <<'NODE'
const fs = require("fs");
const file =
  "apps/api/src/routes/scoreboardControlPolicy.ts";
let text = fs.readFileSync(file, "utf8");

const importLine =
  'import { getPhysicalControlHealthStatus } from "../services/scoreboardPhysicalControlHealth.js";';

if (!text.includes(importLine)) {
  const imports = text.match(/^(import[\s\S]*?;\n)+/);
  if (!imports) throw new Error("Unable to locate route imports.");
  text = text.replace(imports[0], imports[0] + importLine + "\n");
}

if (!text.includes("/scoreboard-control-health")) {
  const marker =
    "export async function registerScoreboardControlPolicyRoutes";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate route registration.");
  const open = text.indexOf("{", idx);
  if (open === -1) throw new Error("Unable to locate registration body.");

  const route = `
  app.get(
    "/scoreboard-control-health",
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

      return {
        success: true,
        data: {
          health:
            getPhysicalControlHealthStatus(),
        },
      };
    },
  );

`;

  text =
    text.slice(0, open + 1) +
    route +
    text.slice(open + 1);
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file =
  "apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("type PhysicalControlHealth")) {
  const marker = "type EmergencyLock";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate EmergencyLock type.");

  text =
    text.slice(0, idx) +
`type PhysicalControlHealth = {
  level:
    | "SAFE"
    | "RESTRICTED"
    | "EMERGENCY_LOCKED";
  acceptingPhysicalControls: boolean;
  emergencyLockActive: boolean;
  activePolicyCount: number;
  lockedPolicyCount: number;
  generatedAt: string;
  summary: string;
};

` +
    text.slice(idx);
}

if (!text.includes("const [controlHealth")) {
  const marker = "const [emergencyLock, setEmergencyLock]";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate emergency lock state.");

  text =
    text.slice(0, idx) +
`const [controlHealth, setControlHealth] =
    useState<PhysicalControlHealth | null>(null);

  ` +
    text.slice(idx);
}

if (!text.includes("/scoreboard-control-health")) {
  text = text.replace(
`        fetch(
          \`\${API_BASE}/scoreboard-control-emergency-lock\`,
          { cache: "no-store" },
        ),
      ]);`,
`        fetch(
          \`\${API_BASE}/scoreboard-control-emergency-lock\`,
          { cache: "no-store" },
        ),
        fetch(
          \`\${API_BASE}/scoreboard-control-health\`,
          { cache: "no-store" },
        ),
      ]);`
  );

  text = text.replace(
`        emergencyResponse,
      ] = await Promise.all([`,
`        emergencyResponse,
        healthResponse,
      ] = await Promise.all([`
  );

  const anchor =
`      if (emergencyResponse.ok) {
        const emergencyJson =
          await emergencyResponse.json();

        setEmergencyLock(
          emergencyJson?.data?.emergencyLock ??
          null,
        );
      }`;

  if (!text.includes(anchor)) {
    throw new Error("Unable to locate emergency response block.");
  }

  text = text.replace(
    anchor,
`${anchor}

      if (healthResponse.ok) {
        const healthJson =
          await healthResponse.json();

        setControlHealth(
          healthJson?.data?.health ??
          null,
        );
      }`
  );
}

if (!text.includes("Physical Control Safety Status")) {
  const marker =
    '      <div className="mt-5 rounded-xl border border-amber-800/60 bg-amber-950/20 p-4">';
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate emergency lock panel.");

  const block = `      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="font-semibold">
              Physical Control Safety Status
            </h3>
            <p className="mt-1 text-sm text-slate-400">
              Server-authoritative status for physical scoreboard controls.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-3 py-1 text-sm font-semibold">
            {controlHealth?.level ?? "UNKNOWN"}
          </span>
        </div>

        <div className="mt-4 grid gap-3 sm:grid-cols-3">
          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs text-slate-500">
              Global Input
            </div>
            <div className="mt-1 font-medium">
              {controlHealth
                ? controlHealth.acceptingPhysicalControls
                  ? "AVAILABLE"
                  : "BLOCKED"
                : "UNKNOWN"}
            </div>
          </div>

          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs text-slate-500">
              Locked Scopes
            </div>
            <div className="mt-1 font-medium">
              {controlHealth?.lockedPolicyCount ?? "—"}
            </div>
          </div>

          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs text-slate-500">
              Emergency Lock
            </div>
            <div className="mt-1 font-medium">
              {controlHealth
                ? controlHealth.emergencyLockActive
                  ? "ACTIVE"
                  : "CLEAR"
                : "UNKNOWN"}
            </div>
          </div>
        </div>

        {controlHealth?.summary && (
          <p className="mt-3 text-sm text-slate-400">
            {controlHealth.summary}
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

describe("Milestone 15.7 physical control health / safety status", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardPhysicalControlHealth.ts",
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

  it("defines safe, restricted, and emergency locked states", () => {
    expect(service).toContain('"SAFE"');
    expect(service).toContain('"RESTRICTED"');
    expect(service).toContain('"EMERGENCY_LOCKED"');
  });

  it("derives health from authoritative policy and emergency lock services", () => {
    expect(service).toContain("getEmergencyPhysicalControlLock");
    expect(service).toContain("listScoreboardPhysicalControlPolicies");
  });

  it("exposes an authorized health endpoint", () => {
    expect(route).toContain("/scoreboard-control-health");
    expect(route).toContain('"CONTROL_POLICY_READ"');
  });

  it("surfaces health in the operator UI", () => {
    expect(panel).toContain("Physical Control Safety Status");
    expect(panel).toContain("Locked Scopes");
    expect(panel).toContain("Emergency Lock");
    expect(panel).toContain("Global Input");
  });

  it("does not use localStorage as safety authority", () => {
    expect(service).not.toContain("localStorage");
    expect(service).not.toContain("window.");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 15.7 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - server-authoritative physical-control health aggregation"
echo "  - SAFE / RESTRICTED / EMERGENCY_LOCKED safety levels"
echo "  - global input availability status"
echo "  - locked policy scope count"
echo "  - emergency-lock visibility"
echo "  - GET /scoreboard-control-health"
echo "  - operator safety-status surface"
echo "  - Milestone 15.7 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 15.8 - Physical Control Incident / Rejection Timeline"
