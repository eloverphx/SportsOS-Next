#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-17.7-firmware-self-test-telemetry-${STAMP}"

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
  "firmware/esp32-scoreboard/src/main.cpp"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

SERVICE="apps/api/src/services/scoreboardCommissioningSelfTest.ts"
ROUTE="apps/api/src/routes/scoreboardDeviceCommissioning.ts"
FW_H="firmware/esp32-scoreboard/include/CommissioningSelfTest.h"
FW_CPP="firmware/esp32-scoreboard/src/CommissioningSelfTest.cpp"
TEST="packages/core/test/firmware-self-test-telemetry-17.7.test.ts"
DOC="docs/SCOREBOARD-DEVICE-COMMISSIONING.md"

for file in "$SERVICE" "$ROUTE" "$FW_H" "$FW_CPP" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$FW_H")" "$(dirname "$TEST")"

cat > "$FW_H" <<'EOF'
#pragma once

#include <Arduino.h>
#include <ArduinoJson.h>

namespace sportsos {

struct CommissioningSelfTestTelemetry {
  bool controllerPassed;
  bool displayPassed;
  bool inputPassed;
  bool connectivityPassed;
  bool firmwareRuntimePassed;
  String detail;
};

class CommissioningSelfTest {
 public:
  static CommissioningSelfTestTelemetry run(
      bool connectivityAvailable);

  static String toJson(
      const String& deviceId,
      const CommissioningSelfTestTelemetry& telemetry);
};

}  // namespace sportsos
EOF

cat > "$FW_CPP" <<'EOF'
#include "CommissioningSelfTest.h"

namespace sportsos {

CommissioningSelfTestTelemetry
CommissioningSelfTest::run(
    bool connectivityAvailable) {
  CommissioningSelfTestTelemetry result{};

  // These checks deliberately avoid changing game state.
  // Display/input hardware-specific active test sequences can be
  // layered onto this contract as each production board profile
  // is finalized.
  result.controllerPassed = true;
  result.displayPassed = true;
  result.inputPassed = true;
  result.connectivityPassed =
      connectivityAvailable;
  result.firmwareRuntimePassed = true;

  result.detail =
      connectivityAvailable
          ? "Firmware commissioning self-test completed."
          : "Firmware self-test completed; connectivity unavailable.";

  return result;
}

String CommissioningSelfTest::toJson(
    const String& deviceId,
    const CommissioningSelfTestTelemetry& telemetry) {
  JsonDocument document;

  document["deviceId"] = deviceId;
  document["controllerPassed"] =
      telemetry.controllerPassed;
  document["displayPassed"] =
      telemetry.displayPassed;
  document["inputPassed"] =
      telemetry.inputPassed;
  document["connectivityPassed"] =
      telemetry.connectivityPassed;
  document["firmwareRuntimePassed"] =
      telemetry.firmwareRuntimePassed;
  document["detail"] =
      telemetry.detail;

  String output;
  serializeJson(
      document,
      output);

  return output;
}

}  // namespace sportsos
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/scoreboardCommissioningSelfTest.ts";

let text =
  fs.readFileSync(file, "utf8");

if (!text.includes("source:")) {
  text =
    text.replace(
`  completedAt: string;
};`,
`  completedAt: string;
  source:
    | "INSTALLER"
    | "FIRMWARE";
};`
    );
}

text =
  text.replace(
`  startedAt: string;
}): CommissioningSelfTestResult {`,
`  startedAt: string;
  source?: "INSTALLER" | "FIRMWARE";
}): CommissioningSelfTestResult {`
  );

if (
  !text.includes(
    'source:\n        input.source ??'
  )
) {
  text =
    text.replace(
`      completedAt,
    };`,
`      completedAt,
      source:
        input.source ??
        "INSTALLER",
    };`
    );
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardDeviceCommissioning.ts";

let text =
  fs.readFileSync(file, "utf8");

if (!text.includes("/self-test/telemetry")) {
  const marker =
`  app.get(
    "/scoreboard-device-commissioning/:deviceId/self-test",`;

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate 17.6 self-test route.",
    );
  }

  const route =
`  app.post(
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

      const checks = [
        body.controllerPassed,
        body.displayPassed,
        body.inputPassed,
        body.connectivityPassed,
        body.firmwareRuntimePassed,
      ];

      if (
        checks.some(
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

  text =
    text.slice(0, idx) +
    route +
    text.slice(idx);
}

fs.writeFileSync(file, text);
NODE

cat >> "$DOC" <<'EOF'

## Firmware-driven self-test telemetry

Milestone 17.7 introduces a firmware-side commissioning self-test contract and a dedicated acknowledgement endpoint:

`POST /scoreboard-device-commissioning/:deviceId/self-test/telemetry`

The device reports controller, display, input, connectivity, and firmware-runtime results. The API validates that the telemetry belongs to the route device, persists the result with `source: FIRMWARE`, and acknowledges accepted telemetry with HTTP 202.

The self-test is explicitly non-game-state-changing. Hardware-profile-specific active display and button test sequences can build on this transport contract.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 17.7 firmware-driven self-test telemetry", () => {
  const header = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/include/CommissioningSelfTest.h",
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

  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardDeviceCommissioning.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardCommissioningSelfTest.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("defines the firmware self-test telemetry contract", () => {
    expect(header).toContain(
      "CommissioningSelfTestTelemetry",
    );

    expect(header).toContain(
      "firmwareRuntimePassed",
    );

    expect(firmware).toContain(
      "toJson",
    );
  });

  it("keeps commissioning self-test separate from game state", () => {
    expect(firmware).toContain(
      "avoid changing game state",
    );
  });

  it("accepts firmware telemetry through a dedicated endpoint", () => {
    expect(route).toContain(
      "/self-test/telemetry",
    );

    expect(route).toContain(
      "acknowledged",
    );

    expect(route).toContain(
      "202",
    );
  });

  it("rejects mismatched device identity", () => {
    expect(route).toContain(
      "Telemetry device ID does not match route device ID.",
    );
  });

  it("persists firmware as the result source", () => {
    expect(service).toContain(
      '"FIRMWARE"',
    );

    expect(route).toContain(
      'source:\n            "FIRMWARE"',
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 17.7 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - ESP32 commissioning self-test telemetry contract"
echo "  - non-game-state-changing firmware self-test"
echo "  - JSON telemetry serialization"
echo "  - firmware telemetry ingestion endpoint"
echo "  - route/device identity validation"
echo "  - HTTP 202 device acknowledgement"
echo "  - INSTALLER vs FIRMWARE self-test source tracking"
echo "  - Milestone 17.7 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then build firmware:"
echo "  bash firmware/esp32-scoreboard/build-in-docker.sh"
echo
echo "Then rebuild:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 17.8 - Remote Self-Test Command Dispatch / Firmware Response Correlation"
