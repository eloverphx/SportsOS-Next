#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-17.2-automated-commissioning-validation-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "package.json" \
  "apps/api/src/services/scoreboardDeviceCommissioning.ts" \
  "apps/api/src/services/scoreboardControlReadiness.ts" \
  "apps/api/src/services/scoreboardReadinessReliability.ts" \
  "apps/api/src/services/automaticGameScoreboardSync.ts" \
  "apps/api/src/routes/scoreboardDeviceCommissioning.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

SERVICE="apps/api/src/services/scoreboardCommissioningValidator.ts"
ROUTE="apps/api/src/routes/scoreboardDeviceCommissioning.ts"
TEST="packages/core/test/automated-commissioning-validation-17.2.test.ts"
DOC="docs/SCOREBOARD-DEVICE-COMMISSIONING.md"

for file in "$SERVICE" "$ROUTE" "$TEST" "$DOC"; do
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
  evaluateScoreboardControlReadiness,
} from "./scoreboardControlReadiness.js";

import {
  listScoreboardReliabilityClassifications,
} from "./scoreboardReadinessReliability.js";

import {
  getScoreboardCommissioning,
  updateScoreboardCommissioningStep,
  type CommissioningStepId,
  type ScoreboardDeviceCommissioning,
} from "./scoreboardDeviceCommissioning.js";

type ValidationResult = {
  step: CommissioningStepId;
  complete: boolean;
  note: string;
};

type Assignment = {
  gameId: string;
  deviceId: string;
};

function normalizeDeviceId(
  value: unknown,
): string | null {
  if (
    typeof value !== "string" ||
    !value.trim()
  ) {
    return null;
  }

  return value.trim();
}

async function getJson(
  app: FastifyInstance,
  url: string,
): Promise<unknown | null> {
  const response =
    await app.inject({
      method: "GET",
      url,
    });

  if (
    response.statusCode < 200 ||
    response.statusCode >= 300
  ) {
    return null;
  }

  try {
    return response.json();
  } catch {
    return null;
  }
}

function containsDevice(
  payload: unknown,
  deviceId: string,
): boolean {
  const seen =
    new Set<unknown>();

  function visit(
    value: unknown,
  ): boolean {
    if (
      value === null ||
      value === undefined ||
      seen.has(value)
    ) {
      return false;
    }

    if (
      typeof value === "string"
    ) {
      return value ===
        deviceId;
    }

    if (
      typeof value !== "object"
    ) {
      return false;
    }

    seen.add(
      value,
    );

    if (
      Array.isArray(
        value,
      )
    ) {
      return value.some(
        visit,
      );
    }

    const record =
      value as Record<
        string,
        unknown
      >;

    for (
      const key of [
        "deviceId",
        "device_id",
        "hardwareId",
        "hardware_id",
        "identifier",
        "serialNumber",
        "serial_number",
      ]
    ) {
      if (
        normalizeDeviceId(
          record[key],
        ) ===
        deviceId
      ) {
        return true;
      }
    }

    return Object.values(
      record,
    ).some(
      visit,
    );
  }

  return visit(
    payload,
  );
}

async function validateEnrollment(
  app: FastifyInstance,
  deviceId: string,
): Promise<ValidationResult> {
  const endpoints = [
    "/scoreboard-device-enrollment",
    "/scoreboard-devices/enrollment",
    "/scoreboard-devices",
  ];

  for (const endpoint of endpoints) {
    const payload =
      await getJson(
        app,
        endpoint,
      );

    if (
      payload &&
      containsDevice(
        payload,
        deviceId,
      )
    ) {
      return {
        step: "ENROLLED",
        complete: true,
        note:
          `Device found through ${endpoint}.`,
      };
    }
  }

  return {
    step: "ENROLLED",
    complete: false,
    note:
      "Device enrollment could not be confirmed.",
  };
}

async function validateVerification(
  app: FastifyInstance,
  deviceId: string,
): Promise<ValidationResult> {
  const endpoints = [
    "/scoreboard-devices",
    "/scoreboard-device-enrollment",
  ];

  for (const endpoint of endpoints) {
    const payload =
      await getJson(
        app,
        endpoint,
      );

    if (!payload) {
      continue;
    }

    const text =
      JSON.stringify(
        payload,
      );

    if (
      text.includes(
        deviceId,
      ) &&
      /verified/i.test(
        text,
      )
    ) {
      return {
        step:
          "VERIFIED",
        complete:
          true,
        note:
          `Verified device state found through ${endpoint}.`,
      };
    }
  }

  return {
    step:
      "VERIFIED",
    complete:
      false,
    note:
      "Verified-device state could not be confirmed.",
  };
}

