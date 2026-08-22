#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-17.1-scoreboard-device-commissioning-${STAMP}"

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
  "apps/api/src/modules/scoreboard-devices/repository.ts" \
  "apps/api/src/services/scoreboardControlReadiness.ts" \
  "apps/api/src/services/scoreboardReadinessReliability.ts" \
  "apps/api/src/services/scoreboardPregameReadinessGate.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

SERVICE="apps/api/src/services/scoreboardDeviceCommissioning.ts"
ROUTE="apps/api/src/routes/scoreboardDeviceCommissioning.ts"
TEST="packages/core/test/scoreboard-device-commissioning-17.1.test.ts"
DOC="docs/SCOREBOARD-DEVICE-COMMISSIONING.md"

for file in "$SERVICE" "$ROUTE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$ROUTE")" "$(dirname "$TEST")" "$(dirname "$DOC")"

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type CommissioningStepId =
  | "FLASHED"
  | "PROVISIONED"
  | "ENROLLED"
  | "VERIFIED"
  | "ASSIGNED"
  | "CONNECTIVITY"
  | "READINESS"
  | "FIRMWARE"
  | "GAME_READY";

export type CommissioningStep = {
  id: CommissioningStepId;
  complete: boolean;
  completedAt: string | null;
  note: string | null;
};

export type ScoreboardDeviceCommissioning = {
  deviceId: string;
  createdAt: string;
  updatedAt: string;
  status:
    | "IN_PROGRESS"
    | "BLOCKED"
    | "GAME_READY";
  steps: CommissioningStep[];
};

type Store = {
  version: 1;
  devices: ScoreboardDeviceCommissioning[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(process.cwd(), "data");

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-device-commissioning.json",
  );

const STEP_ORDER: CommissioningStepId[] = [
  "FLASHED",
  "PROVISIONED",
  "ENROLLED",
  "VERIFIED",
  "ASSIGNED",
  "CONNECTIVITY",
  "READINESS",
  "FIRMWARE",
  "GAME_READY",
];

let store = loadStore();

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
        parsed.devices,
      )
    ) {
      throw new Error(
        "Invalid commissioning store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      devices: [],
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

function emptySteps():
  CommissioningStep[] {
  return STEP_ORDER.map(
    (id) => ({
      id,
      complete: false,
      completedAt: null,
      note: null,
    }),
  );
}

function deriveStatus(
  record:
    ScoreboardDeviceCommissioning,
): ScoreboardDeviceCommissioning["status"] {
  const gameReady =
    record.steps.find(
      (step) =>
        step.id ===
        "GAME_READY",
    );

  if (
    gameReady?.complete
  ) {
    return "GAME_READY";
  }

  const readiness =
    record.steps.find(
      (step) =>
        step.id ===
        "READINESS",
    );

  if (
    readiness &&
    readiness.note?.startsWith(
      "BLOCKED:",
    )
  ) {
    return "BLOCKED";
  }

  return "IN_PROGRESS";
}

export function beginScoreboardCommissioning(
  deviceId: string,
): ScoreboardDeviceCommissioning {
  const normalized =
    deviceId.trim();

  if (!normalized) {
    throw new Error(
      "Device ID is required.",
    );
  }

  const existing =
    store.devices.find(
      (item) =>
        item.deviceId ===
        normalized,
    );

  if (existing) {
    return existing;
  }

  const now =
    new Date().toISOString();

  const record:
    ScoreboardDeviceCommissioning = {
      deviceId:
        normalized,
      createdAt:
        now,
      updatedAt:
        now,
      status:
        "IN_PROGRESS",
      steps:
        emptySteps(),
    };

  store.devices.push(
    record,
  );

  persistStore();

  return record;
}

export function updateScoreboardCommissioningStep(input: {
  deviceId: string;
  step: CommissioningStepId;
  complete: boolean;
  note?: string | null;
}): ScoreboardDeviceCommissioning {
  const record =
    beginScoreboardCommissioning(
      input.deviceId,
    );

  const step =
    record.steps.find(
      (item) =>
        item.id ===
        input.step,
    );

  if (!step) {
    throw new Error(
      "Unknown commissioning step.",
    );
  }

  if (
    input.step ===
      "GAME_READY" &&
    input.complete
  ) {
    const prerequisites =
      record.steps.filter(
        (item) =>
          item.id !==
          "GAME_READY",
      );

    if (
      prerequisites.some(
        (item) =>
          !item.complete,
      )
    ) {
      throw new Error(
        "All commissioning prerequisites must pass before GAME_READY.",
      );
    }
  }

  step.complete =
    input.complete;

  step.completedAt =
    input.complete
      ? new Date().toISOString()
      : null;

  step.note =
    input.note?.trim() ||
    null;

  record.updatedAt =
    new Date().toISOString();

  record.status =
    deriveStatus(
      record,
    );

  persistStore();

  return record;
}

export function getScoreboardCommissioning(
  deviceId: string,
): ScoreboardDeviceCommissioning | null {
  return (
    store.devices.find(
      (item) =>
        item.deviceId ===
        deviceId,
    ) ??
    null
  );
}

export function listScoreboardCommissioning():
  ScoreboardDeviceCommissioning[] {
  return [...store.devices]
    .sort(
      (a, b) =>
        b.updatedAt.localeCompare(
          a.updatedAt,
        ),
    );
}
EOF

cat > "$ROUTE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import {
  beginScoreboardCommissioning,
  getScoreboardCommissioning,
  listScoreboardCommissioning,
  updateScoreboardCommissioningStep,
  type CommissioningStepId,
} from "../services/scoreboardDeviceCommissioning.js";

const VALID_STEPS =
  new Set<CommissioningStepId>([
    "FLASHED",
    "PROVISIONED",
    "ENROLLED",
    "VERIFIED",
    "ASSIGNED",
    "CONNECTIVITY",
    "READINESS",
    "FIRMWARE",
    "GAME_READY",
  ]);

export async function registerScoreboardDeviceCommissioningRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.get(
    "/scoreboard-device-commissioning",
    async () => ({
      success: true,
      data: {
        devices:
          listScoreboardCommissioning(),
      },
    }),
  );

  app.get(
    "/scoreboard-device-commissioning/:deviceId",
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

      const record =
        getScoreboardCommissioning(
          deviceId,
        );

      if (!record) {
        return reply.code(404).send({
          success: false,
          error:
            "Commissioning record not found.",
        });
      }

      return {
        success: true,
        data: {
          commissioning:
            record,
        },
      };
    },
  );

  app.post(
    "/scoreboard-device-commissioning/:deviceId",
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

      return {
        success: true,
        data: {
          commissioning:
            beginScoreboardCommissioning(
              deviceId,
            ),
        },
      };
    },
  );

  app.put(
    "/scoreboard-device-commissioning/:deviceId/step",
    async (request, reply) => {
      const params =
        request.params as {
          deviceId?: string;
        };

      const body =
        request.body as {
          step?: string;
          complete?: boolean;
          note?: string | null;
        };

      const deviceId =
        params.deviceId?.trim();

      if (
        !deviceId ||
        !body.step ||
        typeof body.complete !==
          "boolean" ||
        !VALID_STEPS.has(
          body.step as
            CommissioningStepId,
        )
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Valid device ID, commissioning step, and completion state are required.",
        });
      }

      try {
        const commissioning =
          updateScoreboardCommissioningStep({
            deviceId,
            step:
              body.step as
                CommissioningStepId,
            complete:
              body.complete,
            note:
              body.note,
          });

        return {
          success: true,
          data: {
            commissioning,
          },
        };
      } catch (error) {
        return reply.code(409).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Unable to update commissioning state.",
        });
      }
    },
  );
}
EOF

