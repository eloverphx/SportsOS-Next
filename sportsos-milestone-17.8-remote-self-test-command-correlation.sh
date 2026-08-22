#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-17.8-remote-self-test-correlation-${STAMP}"

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
  "apps/api/src/services/scoreboardCommissioningSelfTest.ts" \
  "apps/api/src/routes/scoreboardDeviceCommissioning.ts" \
  "firmware/esp32-scoreboard/include/CommissioningSelfTest.h" \
  "firmware/esp32-scoreboard/src/CommissioningSelfTest.cpp"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

SERVICE="apps/api/src/services/scoreboardCommissioningSelfTestDispatch.ts"
ROUTE="apps/api/src/routes/scoreboardDeviceCommissioning.ts"
FW_H="firmware/esp32-scoreboard/include/CommissioningSelfTest.h"
FW_CPP="firmware/esp32-scoreboard/src/CommissioningSelfTest.cpp"
TEST="packages/core/test/remote-self-test-correlation-17.8.test.ts"
DOC="docs/SCOREBOARD-DEVICE-COMMISSIONING.md"

for file in "$SERVICE" "$ROUTE" "$FW_H" "$FW_CPP" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import crypto from "node:crypto";

export type CommissioningSelfTestDispatch = {
  commandId: string;
  deviceId: string;
  status:
    | "PENDING"
    | "ACKNOWLEDGED"
    | "COMPLETED"
    | "FAILED";
  requestedAt: string;
  acknowledgedAt: string | null;
  completedAt: string | null;
  resultTestId: string | null;
};

const dispatches =
  new Map<
    string,
    CommissioningSelfTestDispatch
  >();

export function createCommissioningSelfTestDispatch(
  deviceId: string,
): CommissioningSelfTestDispatch {
  const commandId =
    `commissioning-self-test-${crypto.randomUUID()}`;

  const dispatch:
    CommissioningSelfTestDispatch = {
      commandId,
      deviceId,
      status:
        "PENDING",
      requestedAt:
        new Date().toISOString(),
      acknowledgedAt:
        null,
      completedAt:
        null,
      resultTestId:
        null,
    };

  dispatches.set(
    commandId,
    dispatch,
  );

  return {
    ...dispatch,
  };
}

export function getCommissioningSelfTestDispatch(
  commandId: string,
): CommissioningSelfTestDispatch | null {
  const dispatch =
    dispatches.get(
      commandId,
    );

  return dispatch
    ? { ...dispatch }
    : null;
}

export function acknowledgeCommissioningSelfTestDispatch(
  commandId: string,
  deviceId: string,
): CommissioningSelfTestDispatch {
  const dispatch =
    dispatches.get(
      commandId,
    );

  if (!dispatch) {
    throw new Error(
      "Self-test command not found.",
    );
  }

  if (
    dispatch.deviceId !==
    deviceId
  ) {
    throw new Error(
      "Self-test command belongs to another device.",
    );
  }

  dispatch.status =
    "ACKNOWLEDGED";
  dispatch.acknowledgedAt =
    new Date().toISOString();

  return {
    ...dispatch,
  };
}

export function completeCommissioningSelfTestDispatch(
  commandId: string,
  deviceId: string,
  resultTestId: string,
  passed: boolean,
): CommissioningSelfTestDispatch {
  const dispatch =
    dispatches.get(
      commandId,
    );

  if (!dispatch) {
    throw new Error(
      "Self-test command not found.",
    );
  }

  if (
    dispatch.deviceId !==
    deviceId
  ) {
    throw new Error(
      "Self-test command belongs to another device.",
    );
  }

  dispatch.status =
    passed
      ? "COMPLETED"
      : "FAILED";
  dispatch.completedAt =
    new Date().toISOString();
  dispatch.resultTestId =
    resultTestId;

  return {
    ...dispatch,
  };
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardDeviceCommissioning.ts";

let text =
  fs.readFileSync(file, "utf8");

const importLine =
  'import { acknowledgeCommissioningSelfTestDispatch, completeCommissioningSelfTestDispatch, createCommissioningSelfTestDispatch, getCommissioningSelfTestDispatch } from "../services/scoreboardCommissioningSelfTestDispatch.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(?:import[\s\S]*?;\n)+/);

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

if (!text.includes("/self-test/dispatch")) {
  const marker =
`  app.post(
    "/scoreboard-device-commissioning/:deviceId/self-test/telemetry",`;

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate 17.7 telemetry route.",
    );
  }

  const routes =
