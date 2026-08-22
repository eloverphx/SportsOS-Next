#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="13.7-ota-update-reporting-deployment-status-api"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  echo "Expected: $EXPECTED_REAL" >&2
  echo "Received: $ROOT_REAL" >&2
  exit 1
fi

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/app.ts" \
  "$ROOT/apps/api/src/services/scoreboardDeviceEnrollment.ts" \
  "$ROOT/packages/core/src/scoreboard-firmware-update-contract.ts" \
  "$ROOT/firmware/esp32-scoreboard/include/FirmwareUpdateClient.h"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

SERVICE="apps/api/src/services/scoreboardFirmwareDeploymentStatus.ts"
ROUTE="apps/api/src/routes/scoreboardFirmwareDeploymentStatus.ts"
FW_H="firmware/esp32-scoreboard/include/FirmwareUpdateReporter.h"
FW_CPP="firmware/esp32-scoreboard/src/FirmwareUpdateReporter.cpp"
MAIN="firmware/esp32-scoreboard/src/main.cpp"
TEST="packages/core/test/ota-update-reporting-deployment-status-api-13.7.test.ts"

for file in "$SERVICE" "$ROUTE" "$FW_H" "$FW_CPP" "$MAIN" "$TEST" "apps/api/src/app.ts"; do
  if [[ -f "$file" ]]; then
    rel="${file#$ROOT/}"
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$file" "$BACKUP_DIR/$rel"
  fi
done

mkdir -p \
  "$(dirname "$SERVICE")" \
  "$(dirname "$ROUTE")" \
  "$(dirname "$FW_H")" \
  "$(dirname "$FW_CPP")" \
  "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

import type {
  ScoreboardFirmwareUpdateReport,
} from "@sportsos/core";

type DeploymentStore = {
  version: 1;
  reports: ScoreboardFirmwareUpdateReport[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(
    process.cwd(),
    "data",
  );

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-firmware-deployments.json",
  );

let store =
  loadStore();

function loadStore(): DeploymentStore {
  try {
    const parsed =
      JSON.parse(
        fs.readFileSync(
          STORE_FILE,
          "utf8",
        ),
      ) as DeploymentStore;

    if (
      parsed.version !== 1 ||
      !Array.isArray(
        parsed.reports,
      )
    ) {
      throw new Error(
        "Invalid deployment status store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      reports: [],
    };
  }
}

function persistStore(): void {
  fs.mkdirSync(
    DATA_DIR,
    {
      recursive: true,
    },
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

export function recordFirmwareDeploymentStatus(
  report: ScoreboardFirmwareUpdateReport,
): ScoreboardFirmwareUpdateReport {
  store.reports.push(
    report,
  );

  if (
    store.reports.length >
    1000
  ) {
    store.reports =
      store.reports.slice(
        -1000,
      );
  }

  persistStore();

  return report;
}

export function listFirmwareDeploymentReports(input?: {
  deviceId?: string;
  releaseId?: string;
}): ScoreboardFirmwareUpdateReport[] {
  return store.reports
    .filter(
      (report) =>
        (!input?.deviceId ||
          report.deviceId ===
            input.deviceId) &&
        (!input?.releaseId ||
          report.releaseId ===
            input.releaseId),
    )
    .sort(
      (a, b) =>
        b.reportedAt.localeCompare(
          a.reportedAt,
        ),
    );
}

export function getLatestFirmwareDeploymentStatus(
  deviceId: string,
): ScoreboardFirmwareUpdateReport | null {
  return (
    listFirmwareDeploymentReports({
      deviceId,
    })[0] ?? null
  );
}
EOF

cat > "$ROUTE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import type {
  ScoreboardFirmwareUpdateReport,
} from "@sportsos/core";

import {
  getLatestFirmwareDeploymentStatus,
  listFirmwareDeploymentReports,
  recordFirmwareDeploymentStatus,
} from "../services/scoreboardFirmwareDeploymentStatus.js";

import {
  isVerifiedDevice,
} from "../services/scoreboardDeviceEnrollment.js";

export async function registerScoreboardFirmwareDeploymentStatusRoutes(
  app: FastifyInstance,
) {
  app.post(
    "/scoreboard-firmware/deployments/report",
    async (request, reply) => {
      const body =
        request.body as ScoreboardFirmwareUpdateReport;

      if (
        !body?.deviceId ||
        !body?.releaseId ||
        !body?.targetVersion ||
        !body?.status ||
        !body?.reportedAt
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Invalid firmware deployment report.",
        });
      }

      if (
        !isVerifiedDevice(
          body.deviceId,
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Verified scoreboard device required.",
        });
      }

      return {
        success: true,
        data:
          recordFirmwareDeploymentStatus(
            body,
          ),
      };
    },
  );

  app.get(
    "/scoreboard-firmware/deployments",
    async (request) => {
      const query =
        request.query as {
          deviceId?: string;
          releaseId?: string;
        };

      return {
        success: true,
        data: {
          reports:
            listFirmwareDeploymentReports(
              query,
            ),
        },
      };
    },
  );

  app.get(
    "/scoreboard-firmware/deployments/:deviceId/latest",
    async (request) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      return {
        success: true,
        data:
          getLatestFirmwareDeploymentStatus(
            deviceId,
          ),
      };
    },
  );
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/app.ts";

