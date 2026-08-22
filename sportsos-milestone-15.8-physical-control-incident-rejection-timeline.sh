#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-15.8-physical-control-incident-rejection-timeline-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/routes/scoreboardControlInputs.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlAudit.ts" \
  "$ROOT/apps/api/src/routes/scoreboardControlPolicy.ts" \
  "$ROOT/apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

AUDIT="apps/api/src/services/scoreboardControlAudit.ts"
ROUTE="apps/api/src/routes/scoreboardControlPolicy.ts"
PANEL="apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
TEST="packages/core/test/physical-control-incident-rejection-timeline-15.8.test.ts"

for file in "$AUDIT" "$ROUTE" "$PANEL" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");
const file =
  "apps/api/src/services/scoreboardControlAudit.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("listScoreboardControlIncidents")) {
  text += `

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
  return listScoreboardControlAudit(
    Math.max(
      100,
      Math.min(
        limit * 5,
        1000,
      ),
    ),
  )
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
`;
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file =
  "apps/api/src/routes/scoreboardControlPolicy.ts";
let text = fs.readFileSync(file, "utf8");

const importLine =
  'import { listScoreboardControlIncidents } from "../services/scoreboardControlAudit.js";';

if (!text.includes(importLine)) {
  const imports = text.match(/^(import[\s\S]*?;\n)+/);
  if (!imports) throw new Error("Unable to locate route imports.");
  text = text.replace(imports[0], imports[0] + importLine + "\n");
}

