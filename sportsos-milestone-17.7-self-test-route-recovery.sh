#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-17.7-self-test-route-recovery-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/scoreboardCommissioningSelfTest.ts"
ROUTE="apps/api/src/routes/scoreboardDeviceCommissioning.ts"
TEST="packages/core/test/scoreboard-commissioning-self-test-route-recovery-17.7.test.ts"

for required in \
  ".git" \
  "package.json" \
  "$ROUTE"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$ROUTE" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type CommissioningSelfTestCheck = {
  id:
    | "CONTROLLER"
    | "DISPLAY"
    | "INPUT"
    | "CONNECTIVITY"
    | "FIRMWARE_RUNTIME";
  passed: boolean;
  detail: string;
};

export type CommissioningSelfTestResult = {
  testId: string;
  deviceId: string;
  status:
    | "PASS"
    | "FAIL";
  checks: CommissioningSelfTestCheck[];
  startedAt: string;
  completedAt: string;
  source:
    | "INSTALLER"
    | "FIRMWARE";
};

type Store = {
  version: 1;
  results:
    CommissioningSelfTestResult[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(process.cwd(), "data");

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-commissioning-self-tests.json",
  );

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
        parsed.results,
      )
    ) {
      throw new Error(
        "Invalid commissioning self-test store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      results: [],
    };
  }
}

function persistStore(): void {
  fs.mkdirSync(
    DATA_DIR,
    { recursive: true },
  );

  const temporary =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    temporary,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );

  fs.renameSync(
    temporary,
    STORE_FILE,
  );
}

export function createCommissioningSelfTestResult(input: {
  deviceId: string;
  checks: CommissioningSelfTestCheck[];
  startedAt: string;
  source?: "INSTALLER" | "FIRMWARE";
}): CommissioningSelfTestResult {
  const result:
    CommissioningSelfTestResult = {
      testId:
        `selftest-${input.deviceId}-${Date.now()}`,
      deviceId:
        input.deviceId,
      status:
        input.checks.every(
          (check) =>
            check.passed,
        )
          ? "PASS"
          : "FAIL",
      checks:
        input.checks.map(
          (check) => ({
            ...check,
          }),
        ),
      startedAt:
        input.startedAt,
      completedAt:
        new Date().toISOString(),
      source:
        input.source ??
        "INSTALLER",
    };

  store.results.push(
    result,
  );

  if (
    store.results.length >
    1000
  ) {
    store.results =
      store.results.slice(
        -1000,
      );
  }

  persistStore();

  return {
    ...result,
    checks:
      result.checks.map(
        (check) => ({
          ...check,
        }),
      ),
  };
}

export function latestCommissioningSelfTest(
  deviceId: string,
): CommissioningSelfTestResult | null {
  const result =
    [...store.results]
      .reverse()
      .find(
        (item) =>
          item.deviceId ===
          deviceId,
      );

  return result
    ? {
        ...result,
        checks:
          result.checks.map(
            (check) => ({
              ...check,
            }),
          ),
      }
    : null;
}