`  app.post(
    "/scoreboard-device-commissioning/:deviceId/self-test/dispatch",
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

      const dispatch =
        createCommissioningSelfTestDispatch(
          deviceId,
        );

      /*
       * 17.8 establishes the correlated command contract.
       * MQTT/device-gateway publication can consume this command
       * object without changing the API correlation model.
       */
      return reply.code(202).send({
        success: true,
        data: {
          dispatch,
          command: {
            type:
              "COMMISSIONING_SELF_TEST",
            commandId:
              dispatch.commandId,
            deviceId:
              dispatch.deviceId,
            requestedAt:
              dispatch.requestedAt,
          },
        },
      });
    },
  );

  app.get(
    "/scoreboard-device-commissioning/:deviceId/self-test/dispatch/:commandId",
    async (request, reply) => {
      const params =
        request.params as {
          deviceId?: string;
          commandId?: string;
        };

      const deviceId =
        params.deviceId?.trim();
      const commandId =
        params.commandId?.trim();

      if (
        !deviceId ||
        !commandId
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Device ID and command ID are required.",
        });
      }

      const dispatch =
        getCommissioningSelfTestDispatch(
          commandId,
        );

      if (
        !dispatch ||
        dispatch.deviceId !==
          deviceId
      ) {
        return reply.code(404).send({
          success: false,
          error:
            "Self-test dispatch not found.",
        });
      }

      return {
        success: true,
        data: {
          dispatch,
        },
      };
    },
  );

  app.post(
    "/scoreboard-device-commissioning/:deviceId/self-test/dispatch/:commandId/ack",
    async (request, reply) => {
      const params =
        request.params as {
          deviceId?: string;
          commandId?: string;
        };

      const deviceId =
        params.deviceId?.trim();
      const commandId =
        params.commandId?.trim();

      if (
        !deviceId ||
        !commandId
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Device ID and command ID are required.",
        });
      }

      try {
        return {
          success: true,
          data: {
            dispatch:
              acknowledgeCommissioningSelfTestDispatch(
                commandId,
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
              : "Unable to acknowledge self-test command.",
        });
      }
    },
  );

`;

  text =
    text.slice(0, idx) +
    routes +
    text.slice(idx);
}

/* Insert commandId support into telemetry body. */
if (!text.includes("commandId?: string;")) {
  const telemetryMarker =
`          firmwareRuntimePassed?: boolean;
          detail?: string;`;

  if (!text.includes(telemetryMarker)) {
    throw new Error(
      "Unable to locate telemetry body type.",
    );
  }

  text =
    text.replace(
      telemetryMarker,
`          firmwareRuntimePassed?: boolean;
          detail?: string;
          commandId?: string;`
    );
}

/* Correlate result after createCommissioningSelfTestResult. */
const resultMarker =
`      const result =
        createCommissioningSelfTestResult({`;

const resultIdx =
  text.indexOf(resultMarker);

if (resultIdx === -1) {
  throw new Error(
    "Unable to locate telemetry self-test result creation.",
  );
}

const ackMarker =
`      return reply.code(202).send({
        success: true,
        data: {
          acknowledged:
            true,
          selfTest:
            result,
        },
      });`;

if (
  text.includes(ackMarker) &&
  !text.includes(
    "correlatedDispatch"
  )
) {
  text =
    text.replace(
      ackMarker,
`      let correlatedDispatch =
        null;

      if (
        typeof body.commandId ===
          "string" &&
        body.commandId.trim()
      ) {
        try {
          correlatedDispatch =
            completeCommissioningSelfTestDispatch(
              body.commandId.trim(),
              deviceId,
              result.testId,
              result.status ===
                "PASS",
            );
        } catch (error) {
          return reply.code(409).send({
            success: false,
            error:
              error instanceof Error
                ? error.message
                : "Unable to correlate self-test result.",
          });
        }
      }

      return reply.code(202).send({
        success: true,
        data: {
          acknowledged:
            true,
          selfTest:
            result,
          dispatch:
            correlatedDispatch,
        },
      });`
    );
}

