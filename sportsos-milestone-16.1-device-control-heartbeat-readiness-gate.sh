#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-16.1-device-control-heartbeat-readiness-gate-${STAMP}"

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
  "$ROOT/apps/api/src/modules/scoreboard-devices/repository.ts" \
  "$ROOT/apps/api/src/routes/scoreboardDevices.ts" \
  "$ROOT/apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

SERVICE="apps/api/src/services/scoreboardControlReadiness.ts"
ROUTE="apps/api/src/routes/scoreboardControlInputs.ts"
POLICY_ROUTE="apps/api/src/routes/scoreboardControlPolicy.ts"
PANEL="apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
TEST="packages/core/test/device-control-heartbeat-readiness-gate-16.1.test.ts"

for file in "$SERVICE" "$ROUTE" "$POLICY_ROUTE" "$PANEL" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import {
  findScoreboardDeviceById,
} from "../modules/scoreboard-devices/repository.js";

export type ScoreboardControlReadinessDecision = {
  ready: boolean;
  deviceId: string;
  lastHeartbeatAt: string | null;
  heartbeatAgeMs: number | null;
  thresholdMs: number;
  reason: string | null;
};

const DEFAULT_THRESHOLD_MS =
  Number.parseInt(
    process.env.SPORTSOS_CONTROL_HEARTBEAT_MAX_AGE_MS ??
      "30000",
    10,
  );

function heartbeatTimestamp(
  device: unknown,
): string | null {
  if (
    typeof device !== "object" ||
    device === null
  ) {
    return null;
  }

  const record =
    device as Record<string, unknown>;

  const candidates = [
    record.lastHeartbeatAt,
    record.lastSeenAt,
    record.heartbeatAt,
    record.updatedAt,
  ];

  for (const candidate of candidates) {
    if (
      typeof candidate === "string" &&
      candidate.trim()
    ) {
      return candidate.trim();
    }
  }

  return null;
}

export async function evaluateScoreboardControlReadiness(
  deviceId: string,
): Promise<ScoreboardControlReadinessDecision> {
  const device =
    await findScoreboardDeviceById(
      deviceId,
    );

  const thresholdMs =
    Number.isFinite(
      DEFAULT_THRESHOLD_MS,
    ) &&
    DEFAULT_THRESHOLD_MS > 0
      ? DEFAULT_THRESHOLD_MS
      : 30000;

  if (!device) {
    return {
      ready: false,
      deviceId,
      lastHeartbeatAt: null,
      heartbeatAgeMs: null,
      thresholdMs,
      reason:
        "Scoreboard device record was not found.",
    };
  }

  const lastHeartbeatAt =
    heartbeatTimestamp(
      device,
    );

  if (!lastHeartbeatAt) {
    return {
      ready: false,
      deviceId,
      lastHeartbeatAt: null,
      heartbeatAgeMs: null,
      thresholdMs,
      reason:
        "Scoreboard device heartbeat is unavailable.",
    };
  }

  const heartbeatMs =
    Date.parse(
      lastHeartbeatAt,
    );

  if (
    !Number.isFinite(
      heartbeatMs,
    )
  ) {
    return {
      ready: false,
      deviceId,
      lastHeartbeatAt,
      heartbeatAgeMs: null,
      thresholdMs,
      reason:
        "Scoreboard device heartbeat timestamp is invalid.",
    };
  }

  const heartbeatAgeMs =
    Math.max(
      0,
      Date.now() -
        heartbeatMs,
    );

  if (
    heartbeatAgeMs >
    thresholdMs
  ) {
    return {
      ready: false,
      deviceId,
      lastHeartbeatAt,
      heartbeatAgeMs,
      thresholdMs,
      reason:
        `Scoreboard device heartbeat is stale (${heartbeatAgeMs}ms old).`,
    };
  }

  return {
    ready: true,
    deviceId,
    lastHeartbeatAt,
    heartbeatAgeMs,
    thresholdMs,
    reason: null,
  };
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardControlInputs.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { evaluateScoreboardControlReadiness } from "../services/scoreboardControlReadiness.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate scoreboard control-input imports.",
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
    "evaluateScoreboardControlReadiness(",
  )
) {
  const anchor =
    "      const emergencyPhysicalControlLock =";

  const idx =
    text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate emergency lock gate.",
    );
  }

  const block =