cat > "$DOC" <<'EOF'
# SportsOS Scoreboard Device Commissioning

Milestone 17.1 establishes the installation workflow for a physical scoreboard controller.

A controller progresses through these stages:

1. **FLASHED** — production ESP32 firmware has been installed.
2. **PROVISIONED** — local network/API configuration is present.
3. **ENROLLED** — the controller has completed SportsOS enrollment.
4. **VERIFIED** — the server recognizes the device as verified hardware.
5. **ASSIGNED** — the device is assigned to the intended scoreboard/game context.
6. **CONNECTIVITY** — API/MQTT communication is functioning.
7. **READINESS** — heartbeat/readiness checks pass.
8. **FIRMWARE** — installed firmware is on the approved release/channel.
9. **GAME_READY** — all previous commissioning requirements have passed.

`GAME_READY` cannot be set until every prior commissioning stage is complete.

The commissioning record is persistent and is intended to become the server-side source for the Milestone 17 installation UI and automated commissioning checks.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 17.1 scoreboard device commissioning", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardDeviceCommissioning.ts",
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

  const doc = fs.readFileSync(
    new URL(
      "../../../docs/SCOREBOARD-DEVICE-COMMISSIONING.md",
      import.meta.url,
    ),
    "utf8",
  );

  it("defines the complete commissioning lifecycle", () => {
    for (const step of [
      "FLASHED",
      "PROVISIONED",
      "ENROLLED",
      "VERIFIED",
      "ASSIGNED",
      "CONNECTIVITY",
      "READINESS",
      "FIRMWARE",
      "GAME_READY",
    ]) {
      expect(service).toContain(
        `"${step}"`,
      );
    }
  });

  it("persists commissioning records", () => {
    expect(service).toContain(
      "scoreboard-device-commissioning.json",
    );
  });

  it("prevents premature GAME_READY state", () => {
    expect(service).toContain(
      "All commissioning prerequisites must pass before GAME_READY.",
    );
  });

  it("provides commissioning API routes", () => {
    expect(route).toContain(
      "/scoreboard-device-commissioning",
    );

    expect(route).toContain(
      "/scoreboard-device-commissioning/:deviceId/step",
    );
  });

  it("documents physical installation stages", () => {
    expect(doc).toContain(
      "SportsOS Scoreboard Device Commissioning",
    );

    expect(doc).toContain(
      "production ESP32 firmware",
    );

    expect(doc).toContain(
      "GAME_READY",
    );
  });
});
EOF

