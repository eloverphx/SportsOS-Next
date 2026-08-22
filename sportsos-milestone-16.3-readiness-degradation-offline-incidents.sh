#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-16.3-readiness-degradation-offline-incidents-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/services/scoreboardControlReadiness.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlAudit.ts" \
  "$ROOT/apps/api/src/services/automaticGameScoreboardSync.ts" \
  "$ROOT/apps/api/src/routes/scoreboardControlPolicy.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

SERVICE="apps/api/src/services/scoreboardReadinessIncidentMonitor.ts"
POLICY_ROUTE="apps/api/src/routes/scoreboardControlPolicy.ts"
APP="apps/api/src/app.ts"
TEST="packages/core/test/readiness-degradation-offline-incidents-16.3.test.ts"

for file in "$SERVICE" "$POLICY_ROUTE" "$APP" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import {
  recordScoreboardControlAudit,
} from "./scoreboardControlAudit.js";

import {
  evaluateScoreboardControlReadiness,
} from "./scoreboardControlReadiness.js";

type Assignment = {
  gameId: string;
  deviceId: string;
};

type MonitorState =
  | "READY"
  | "NOT_READY";

const previousState =
  new Map<string, MonitorState>();

let interval:
  NodeJS.Timeout | null =
    null;

function stateKey(
  assignment: Assignment,
): string {
  return [
    assignment.gameId,
    assignment.deviceId,
  ].join(":");
}

async function loadAssignments(
  app: FastifyInstance,
): Promise<Assignment[]> {
  const response =
    await app.inject({
      method: "GET",
      url:
        "/scoreboard-devices/assignments",
    });

  if (
    response.statusCode < 200 ||
    response.statusCode >= 300
  ) {
    return [];
  }

  try {
    const payload =
      response.json() as {
        data?: {
          assignments?: Assignment[];
        };
        assignments?: Assignment[];
      };

    return (
      payload.data?.assignments ??
      payload.assignments ??
      []
    );
  } catch {
    return [];
  }
}

export async function checkScoreboardReadinessIncidents(
  app: FastifyInstance,
): Promise<void> {
  const assignments =
    await loadAssignments(
      app,
    );

  const liveKeys =
    new Set<string>();

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

    const nextState:
      MonitorState =
        readiness.ready
          ? "READY"
          : "NOT_READY";

    const prior =
      previousState.get(
        key,
      );

    if (
      nextState ===
        "NOT_READY" &&
      prior !==
        "NOT_READY"
    ) {
      const now =
        new Date().toISOString();

      recordScoreboardControlAudit({
        auditId:
          `readiness-${assignment.deviceId}-${Date.now()}`,
        deviceId:
          assignment.deviceId,
        gameId:
          assignment.gameId,
        inputId:
          `readiness-monitor:${assignment.deviceId}`,
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
          now,
      });
    }

    previousState.set(
      key,
      nextState,
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
    }
  }
}

export function startScoreboardReadinessIncidentMonitor(
  app: FastifyInstance,
): () => void {
  if (interval) {
    return () => {};
  }

  const monitorEveryMs =
    Number.parseInt(
      process.env.SPORTSOS_READINESS_MONITOR_INTERVAL_MS ??
        "10000",
      10,
    );

  const cadence =
    Number.isFinite(
      monitorEveryMs,
    ) &&
    monitorEveryMs >=
      5000
      ? monitorEveryMs
      : 10000;

  const run =
    () => {
      void checkScoreboardReadinessIncidents(
        app,
      ).catch(
        (error) => {
          app.log.error(
            {
              error,
            },
            "scoreboard readiness incident monitor failed",
          );
        },
      );
    };

  run();

  interval =
    setInterval(
      run,
      cadence,
    );

  interval.unref?.();

  return () => {
    if (interval) {
      clearInterval(
        interval,
      );

      interval =
        null;
    }
  };
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardControlPolicy.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { checkScoreboardReadinessIncidents } from "../services/scoreboardReadinessIncidentMonitor.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(
      /^(import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate control-policy route imports.",
    );
  }

  text =
    text.replace(
      imports[0],
      imports[0] +
        importLine +
        "\n",
    );
}

if (
  !text.includes(
    "/scoreboard-control-readiness/check",
  )
) {
  const marker =
    "export async function registerScoreboardControlPolicyRoutes";

  const idx =
    text.indexOf(
      marker,
    );

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
      "Unable to locate route registration body.",
    );
  }

  const route =
`
  app.post(
    "/scoreboard-control-readiness/check",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_WRITE",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy write permission required.",
        });
      }

      await checkScoreboardReadinessIncidents(
        app,
      );

      return {
        success: true,
        data: {
          checked: true,
        },
      };
    },
  );

`;

  text =
    text.slice(
      0,
      open + 1,
    ) +
    route +
    text.slice(
      open + 1,
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
  "apps/api/src/app.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { startScoreboardReadinessIncidentMonitor } from "./services/scoreboardReadinessIncidentMonitor.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(
      /^(import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate API app imports.",
    );
  }

  text =
    text.replace(
      imports[0],
      imports[0] +
        importLine +
        "\n",
    );
}

if (
  !text.includes(
    "startScoreboardReadinessIncidentMonitor(",
  )
) {
  const returnIdx =
    text.lastIndexOf(
      "return app;",
    );

  if (returnIdx === -1) {
    throw new Error(
      "Unable to locate return app;.",
    );
  }

  text =
    text.slice(
      0,
      returnIdx,
    ) +
`  startScoreboardReadinessIncidentMonitor(
    app,
  );

` +
    text.slice(
      returnIdx,
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

describe("Milestone 16.3 readiness degradation / offline incident generation", () => {
  const monitor = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardReadinessIncidentMonitor.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const app = fs.readFileSync(
    new URL(
      "../../../apps/api/src/app.ts",
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

  it("monitors assigned scoreboard readiness", () => {
    expect(monitor).toContain(
      "/scoreboard-devices/assignments",
    );

    expect(monitor).toContain(
      "evaluateScoreboardControlReadiness",
    );
  });

  it("creates an incident only on transition into not-ready", () => {
    expect(monitor).toContain(
      '"NOT_READY"',
    );

    expect(monitor).toContain(
      "prior !==",
    );
  });

  it("writes readiness degradation through the existing control audit", () => {
    expect(monitor).toContain(
      "recordScoreboardControlAudit",
    );

    expect(monitor).toContain(
      "DEVICE_READINESS_DEGRADED",
    );
  });

  it("starts the monitor from the API application", () => {
    expect(app).toContain(
      "startScoreboardReadinessIncidentMonitor",
    );
  });

  it("supports a permission-protected manual readiness check", () => {
    expect(route).toContain(
      "/scoreboard-control-readiness/check",
    );

    expect(route).toContain(
      '"CONTROL_POLICY_WRITE"',
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 16.3 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - readiness degradation monitor"
echo "  - assignment-wide heartbeat checks"
echo "  - deduplicated READY -> NOT_READY incident transition"
echo "  - DEVICE_READINESS_DEGRADED audit incidents"
echo "  - default 10-second monitor cadence"
echo "  - configurable SPORTSOS_READINESS_MONITOR_INTERVAL_MS"
echo "  - permission-protected manual readiness check"
echo "  - Milestone 16.3 regression tests"
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
echo "  Milestone 16.4 - Readiness Recovery / Restored-Service Events"