`      const readinessDecision =
        await evaluateScoreboardControlReadiness(
          body.deviceId,
        );

      if (!readinessDecision.ready) {
        recordScoreboardControlAudit({
          auditId:
            body.inputId,
          deviceId:
            body.deviceId,
          gameId:
            result.authoritativeGameId,
          inputId:
            body.inputId,
          inputType:
            body.type,
          sequence:
            body.sequence,
          disposition:
            "REJECTED",
          command:
            "command" in result
              ? result.command
              : null,
          execution:
            null,
          reconciliation:
            null,
          error:
            readinessDecision.reason ??
            "Scoreboard device is not ready for physical control.",
          createdAt:
            new Date().toISOString(),
        });

        return reply.code(409).send({
          success: false,
          error:
            readinessDecision.reason ??
            "Scoreboard device is not ready for physical control.",
          data: {
            acknowledgement: {
              ...result,
              disposition:
                "REJECTED",
              reason:
                readinessDecision.reason ??
                "Scoreboard device is not ready for physical control.",
            },
            readiness:
              readinessDecision,
          },
        });
      }

`;

  text =
    text.slice(0, idx) +
    block +
    text.slice(idx);
}

const readinessIndex =
  text.indexOf(
    "evaluateScoreboardControlReadiness(",
  );

const executionIndex =
  text.indexOf(
    "executePhysicalScoreboardControl(",
  );

if (
  readinessIndex === -1 ||
  executionIndex === -1 ||
  readinessIndex >
    executionIndex
) {
  throw new Error(
    "Readiness gate is not enforced before authoritative execution.",
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
  "apps/api/src/routes/scoreboardControlPolicy.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { evaluateScoreboardControlReadiness } from "../services/scoreboardControlReadiness.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

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
    "/scoreboard-control-readiness/:deviceId",
  )
) {
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
      "Unable to locate route registration body.",
    );
  }

  const route =
`
  app.get(
    "/scoreboard-control-readiness/:deviceId",
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

      const params =
        request.params as {
          deviceId?: string;
        };

      const deviceId =
        params.deviceId?.trim();

      if (!deviceId) {
        return reply.code(400).send({
          success: false,
          error:
            "Scoreboard device ID is required.",
        });
      }

      return {
        success: true,
        data: {
          readiness:
            await evaluateScoreboardControlReadiness(
              deviceId,
            ),
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
  "apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (!text.includes("Control Readiness Probe")) {
  const footer =
`      <p className="mt-5 text-xs text-slate-500">
        Dashboard state is informational only. The API policy store remains authoritative.
      </p>`;

  if (!text.includes(footer)) {
    throw new Error(
      "Unable to locate physical-control policy footer.",
    );
  }

  text =
    text.replace(
      footer,
`      <div className="mt-6 rounded-xl border border-slate-800 p-4">
        <h3 className="font-semibold">
          Control Readiness Probe
        </h3>
        <p className="mt-1 text-sm text-slate-500">
          Physical mutations are accepted only while the server sees a recent scoreboard heartbeat.
        </p>
        <p className="mt-2 text-xs text-slate-500">
          Default readiness window: 30 seconds. Override with SPORTSOS_CONTROL_HEARTBEAT_MAX_AGE_MS.
        </p>
      </div>

${footer}`
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

describe("Milestone 16.1 device control heartbeat / readiness gate", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlReadiness.ts",
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

  const policyRoute = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlPolicy.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("uses scoreboard device heartbeat state as readiness authority", () => {
    expect(service).toContain(
      "findScoreboardDeviceById",
    );

    expect(service).toContain(
      "lastHeartbeatAt",
    );
  });

  it("defaults heartbeat readiness to 30 seconds", () => {
    expect(service).toContain(
      '"30000"',
    );

    expect(service).toContain(
      "SPORTSOS_CONTROL_HEARTBEAT_MAX_AGE_MS",
    );
  });

  it("rejects stale or missing heartbeat before physical mutation", () => {
    const readinessIndex =
      inputRoute.indexOf(
        "evaluateScoreboardControlReadiness",
      );

    const executionIndex =
      inputRoute.indexOf(
        "executePhysicalScoreboardControl",
      );

    expect(readinessIndex).toBeGreaterThan(
      -1,
    );

    expect(executionIndex).toBeGreaterThan(
      readinessIndex,
    );

    expect(inputRoute).toContain(
      "readinessDecision.ready",
    );
  });

  it("audits readiness rejections", () => {
    expect(inputRoute).toContain(
      "recordScoreboardControlAudit",
    );

    expect(inputRoute).toContain(
      "readinessDecision.reason",
    );
  });

  it("exposes an authorized readiness endpoint", () => {
    expect(policyRoute).toContain(
      "/scoreboard-control-readiness/:deviceId",
    );

    expect(policyRoute).toContain(
      '"CONTROL_POLICY_READ"',
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 16.1 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - device heartbeat readiness service"
echo "  - default 30-second freshness window"
echo "  - configurable SPORTSOS_CONTROL_HEARTBEAT_MAX_AGE_MS"
echo "  - stale/missing heartbeat rejection before mutation"
echo "  - readiness rejection audit"
echo "  - GET /scoreboard-control-readiness/:deviceId"
echo "  - operator readiness documentation surface"
echo "  - Milestone 16.1 regression tests"
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
echo "  Milestone 16.2 - Device Readiness Status UI"