if (!text.includes("/scoreboard-control-incidents")) {
  const marker =
    "export async function registerScoreboardControlPolicyRoutes";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate route registration.");
  const open = text.indexOf("{", idx);
  if (open === -1) throw new Error("Unable to locate route body.");

  const route = `
  app.get(
    "/scoreboard-control-incidents",
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

      const parsed =
        query.limit
          ? Number.parseInt(
              query.limit,
              10,
            )
          : 50;

      const limit =
        Number.isFinite(parsed)
          ? parsed
          : 50;

      return {
        success: true,
        data: {
          incidents:
            listScoreboardControlIncidents(
              limit,
            ),
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

if (!text.includes("type PhysicalControlIncident")) {
  const marker = "type PhysicalControlHealth";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate health type.");

  text =
    text.slice(0, idx) +
`type PhysicalControlIncident = {
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

` +
    text.slice(idx);
}

if (!text.includes("const [controlIncidents")) {
  const marker = "const [controlHealth, setControlHealth]";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate health state.");

  text =
    text.slice(0, idx) +
`const [controlIncidents, setControlIncidents] =
    useState<PhysicalControlIncident[]>([]);

  ` +
    text.slice(idx);
}

if (!text.includes("/scoreboard-control-incidents")) {
  text = text.replace(
`        fetch(
          \`\${API_BASE}/scoreboard-control-health\`,
          { cache: "no-store" },
        ),
      ]);`,
`        fetch(
          \`\${API_BASE}/scoreboard-control-health\`,
          { cache: "no-store" },
        ),
        fetch(
          \`\${API_BASE}/scoreboard-control-incidents?limit=50\`,
          { cache: "no-store" },
        ),
      ]);`
  );

  text = text.replace(
`        healthResponse,
      ] = await Promise.all([`,
`        healthResponse,
        incidentsResponse,
      ] = await Promise.all([`
  );

  const anchor =
`      if (healthResponse.ok) {
        const healthJson =
          await healthResponse.json();

        setControlHealth(
          healthJson?.data?.health ??
          null,
        );
      }`;

  if (!text.includes(anchor)) {
    throw new Error("Unable to locate health response block.");
  }

  text = text.replace(
    anchor,
`${anchor}

      if (incidentsResponse.ok) {
        const incidentsJson =
          await incidentsResponse.json();

        setControlIncidents(
          incidentsJson?.data?.incidents ??
          [],
        );
      }`
  );
}

if (!text.includes("Physical Control Incident Timeline")) {
  const marker =
    '      <div className="mt-6">\n        <h3 className="font-semibold">\n          Recent Policy Changes';
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate policy audit section.");

  const block = `      <div className="mt-6">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div>
            <h3 className="font-semibold">
              Physical Control Incident Timeline
            </h3>
            <p className="mt-1 text-sm text-slate-500">
              Rejected or failed physical scoreboard inputs, newest first.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-2 py-1 text-xs">
            {controlIncidents.length} shown
          </span>
        </div>

        {controlIncidents.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">
            No physical-control incidents recorded.
          </p>
        ) : (
          <div className="mt-3 space-y-2">
            {controlIncidents.map(
              (incident) => (
                <div
                  key={incident.auditId}
                  className="rounded-lg border border-slate-800 p-3 text-sm"
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-semibold">
                        {incident.disposition}
                      </span>
                      <span className="rounded border border-slate-800 px-2 py-0.5 font-mono text-xs">
                        {incident.inputType}
                      </span>
                    </div>

                    <span className="text-xs text-slate-500">
                      {incident.createdAt}
                    </span>
                  </div>

                  <div className="mt-2 grid gap-1 text-slate-400 sm:grid-cols-2">
                    <div>
                      Device:{" "}
                      <span className="font-mono text-xs">
                        {incident.deviceId}
                      </span>
                    </div>
                    <div>
                      Game:{" "}
                      <span className="font-mono text-xs">
                        {incident.gameId ?? "unassigned"}
                      </span>
                    </div>
                    <div>
                      Sequence: {incident.sequence}
                    </div>
                    <div>
                      Input ID:{" "}
                      <span className="font-mono text-xs">
                        {incident.inputId}
                      </span>
                    </div>
                  </div>

                  {incident.error && (
                    <div className="mt-2 rounded border border-slate-800 bg-slate-950/50 p-2 text-slate-300">
                      {incident.error}
                    </div>
                  )}
                </div>
              ),
            )}
          </div>
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

describe("Milestone 15.8 physical control incident / rejection timeline", () => {
  const audit = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlAudit.ts",
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

  it("derives incidents from rejected or errored control audit records", () => {
    expect(audit).toContain(
      "listScoreboardControlIncidents",
    );
    expect(audit).toContain(
      'record.disposition === "REJECTED"',
    );
    expect(audit).toContain(
      "Boolean(record.error)",
    );
  });

  it("exposes an authorized incident endpoint", () => {
    expect(route).toContain(
      "/scoreboard-control-incidents",
    );
    expect(route).toContain(
      '"CONTROL_POLICY_READ"',
    );
  });

  it("preserves device, game, input, sequence, error, and timestamp context", () => {
    for (const field of [
      "deviceId",
      "gameId",
      "inputId",
      "inputType",
      "sequence",
      "error",
      "createdAt",
    ]) {
      expect(audit).toContain(field);
    }
  });

  it("renders an operator incident timeline", () => {
    expect(panel).toContain(
      "Physical Control Incident Timeline",
    );
    expect(panel).toContain(
      "No physical-control incidents recorded.",
    );
    expect(panel).toContain(
      "incident.deviceId",
    );
    expect(panel).toContain(
      "incident.error",
    );
  });

  it("keeps the server audit as timeline authority", () => {
    expect(audit).not.toContain("localStorage");
    expect(audit).not.toContain("window.");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 15.8 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - incident projection from authoritative physical-control audit"
echo "  - rejected/failed input filtering"
echo "  - device/game/input/sequence/error/timestamp context"
echo "  - GET /scoreboard-control-incidents"
echo "  - permission-protected incident access"
echo "  - operator Physical Control Incident Timeline"
echo "  - Milestone 15.8 regression tests"
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
echo "  Milestone 15.9 - Incident Acknowledgement / Resolution Workflow"
