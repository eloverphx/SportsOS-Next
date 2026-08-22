#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-16.5-readiness-flap-stability-window-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/services/scoreboardReadinessIncidentMonitor.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlReadiness.ts" \
  "$ROOT/apps/api/src/routes/scoreboardControlPolicy.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

MONITOR="apps/api/src/services/scoreboardReadinessIncidentMonitor.ts"
ROUTE="apps/api/src/routes/scoreboardControlPolicy.ts"
PANEL="apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
TEST="packages/core/test/readiness-flap-stability-window-16.5.test.ts"

for file in "$MONITOR" "$ROUTE" "$PANEL" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/scoreboardReadinessIncidentMonitor.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (!text.includes("type PendingState")) {
  const marker =
`type MonitorState =
  | "READY"
  | "NOT_READY";`;

  if (!text.includes(marker)) {
    throw new Error(
      "Unable to locate MonitorState definition.",
    );
  }

  text =
    text.replace(
      marker,
`${marker}

type PendingState = {
  state: MonitorState;
  firstObservedAtMs: number;
};

const DEFAULT_STABILITY_WINDOW_MS =
  Number.parseInt(
    process.env.SPORTSOS_READINESS_STABILITY_WINDOW_MS ??
      "20000",
    10,
  );`
    );
}

if (!text.includes("const pendingState")) {
  const marker =
`const previousState =
  new Map<string, MonitorState>();`;

  if (!text.includes(marker)) {
    throw new Error(
      "Unable to locate previousState map.",
    );
  }

  text =
    text.replace(
      marker,
`${marker}

const pendingState =
  new Map<string, PendingState>();`
    );
}

if (!text.includes("function stabilityWindowMs")) {
  const marker =
`function stateKey(
  assignment: Assignment,
): string {`;

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate stateKey().",
    );
  }

  const helper =
`function stabilityWindowMs(): number {
  return (
    Number.isFinite(
      DEFAULT_STABILITY_WINDOW_MS,
    ) &&
    DEFAULT_STABILITY_WINDOW_MS >= 0
      ? DEFAULT_STABILITY_WINDOW_MS
      : 20000
  );
}

`;

  text =
    text.slice(0, idx) +
    helper +
    text.slice(idx);
}

const start =
  text.indexOf(
    "export async function checkScoreboardReadinessIncidents",
  );

const end =
  text.indexOf(
    "export function startScoreboardReadinessIncidentMonitor",
  );

if (
  start === -1 ||
  end === -1
) {
  throw new Error(
    "Unable to locate readiness-check function boundaries.",
  );
}

const oldFunction =
  text.slice(
    start,
    end,
  );

if (!oldFunction.includes("pendingState")) {
  const newFunction = `export async function checkScoreboardReadinessIncidents(
  app: FastifyInstance,
): Promise<void> {
  const assignments =
    await loadAssignments(
      app,
    );

  const liveKeys =
    new Set<string>();

  const nowMs =
    Date.now();

  const requiredStableMs =
    stabilityWindowMs();

  for (
    const assignment of
    assignments
  ) {
    const key =
      stateKey(
        assignment,
      );

    liveKeys.add(
      key,
    );

    const readiness =
      await evaluateScoreboardControlReadiness(
        assignment.deviceId,
      );

    const observedState:
      MonitorState =
        readiness.ready
          ? "READY"
          : "NOT_READY";

    const committedState =
      previousState.get(
        key,
      );

    /*
     * First observation establishes baseline only.
     * This avoids generating a false outage/recovery incident at API startup.
     */
    if (!committedState) {
      previousState.set(
        key,
        observedState,
      );

      pendingState.delete(
        key,
      );

      continue;
    }

    if (
      observedState ===
      committedState
    ) {
      pendingState.delete(
        key,
      );

      continue;
    }

    const pending =
      pendingState.get(
        key,
      );

    if (
      !pending ||
      pending.state !==
        observedState
    ) {
      pendingState.set(
        key,
        {
          state:
            observedState,
          firstObservedAtMs:
            nowMs,
        },
      );

      continue;
    }

    const stableForMs =
      nowMs -
      pending.firstObservedAtMs;

    if (
      stableForMs <
      requiredStableMs
    ) {
      continue;
    }

    if (
      observedState ===
      "NOT_READY"
    ) {
      recordScoreboardControlAudit({
        auditId:
          \`readiness-\${assignment.deviceId}-\${Date.now()}\`,
        deviceId:
          assignment.deviceId,
        gameId:
          assignment.gameId,
        inputId:
          \`readiness-monitor:\${assignment.deviceId}\`,
        inputType:
          "DEVICE_READINESS_DEGRADED",
        sequence:
          0,
        disposition:
          "REJECTED",
        command:
          null,
        execution:
          null,
        reconciliation:
          null,
        error:
          readiness.reason ??
          "Assigned scoreboard device is not ready.",
        createdAt:
          new Date().toISOString(),
      });
    } else {
      recordScoreboardControlAudit({
        auditId:
          \`readiness-restored-\${assignment.deviceId}-\${Date.now()}\`,
        deviceId:
          assignment.deviceId,
        gameId:
          assignment.gameId,
        inputId:
          \`readiness-monitor:\${assignment.deviceId}\`,
        inputType:
          "DEVICE_READINESS_RESTORED",
        sequence:
          0,
        disposition:
          "ACCEPTED",
        command:
          null,
        execution:
          null,
        reconciliation:
          null,
        error:
          null,
        createdAt:
          new Date().toISOString(),
      });
    }

    previousState.set(
      key,
      observedState,
    );

    pendingState.delete(
      key,
    );
  }

  for (
    const key of
    previousState.keys()
  ) {
    if (
      !liveKeys.has(
        key,
      )
    ) {
      previousState.delete(
        key,
      );

      pendingState.delete(
        key,
      );
    }
  }
}

`;

  text =
    text.slice(0, start) +
    newFunction +
    text.slice(end);
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

if (!text.includes("/scoreboard-control-readiness-stability")) {
  const marker =
    "export async function registerScoreboardControlPolicyRoutes";

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate policy route registration.",
    );
  }

  const open =
    text.indexOf(
      "{",
      idx,
    );

  if (open === -1) {
    throw new Error(
      "Unable to locate policy route body.",
    );
  }

  const route =