let text =
  fs.readFileSync(file, "utf8");

const importLine =
  'import { registerScoreboardFirmwareDeploymentStatusRoutes } from "./routes/scoreboardFirmwareDeploymentStatus.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate app.ts import block.",
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
    "await registerScoreboardFirmwareDeploymentStatusRoutes(app);",
  )
) {
  const anchors = [
    "await registerScoreboardFirmwareArtifactRoutes(app);",
    "await registerScoreboardFirmwareReleaseRoutes(app);",
    "return app;",
  ];

  let patched = false;

  for (const anchor of anchors) {
    if (!text.includes(anchor)) {
      continue;
    }

    if (anchor === "return app;") {
      text =
        text.replace(
          anchor,
          "await registerScoreboardFirmwareDeploymentStatusRoutes(app);\n\n  " +
            anchor,
        );
    } else {
      text =
        text.replace(
          anchor,
          anchor +
            "\n  await registerScoreboardFirmwareDeploymentStatusRoutes(app);",
        );
    }

    patched = true;
    break;
  }

  if (!patched) {
    throw new Error(
      "Unable to locate API registration anchor.",
    );
  }
}

fs.writeFileSync(file, text);
NODE

cat > "$FW_H" <<'EOF'
#pragma once

#include <Arduino.h>

#include "FirmwareUpdateContract.h"

namespace sportsos {

struct FirmwareUpdateReporterConfig {
  const char* apiBaseUrl;
  const char* deviceId;
  const char* currentVersion;
};

class FirmwareUpdateReporter {
 public:
  explicit FirmwareUpdateReporter(
      const FirmwareUpdateReporterConfig& config);

  bool report(
      const FirmwareUpdateOffer& offer,
      FirmwareUpdateState state,
      int progressPercent,
      const char* error);

 private:
  FirmwareUpdateReporterConfig config_;

  static const char* stateText(
      FirmwareUpdateState state);
};

}  // namespace sportsos
EOF

cat > "$FW_CPP" <<'EOF'
#include "FirmwareUpdateReporter.h"

#include <ArduinoJson.h>
#include <HTTPClient.h>

namespace sportsos {

FirmwareUpdateReporter::FirmwareUpdateReporter(
    const FirmwareUpdateReporterConfig& config)
    : config_(config) {}

bool FirmwareUpdateReporter::report(
    const FirmwareUpdateOffer& offer,
    FirmwareUpdateState state,
    int progressPercent,
    const char* error) {
  HTTPClient http;

  const String url =
      String(config_.apiBaseUrl) +
      "/scoreboard-firmware/deployments/report";

  if (!http.begin(url)) {
    return false;
  }

  http.addHeader(
      "Content-Type",
      "application/json");

  JsonDocument document;

  document["deviceId"] =
      config_.deviceId;

  document["releaseId"] =
      offer.releaseId;

  document["previousVersion"] =
      config_.currentVersion;

  document["targetVersion"] =
      offer.version;

  document["status"] =
      stateText(state);

  if (
      progressPercent >= 0
  ) {
    document["progressPercent"] =
        progressPercent;
  } else {
    document["progressPercent"] =
        nullptr;
  }

  document["error"] =
      error &&
      error[0] != '\0'
        ? error
        : nullptr;

  document["reportedAt"] =
      String(
          millis());

  String payload;

  serializeJson(
      document,
      payload);

  const int status =
      http.POST(
          payload);

  http.end();

  return
      status >= 200 &&
      status < 300;
}

const char*
FirmwareUpdateReporter::stateText(
    FirmwareUpdateState state) {
  return
      FirmwareUpdateContract::stateText(
          state);
}

}  // namespace sportsos
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "firmware/esp32-scoreboard/src/main.cpp";