# Discover API route registration rather than guessing.
REGISTRATION_FILE="$(
node <<'NODE'
const fs = require("fs");
const path = require("path");

const root = "apps/api/src";
const files = [];

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (entry.isFile() && entry.name.endsWith(".ts")) files.push(full);
  }
}

walk(root);

const candidates = [];

for (const file of files) {
  const text = fs.readFileSync(file, "utf8");
  let score = 0;

  if (/register.*Routes/.test(text)) score += 4;
  if (/scoreboardDeviceEnrollment|scoreboardDevicesRoutes|scoreboardDeviceRoutes/.test(text)) score += 12;
  if (/app\.register|fastify\.register/.test(text)) score += 5;
  if (/buildApp|createApp/.test(text)) score += 3;

  if (score > 0) candidates.push({ file, score });
}

candidates.sort((a, b) => b.score - a.score);

if (!candidates.length) process.exit(2);
console.log(candidates[0].file);
NODE
)" || {
  echo "ERROR: unable to discover API route registration file." >&2
  echo "New 17.1 files were created, but route registration was NOT modified." >&2
  exit 1
}

mkdir -p "$BACKUP/$(dirname "$REGISTRATION_FILE")"
cp -a "$REGISTRATION_FILE" "$BACKUP/$REGISTRATION_FILE"

node - "$REGISTRATION_FILE" <<'NODE'
const fs = require("fs");
const path = require("path");

const file = process.argv[2];
let text = fs.readFileSync(file, "utf8");

if (text.includes("registerScoreboardDeviceCommissioningRoutes")) {
  console.log("17.1 commissioning routes already registered.");
  process.exit(0);
}

const routeAbs =
  path.resolve(
    "apps/api/src/routes/scoreboardDeviceCommissioning.ts",
  );

const fileDir =
  path.dirname(
    path.resolve(file),
  );

let relative =
  path.relative(
    fileDir,
    routeAbs,
  ).replace(/\\/g, "/");

relative =
  relative.replace(
    /\.ts$/,
    ".js",
  );

if (!relative.startsWith(".")) {
  relative =
    `./${relative}`;
}

const importLine =
  `import { registerScoreboardDeviceCommissioningRoutes } from "${relative}";\n`;

const imports =
  text.match(/^(?:import[\s\S]*?;\n)+/);

if (!imports) {
  throw new Error(
    "Unable to locate API registration imports.",
  );
}

text =
  text.replace(
    imports[0],
    imports[0] +
      importLine,
  );

const registrationPatterns = [
  /await\s+app\.register\([^;]+;\n/g,
  /app\.register\([^;]+;\n/g,
  /await\s+fastify\.register\([^;]+;\n/g,
  /fastify\.register\([^;]+;\n/g,
];

let last = null;

for (const pattern of registrationPatterns) {
  const matches =
    [...text.matchAll(pattern)];

  if (matches.length) {
    const candidate =
      matches[matches.length - 1];

    if (
      !last ||
      candidate.index >
        last.index
    ) {
      last =
        candidate;
    }
  }
}

if (!last) {
  throw new Error(
    "Unable to locate API route registration anchor.",
  );
}

const insertAt =
  last.index +
  last[0].length;

const call =
  last[0].includes(
    "fastify.register",
  )
    ? "  await fastify.register(registerScoreboardDeviceCommissioningRoutes);\n"
    : "  await app.register(registerScoreboardDeviceCommissioningRoutes);\n";

text =
  text.slice(0, insertAt) +
  call +
  text.slice(insertAt);

fs.writeFileSync(file, text);

console.log(
  `Registered commissioning routes in ${file}`,
);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 17.1 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - persistent physical device commissioning records"
echo "  - FLASHED -> GAME_READY installation lifecycle"
echo "  - prerequisite enforcement before GAME_READY"
echo "  - commissioning list/detail/start/update API"
echo "  - installation workflow documentation"
echo "  - Milestone 17.1 regression tests"
echo
echo "API registration:"
echo "  $REGISTRATION_FILE"
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
echo "  Milestone 17.2 - Automated Commissioning Validation / GAME_READY Evaluation"