export function listCommissioningSelfTests(
  deviceId?: string,
): CommissioningSelfTestResult[] {
  return [...store.results]
    .filter(
      (item) =>
        !deviceId ||
        item.deviceId ===
          deviceId,
    )
    .sort(
      (a, b) =>
        b.completedAt.localeCompare(
          a.completedAt,
        ),
    )
    .map(
      (item) => ({
        ...item,
        checks:
          item.checks.map(
            (check) => ({
              ...check,
            }),
          ),
      }),
    );
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
  'import { createCommissioningSelfTestResult, latestCommissioningSelfTest } from "../services/scoreboardCommissioningSelfTest.js";';

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

let routes = "";

if (
  !text.includes(
    "/scoreboard-device-commissioning/:deviceId/self-test\""
  )
) {
  routes += `
  app.get(
    "/scoreboard-device-commissioning/:deviceId/self-test",
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
          selfTest:
            latestCommissioningSelfTest(
              deviceId,
            ),
        },
      };
    },
  );

  app.post(
    "/scoreboard-device-commissioning/:deviceId/self-test",
    async (request, reply) => {
      const params =
        request.params as {
          deviceId?: string;
        };

      const body =
        request.body as {
          controllerPassed?: boolean;
          displayPassed?: boolean;
          inputPassed?: boolean;
          connectivityPassed?: boolean;
          firmwareRuntimePassed?: boolean;
          details?: {
            controller?: string;
            display?: string;
            input?: string;
            connectivity?: string;
            firmwareRuntime?: string;
          };
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

      const required = [
        body.controllerPassed,
        body.displayPassed,
        body.inputPassed,
        body.connectivityPassed,
        body.firmwareRuntimePassed,
      ];

      if (
        required.some(
          (value) =>
            typeof value !==
            "boolean",
        )
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "All hardware self-test checks must be reported.",
        });
      }

      const result =
        createCommissioningSelfTestResult({
          deviceId,
          source:
            "INSTALLER",
          startedAt:
            new Date().toISOString(),
          checks: [
            {
              id:
                "CONTROLLER",
              passed:
                body.controllerPassed ===
                true,
              detail:
                body.details?.controller ??
                "Controller runtime check.",
            },
            {
              id:
                "DISPLAY",
              passed:
                body.displayPassed ===
                true,
              detail:
                body.details?.display ??
                "Scoreboard display path check.",
            },
            {
              id:
                "INPUT",
              passed:
                body.inputPassed ===
                true,
              detail:
                body.details?.input ??
                "Physical control input path check.",
            },
            {
              id:
                "CONNECTIVITY",
              passed:
                body.connectivityPassed ===
                true,
              detail:
                body.details?.connectivity ??
                "SportsOS connectivity check.",
            },
            {
              id:
                "FIRMWARE_RUNTIME",
              passed:
                body.firmwareRuntimePassed ===
                true,
              detail:
                body.details?.firmwareRuntime ??
                "Firmware runtime check.",
            },
          ],
        });

      return {
        success: true,
        data: {
          selfTest:
            result,
        },
      };
    },
  );

`;
}

if (
  !text.includes(
    "/scoreboard-device-commissioning/:deviceId/self-test/telemetry"
  )
) {
  routes += `
  app.post(
    "/scoreboard-device-commissioning/:deviceId/self-test/telemetry",
    async (request, reply) => {
      const params =
        request.params as {
          deviceId?: string;
        };

      const body =
        request.body as {
          deviceId?: string;
          controllerPassed?: boolean;
          displayPassed?: boolean;
          inputPassed?: boolean;
          connectivityPassed?: boolean;
          firmwareRuntimePassed?: boolean;
          detail?: string;
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

      if (
        body.deviceId &&
        body.deviceId.trim() !==
          deviceId
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Telemetry device ID does not match route device ID.",
        });
      }

      const required = [
        body.controllerPassed,
        body.displayPassed,
        body.inputPassed,
        body.connectivityPassed,
        body.firmwareRuntimePassed,
      ];

      if (
        required.some(
          (value) =>
            typeof value !==
            "boolean",
        )
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Firmware telemetry must report every self-test check.",
        });
      }

      const detail =
        typeof body.detail ===
          "string" &&
        body.detail.trim()
          ? body.detail.trim()
          : "Firmware-reported commissioning self-test.";

      const result =
        createCommissioningSelfTestResult({
          deviceId,
          source:
            "FIRMWARE",
          startedAt:
            new Date().toISOString(),
          checks: [
            {
              id:
                "CONTROLLER",
              passed:
                body.controllerPassed ===
                true,
              detail,
            },
            {
              id:
                "DISPLAY",
              passed:
                body.displayPassed ===
                true,
              detail,
            },
            {
              id:
                "INPUT",
              passed:
                body.inputPassed ===
                true,
              detail,
            },
            {
              id:
                "CONNECTIVITY",
              passed:
                body.connectivityPassed ===
                true,
              detail,
            },
            {
              id:
                "FIRMWARE_RUNTIME",
              passed:
                body.firmwareRuntimePassed ===
                true,
              detail,
            },
          ],
        });

      return reply.code(202).send({
        success: true,
        data: {
          acknowledged:
            true,
          selfTest:
            result,
        },
      });
    },
  );

`;
}

if (routes) {
  text =
    text.slice(
      0,
      open + 1,
    ) +
    routes +
    text.slice(
      open + 1,
    );
}

for (const required of [
  "createCommissioningSelfTestResult",
  "latestCommissioningSelfTest",
  "/scoreboard-device-commissioning/:deviceId/self-test",
  "/scoreboard-device-commissioning/:deviceId/self-test/telemetry",
]) {
  if (!text.includes(required)) {
    throw new Error(
      `Self-test route recovery failed: ${required}`,
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

describe("Milestone 17.7 self-test route recovery", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardCommissioningSelfTest.ts",
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

  it("restores the self-test service", () => {
    expect(service).toContain(
      "createCommissioningSelfTestResult",
    );

    expect(service).toContain(
      "latestCommissioningSelfTest",
    );
  });

  it("restores installer self-test routes", () => {
    expect(route).toContain(
      "/scoreboard-device-commissioning/:deviceId/self-test",
    );

    expect(route).toContain(
      'source:\n            "INSTALLER"',
    );
  });

  it("restores firmware telemetry route", () => {
    expect(route).toContain(
      "/scoreboard-device-commissioning/:deviceId/self-test/telemetry",
    );

    expect(route).toContain(
      'source:\n            "FIRMWARE"',
    );

    expect(route).toContain(
      "acknowledged",
    );
  });

  it("preserves route/device identity validation", () => {
    expect(route).toContain(
      "Telemetry device ID does not match route device ID.",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 17.7 self-test route recovery"
echo "============================================================"
echo
echo "Restored:"
echo "  - scoreboardCommissioningSelfTest service"
echo "  - GET latest self-test route"
echo "  - POST installer self-test route"
echo "  - POST firmware telemetry route"
echo "  - INSTALLER / FIRMWARE source tracking"
echo "  - HTTP 202 firmware acknowledgement"
echo "  - telemetry device-ID validation"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then retry:"
echo "  bash sportsos-milestone-17.8-remote-self-test-command-correlation.sh"