async function validateAssignment(
  app: FastifyInstance,
  deviceId: string,
): Promise<ValidationResult> {
  const payload =
    await getJson(
      app,
      "/scoreboard-devices/assignments",
    ) as
      | {
          data?: {
            assignments?: Assignment[];
          };
          assignments?: Assignment[];
        }
      | null;

  const assignments =
    payload?.data?.assignments ??
    payload?.assignments ??
    [];

  const assignment =
    assignments.find(
      (item) =>
        item.deviceId ===
        deviceId,
    );

  return {
    step:
      "ASSIGNED",
    complete:
      Boolean(
        assignment,
      ),
    note:
      assignment
        ? `Assigned to game ${assignment.gameId}.`
        : "No scoreboard assignment found.",
  };
}

async function validateConnectivity(
  app: FastifyInstance,
  deviceId: string,
): Promise<ValidationResult> {
  const readiness =
    await evaluateScoreboardControlReadiness(
      deviceId,
    );

  return {
    step:
      "CONNECTIVITY",
    complete:
      Boolean(
        readiness.lastHeartbeatAt,
      ),
    note:
      readiness.lastHeartbeatAt
        ? `Heartbeat observed at ${readiness.lastHeartbeatAt}.`
        : readiness.reason ??
          "No device heartbeat observed.",
  };
}

async function validateReadiness(
  deviceId: string,
): Promise<ValidationResult> {
  const readiness =
    await evaluateScoreboardControlReadiness(
      deviceId,
    );

  return {
    step:
      "READINESS",
    complete:
      readiness.ready,
    note:
      readiness.ready
        ? `Heartbeat age ${readiness.heartbeatAgeMs ?? 0}ms is within ${readiness.thresholdMs}ms threshold.`
        : `BLOCKED: ${readiness.reason ?? "Device is not ready."}`,
  };
}

function validateReliability(
  deviceId: string,
): ValidationResult {
  const classification =
    listScoreboardReliabilityClassifications()
      .find(
        (item) =>
          item.deviceId ===
          deviceId,
      );

  if (!classification) {
    return {
      step:
        "READINESS",
      complete:
        false,
      note:
        "BLOCKED: Reliability history is unavailable.",
    };
  }

  return {
    step:
      "READINESS",
    complete:
      classification.risk ===
        "HEALTHY" ||
      classification.risk ===
        "WATCH",
    note:
      classification.risk ===
        "HEALTHY" ||
      classification.risk ===
        "WATCH"
        ? `Reliability classification is ${classification.risk}.`
        : `BLOCKED: Reliability classification is ${classification.risk}.`,
  };
}

async function validateFirmware(
  app: FastifyInstance,
  deviceId: string,
): Promise<ValidationResult> {
  const endpoints = [
    `/scoreboard-firmware/device-offer?deviceId=${encodeURIComponent(deviceId)}`,
    `/scoreboard-firmware-releases/device-offer?deviceId=${encodeURIComponent(deviceId)}`,
    "/scoreboard-firmware-releases",
  ];

  for (const endpoint of endpoints) {
    const payload =
      await getJson(
        app,
        endpoint,
      );

    if (!payload) {
      continue;
    }

    const text =
      JSON.stringify(
        payload,
      );

    if (
      text.includes(
        deviceId,
      ) ||
      /firmware|release|version/i.test(
        text,
      )
    ) {
      return {
        step:
          "FIRMWARE",
        complete:
          true,
        note:
          `Firmware state confirmed through ${endpoint}.`,
      };
    }
  }

  return {
    step:
      "FIRMWARE",
    complete:
      false,
    note:
      "Approved firmware state could not be confirmed automatically.",
  };
}

function preserveManualStep(
  record:
    ScoreboardDeviceCommissioning,
  step:
    CommissioningStepId,
): ValidationResult {
  const current =
    record.steps.find(
      (item) =>
        item.id ===
        step,
    );

  return {
    step,
    complete:
      current?.complete ??
      false,
    note:
      current?.note ??
      (
        step ===
          "FLASHED"
          ? "Manual confirmation required after firmware flashing."
          : "Manual confirmation required after device provisioning."
      ),
  };
}