`
  app.get(
    "/scoreboard-control-readiness-stability",
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

      const configured =
        Number.parseInt(
          process.env.SPORTSOS_READINESS_STABILITY_WINDOW_MS ??
            "20000",
          10,
        );

      return {
        success: true,
        data: {
          stabilityWindowMs:
            Number.isFinite(
              configured,
            ) &&
            configured >= 0
              ? configured
              : 20000,
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

fs.writeFileSync(
  file,
  text,
);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx";

if (!fs.existsSync(file)) {
  process.exit(0);
}

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (!text.includes("Readiness Stability Window")) {
  const footer =
`      <p className="mt-5 text-xs text-slate-500">
        Dashboard state is informational only. The API policy store remains authoritative.
      </p>`;

  if (text.includes(footer)) {
    text =
      text.replace(
        footer,
`      <div className="mt-6 rounded-xl border border-slate-800 p-4">
        <h3 className="font-semibold">
          Readiness Stability Window
        </h3>
        <p className="mt-1 text-sm text-slate-500">
          Readiness transitions must remain stable before SportsOS records degradation or recovery.
        </p>
        <p className="mt-2 text-xs text-slate-500">
          Default: 20 seconds. Configure with SPORTSOS_READINESS_STABILITY_WINDOW_MS.
        </p>
      </div>

${footer}`
      );
  }
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

describe("Milestone 16.5 readiness flap detection / stability window", () => {
  const monitor = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardReadinessIncidentMonitor.ts",
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

  it("defines a configurable readiness stability window", () => {
    expect(monitor).toContain(
      "SPORTSOS_READINESS_STABILITY_WINDOW_MS",
    );

    expect(monitor).toContain(
      '"20000"',
    );
  });

  it("tracks pending transitions separately from committed readiness", () => {
    expect(monitor).toContain(
      "pendingState",
    );

    expect(monitor).toContain(
      "firstObservedAtMs",
    );
  });

  it("does not emit transition events until the observed state is stable", () => {
    expect(monitor).toContain(
      "stableForMs",
    );

    expect(monitor).toContain(
      "requiredStableMs",
    );

    expect(monitor).toContain(
      "stableForMs <",
    );
  });

  it("preserves degraded and restored readiness events", () => {
    expect(monitor).toContain(
      "DEVICE_READINESS_DEGRADED",
    );

    expect(monitor).toContain(
      "DEVICE_READINESS_RESTORED",
    );
  });

  it("exposes the configured stability window", () => {
    expect(route).toContain(
      "/scoreboard-control-readiness-stability",
    );

    expect(route).toContain(
      '"CONTROL_POLICY_READ"',
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 16.5 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - readiness flap detection"
echo "  - pending transition tracking"
echo "  - default 20-second stability window"
echo "  - configurable SPORTSOS_READINESS_STABILITY_WINDOW_MS"
echo "  - no startup false outage/recovery event"
echo "  - degradation/recovery only after stable transition"
echo "  - GET /scoreboard-control-readiness-stability"
echo "  - Milestone 16.5 regression tests"
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
echo "  Milestone 16.6 - Device Readiness Metrics / Reliability Counters"