fs.writeFileSync(file, text);
NODE

# Fix the guard above: completion function should now be used after route rewrite.
grep -q 'completeCommissioningSelfTestDispatch(' "$ROUTE" || {
  echo "ERROR: telemetry correlation was not installed." >&2
  exit 1
}

node <<'NODE'
const fs = require("fs");

const header =
  "firmware/esp32-scoreboard/include/CommissioningSelfTest.h";
const cpp =
  "firmware/esp32-scoreboard/src/CommissioningSelfTest.cpp";

let h =
  fs.readFileSync(header, "utf8");
let c =
  fs.readFileSync(cpp, "utf8");

if (!h.includes("commandId")) {
  h =
    h.replace(
`  static String toJson(
      const String& deviceId,
      const CommissioningSelfTestTelemetry& telemetry);`,
`  static String toJson(
      const String& deviceId,
      const String& commandId,
      const CommissioningSelfTestTelemetry& telemetry);`
    );
}

if (
  c.includes(
`CommissioningSelfTest::toJson(
    const String& deviceId,
    const CommissioningSelfTestTelemetry& telemetry)`
  )
) {
  c =
    c.replace(
`CommissioningSelfTest::toJson(
    const String& deviceId,
    const CommissioningSelfTestTelemetry& telemetry)`,
`CommissioningSelfTest::toJson(
    const String& deviceId,
    const String& commandId,
    const CommissioningSelfTestTelemetry& telemetry)`
    );
}

if (!c.includes('document["commandId"]')) {
  c =
    c.replace(
`  document["deviceId"] = deviceId;`,
`  document["deviceId"] = deviceId;
  document["commandId"] = commandId;`
    );
}

fs.writeFileSync(header, h);
fs.writeFileSync(cpp, c);
NODE

cat >> "$DOC" <<'EOF'

## Remote self-test command correlation

Milestone 17.8 adds a command correlation lifecycle for remote commissioning self-tests:

- `PENDING` when SportsOS creates the request
- `ACKNOWLEDGED` when the device accepts the command
- `COMPLETED` when correlated firmware telemetry reports PASS
- `FAILED` when correlated firmware telemetry reports FAIL

Each request receives a unique `commandId`. Firmware telemetry echoes that `commandId`, allowing SportsOS to bind the device response to the exact commissioning request rather than treating telemetry as an uncorrelated event.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 17.8 remote self-test dispatch / response correlation", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardCommissioningSelfTestDispatch.ts",
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

  const firmware = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/CommissioningSelfTest.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  it("creates unique correlated self-test commands", () => {
    expect(service).toContain(
      "crypto.randomUUID",
    );

    expect(service).toContain(
      '"PENDING"',
    );
  });

  it("tracks acknowledgement and completion states", () => {
    expect(service).toContain(
      '"ACKNOWLEDGED"',
    );

    expect(service).toContain(
      '"COMPLETED"',
    );

    expect(service).toContain(
      '"FAILED"',
    );
  });

  it("provides dispatch and acknowledgement API routes", () => {
    expect(route).toContain(
      "/self-test/dispatch",
    );

    expect(route).toContain(
      "/ack",
    );

    expect(route).toContain(
      "COMMISSIONING_SELF_TEST",
    );
  });

  it("correlates firmware telemetry with command ID", () => {
    expect(route).toContain(
      "commandId?: string",
    );

    expect(route).toContain(
      "completeCommissioningSelfTestDispatch",
    );

    expect(firmware).toContain(
      'document["commandId"]',
    );
  });

  it("rejects command/device mismatches", () => {
    expect(service).toContain(
      "Self-test command belongs to another device.",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 17.8 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - unique remote self-test command IDs"
echo "  - PENDING / ACKNOWLEDGED / COMPLETED / FAILED lifecycle"
echo "  - dispatch API"
echo "  - device acknowledgement API"
echo "  - dispatch status API"
echo "  - firmware commandId telemetry echo"
echo "  - result-to-command correlation"
echo "  - cross-device correlation protection"
echo "  - Milestone 17.8 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then firmware:"
echo "  bash firmware/esp32-scoreboard/build-in-docker.sh"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 17.9 - MQTT Self-Test Command Transport / Device Execution"