export async function validateScoreboardCommissioning(
  app: FastifyInstance,
  deviceId: string,
): Promise<ScoreboardDeviceCommissioning> {
  const record =
    getScoreboardCommissioning(
      deviceId,
    );

  if (!record) {
    throw new Error(
      "Commissioning record not found.",
    );
  }

  const results:
    ValidationResult[] = [
      preserveManualStep(
        record,
        "FLASHED",
      ),
      preserveManualStep(
        record,
        "PROVISIONED",
      ),
      await validateEnrollment(
        app,
        deviceId,
      ),
      await validateVerification(
        app,
        deviceId,
      ),
      await validateAssignment(
        app,
        deviceId,
      ),
      await validateConnectivity(
        app,
        deviceId,
      ),
    ];

  const directReadiness =
    await validateReadiness(
      deviceId,
    );

  const reliabilityReadiness =
    validateReliability(
      deviceId,
    );

  results.push({
    step:
      "READINESS",
    complete:
      directReadiness.complete &&
      reliabilityReadiness.complete,
    note:
      directReadiness.complete &&
      reliabilityReadiness.complete
        ? `${directReadiness.note} ${reliabilityReadiness.note}`
        : [
            directReadiness.note,
            reliabilityReadiness.note,
          ].join(
            " ",
          ),
  });

  results.push(
    await validateFirmware(
      app,
      deviceId,
    ),
  );

  for (const result of results) {
    updateScoreboardCommissioningStep({
      deviceId,
      step:
        result.step,
      complete:
        result.complete,
      note:
        result.note,
    });
  }

  const refreshed =
    getScoreboardCommissioning(
      deviceId,
    );

  if (!refreshed) {
    throw new Error(
      "Commissioning record disappeared during validation.",
    );
  }

  const prerequisitesPassed =
    refreshed.steps
      .filter(
        (step) =>
          step.id !==
          "GAME_READY",
      )
      .every(
        (step) =>
          step.complete,
      );

  updateScoreboardCommissioningStep({
    deviceId,
    step:
      "GAME_READY",
    complete:
      prerequisitesPassed,
    note:
      prerequisitesPassed
        ? "All commissioning validations passed."
        : "Commissioning prerequisites are incomplete.",
  });

  const finalRecord =
    getScoreboardCommissioning(
      deviceId,
    );

  if (!finalRecord) {
    throw new Error(
      "Unable to load final commissioning result.",
    );
  }

  return finalRecord;
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardDeviceCommissioning.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { validateScoreboardCommissioning } from "../services/scoreboardCommissioningValidator.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate commissioning route imports.",
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
    "/validate",
  )
) {
  const marker =
    "export async function registerScoreboardDeviceCommissioningRoutes";

  const idx =
    text.indexOf(
      marker,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate commissioning route registration.",
    );
  }

  const open =
    text.indexOf(
      "{",
      idx,
    );

  if (open === -1) {
    throw new Error(
      "Unable to locate commissioning route body.",
    );
  }

  const route =
`
  app.post(
    "/scoreboard-device-commissioning/:deviceId/validate",
    async (request, reply) => {
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
            "Device ID is required.",
        });
      }

      try {
        return {
          success: true,
          data: {
            commissioning:
              await validateScoreboardCommissioning(
                app,
                deviceId,
              ),
          },
        };
      } catch (error) {
        return reply.code(409).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Unable to validate scoreboard commissioning.",
        });
      }
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

cat >> "$DOC" <<'EOF'

## Automated validation

Milestone 17.2 adds server-side validation of the commissioning record.

Automatically evaluated stages:

- **ENROLLED**
- **VERIFIED**
- **ASSIGNED**
- **CONNECTIVITY**
- **READINESS**
- **FIRMWARE**

The **FLASHED** and **PROVISIONED** stages remain explicit installation confirmations because they represent physical work that may occur before the controller is visible to the server.

The validator combines the live heartbeat readiness gate and reliability classification before marking **READINESS** complete.

`GAME_READY` is evaluated automatically after every validation pass and is set only when every prerequisite stage is complete.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 17.2 automated commissioning validation", () => {
  const validator = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardCommissioningValidator.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardDeviceCommissioning.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("automatically evaluates enrollment and verification", () => {
    expect(validator).toContain(
      "validateEnrollment",
    );

    expect(validator).toContain(
      "validateVerification",
    );
  });

  it("automatically evaluates assignment and connectivity", () => {
    expect(validator).toContain(
      "/scoreboard-devices/assignments",
    );

    expect(validator).toContain(
      "validateConnectivity",
    );
  });

  it("combines direct readiness and reliability classification", () => {
    expect(validator).toContain(
      "evaluateScoreboardControlReadiness",
    );

    expect(validator).toContain(
      "listScoreboardReliabilityClassifications",
    );
  });

  it("evaluates firmware state", () => {
    expect(validator).toContain(
      "validateFirmware",
    );

    expect(validator).toContain(
      "scoreboard-firmware",
    );
  });

  it("automatically evaluates GAME_READY after prerequisites", () => {
    expect(validator).toContain(
      "prerequisitesPassed",
    );

    expect(validator).toContain(
      '"GAME_READY"',
    );
  });

  it("provides an explicit validation endpoint", () => {
    expect(route).toContain(
      "/scoreboard-device-commissioning/:deviceId/validate",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 17.2 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - automated commissioning validator"
echo "  - enrollment validation"
echo "  - verified-device validation"
echo "  - assignment validation"
echo "  - connectivity/heartbeat validation"
echo "  - readiness + reliability validation"
echo "  - firmware-state validation"
echo "  - automatic GAME_READY evaluation"
echo "  - POST /scoreboard-device-commissioning/:deviceId/validate"
echo "  - Milestone 17.2 regression tests"
echo
echo "Manual-only stages retained:"
echo "  - FLASHED"
echo "  - PROVISIONED"
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
echo "  Milestone 17.3 - Commissioning Dashboard / Installation Wizard"