let text =
  fs.readFileSync(file, "utf8");

if (
  !text.includes(
    '#include "FirmwareUpdateReporter.h"',
  )
) {
  const anchor =
    '#include "FirmwareUpdateClient.h"';

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate firmware update include.",
    );
  }

  text =
    text.replace(
      anchor,
      anchor +
        '\n#include "FirmwareUpdateReporter.h"',
    );
}

if (
  !text.includes(
    "using sportsos::FirmwareUpdateReporter;",
  )
) {
  const matches =
    [...text.matchAll(/^using sportsos::.*?;$/gm)];

  if (matches.length === 0) {
    throw new Error(
      "Unable to locate using declarations.",
    );
  }

  const last =
    matches[matches.length - 1];

  const insertAt =
    last.index +
    last[0].length;

  text =
    text.slice(0, insertAt) +
    "\nusing sportsos::FirmwareUpdateReporter;" +
    "\nusing sportsos::FirmwareUpdateReporterConfig;" +
    text.slice(insertAt);
}

if (
  !text.includes(
    "FirmwareUpdateReporter* firmwareUpdateReporter",
  )
) {
  const anchor =
    "FirmwareUpdateClient* firmwareUpdateClient";

  const idx =
    text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate firmwareUpdateClient declaration.",
    );
  }

  const end =
    text.indexOf(";", idx);

  if (end === -1) {
    throw new Error(
      "Unable to locate firmwareUpdateClient declaration end.",
    );
  }

  text =
    text.slice(0, end + 1) +
    `

FirmwareUpdateReporter* firmwareUpdateReporter =
    nullptr;` +
    text.slice(end + 1);
}

if (
  !text.includes(
    "FirmwareUpdateReporterConfig reporterConfig",
  )
) {
  const anchor =
    "firmwareUpdateClient->begin();";

  const idx =
    text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate firmwareUpdateClient->begin().",
    );
  }

  const insertAt =
    idx +
    anchor.length;

  text =
    text.slice(0, insertAt) +
    `

  FirmwareUpdateReporterConfig
      reporterConfig{
          SPORTSOS_API_BASE_URL,
          persistedConfig.deviceId.c_str(),
          SPORTSOS_FIRMWARE_VERSION,
      };

  firmwareUpdateReporter =
      new FirmwareUpdateReporter(
          reporterConfig);` +
    text.slice(insertAt);
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

describe("Milestone 13.7 OTA update reporting / deployment status API", () => {
  it("persists deployment reports", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardFirmwareDeploymentStatus.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "scoreboard-firmware-deployments.json",
    );

    expect(service).toContain(
      "recordFirmwareDeploymentStatus",
    );
  });

  it("exposes report, history, and latest endpoints", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareDeploymentStatus.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/deployments/report",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/deployments",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/deployments/:deviceId/latest",
    );
  });

  it("requires verified device identity for update reports", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareDeploymentStatus.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "isVerifiedDevice",
    );

    expect(routes).toContain(
      "Verified scoreboard device required.",
    );
  });

  it("defines ESP32 firmware update reporter", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/FirmwareUpdateReporter.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "FirmwareUpdateReporter",
    );

    expect(header).toContain(
      "FirmwareUpdateState",
    );
  });

  it("posts deployment status to SportsOS API", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareUpdateReporter.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "/scoreboard-firmware/deployments/report",
    );

    expect(source).toContain(
      "progressPercent",
    );

    expect(source).toContain(
      "targetVersion",
    );
  });

  it("registers deployment status routes in API app", () => {
    const app = fs.readFileSync(
      new URL(
        "../../../apps/api/src/app.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(app).toContain(
      "registerScoreboardFirmwareDeploymentStatusRoutes",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 13.7 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - persistent OTA deployment status registry"
echo "  - device update report API"
echo "  - deployment history API"
echo "  - latest-per-device status API"
echo "  - verified-device reporting gate"
echo "  - ESP32 FirmwareUpdateReporter"
echo "  - progress/error reporting contract"
echo "  - Milestone 13.7 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then rebuild API:"
echo "  docker compose up -d --build api"
echo
echo "Next after green:"
echo "  Milestone 13.8 - Firmware Fleet Operations Dashboard"
