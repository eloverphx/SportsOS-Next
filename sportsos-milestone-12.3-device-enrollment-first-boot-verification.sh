#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="12.3-device-enrollment-first-boot-verification"
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
  "$ROOT/apps/api/src" \
  "$ROOT/apps/dashboard" \
  "$ROOT/firmware/esp32-scoreboard"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

API_SERVICE="apps/api/src/services/scoreboardDeviceEnrollment.ts"
API_ROUTE="apps/api/src/routes/scoreboardDeviceEnrollment.ts"
FW_H="firmware/esp32-scoreboard/include/DeviceEnrollment.h"
FW_CPP="firmware/esp32-scoreboard/src/DeviceEnrollment.cpp"
PAGE="apps/dashboard/app/scoreboards/enrollment/page.tsx"
README="firmware/esp32-scoreboard/README.md"
TEST="packages/core/test/device-enrollment-first-boot-12.3.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$API_SERVICE")" \
  "$BACKUP_DIR/$(dirname "$API_ROUTE")" \
  "$BACKUP_DIR/$(dirname "$FW_H")" \
  "$BACKUP_DIR/$(dirname "$FW_CPP")" \
  "$BACKUP_DIR/$(dirname "$PAGE")" \
  "$BACKUP_DIR/$(dirname "$README")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$API_SERVICE")" \
  "$(dirname "$API_ROUTE")" \
  "$(dirname "$FW_H")" \
  "$(dirname "$FW_CPP")" \
  "$(dirname "$PAGE")" \
  "$(dirname "$TEST")"

for file in "$API_SERVICE" "$API_ROUTE" "$FW_H" "$FW_CPP" "$PAGE" "$README" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$API_SERVICE" <<'EOF'
export type EnrollmentStatus =
  | "UNENROLLED"
  | "PENDING"
  | "VERIFIED"
  | "REJECTED";

export type ScoreboardEnrollmentRecord = {
  deviceId: string;
  firmwareVersion: string;
  chipId: string;
  status: EnrollmentStatus;
  firstSeenAt: string;
  lastSeenAt: string;
  verifiedAt: string | null;
};

const records = new Map<
  string,
  ScoreboardEnrollmentRecord
>();

export function registerFirstBoot(input: {
  deviceId: string;
  firmwareVersion: string;
  chipId: string;
}): ScoreboardEnrollmentRecord {
  const now = new Date().toISOString();

  const existing =
    records.get(input.deviceId);

  if (existing) {
    const updated = {
      ...existing,
      firmwareVersion:
        input.firmwareVersion,
      chipId:
        input.chipId,
      lastSeenAt:
        now,
    };

    records.set(
      input.deviceId,
      updated,
    );

    return updated;
  }

  const created: ScoreboardEnrollmentRecord = {
    deviceId:
      input.deviceId,
    firmwareVersion:
      input.firmwareVersion,
    chipId:
      input.chipId,
    status:
      "PENDING",
    firstSeenAt:
      now,
    lastSeenAt:
      now,
    verifiedAt:
      null,
  };

  records.set(
    input.deviceId,
    created,
  );

  return created;
}

export function verifyEnrollment(
  deviceId: string,
): ScoreboardEnrollmentRecord | null {
  const record =
    records.get(deviceId);

  if (!record) {
    return null;
  }

  const now =
    new Date().toISOString();

  const updated = {
    ...record,
    status:
      "VERIFIED" as const,
    verifiedAt:
      now,
    lastSeenAt:
      now,
  };

  records.set(
    deviceId,
    updated,
  );

  return updated;
}

export function rejectEnrollment(
  deviceId: string,
): ScoreboardEnrollmentRecord | null {
  const record =
    records.get(deviceId);

  if (!record) {
    return null;
  }

  const updated = {
    ...record,
    status:
      "REJECTED" as const,
    lastSeenAt:
      new Date().toISOString(),
  };

  records.set(
    deviceId,
    updated,
  );

  return updated;
}

export function getEnrollment(
  deviceId: string,
): ScoreboardEnrollmentRecord | null {
  return records.get(deviceId) ?? null;
}

export function listEnrollments():
  ScoreboardEnrollmentRecord[] {
  return [...records.values()].sort(
    (a, b) =>
      b.lastSeenAt.localeCompare(
        a.lastSeenAt,
      ),
  );
}
EOF

cat > "$API_ROUTE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import {
  getEnrollment,
  listEnrollments,
  registerFirstBoot,
  rejectEnrollment,
  verifyEnrollment,
} from "../services/scoreboardDeviceEnrollment.js";

type FirstBootBody = {
  deviceId?: string;
  firmwareVersion?: string;
  chipId?: string;
};

export async function registerScoreboardDeviceEnrollmentRoutes(
  app: FastifyInstance,
) {
  app.get(
    "/scoreboard-devices/enrollment",
    async () => ({
      success: true,
      data: {
        devices:
          listEnrollments(),
      },
    }),
  );

  app.get(
    "/scoreboard-devices/enrollment/:deviceId",
    async (request, reply) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      const record =
        getEnrollment(deviceId);

      if (!record) {
        return reply.code(404).send({
          success: false,
          error:
            "Enrollment record not found.",
        });
      }

      return {
        success: true,
        data: record,
      };
    },
  );

  app.post(
    "/scoreboard-devices/enrollment/first-boot",
    async (request, reply) => {
      const body =
        request.body as FirstBootBody;

      if (
        !body?.deviceId ||
        !body?.firmwareVersion ||
        !body?.chipId
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "deviceId, firmwareVersion and chipId are required.",
        });
      }

      const record =
        registerFirstBoot({
          deviceId:
            body.deviceId,
          firmwareVersion:
            body.firmwareVersion,
          chipId:
            body.chipId,
        });

      return reply.code(201).send({
        success: true,
        data: record,
      });
    },
  );

  app.post(
    "/scoreboard-devices/enrollment/:deviceId/verify",
    async (request, reply) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      const record =
        verifyEnrollment(deviceId);

      if (!record) {
        return reply.code(404).send({
          success: false,
          error:
            "Enrollment record not found.",
        });
      }

      return {
        success: true,
        data: record,
      };
    },
  );

  app.post(
    "/scoreboard-devices/enrollment/:deviceId/reject",
    async (request, reply) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      const record =
        rejectEnrollment(deviceId);

      if (!record) {
        return reply.code(404).send({
          success: false,
          error:
            "Enrollment record not found.",
        });
      }

      return {
        success: true,
        data: record,
      };
    },
  );
}
EOF

cat > "$FW_H" <<'EOF'
#pragma once

#include <Arduino.h>

namespace sportsos {

struct DeviceEnrollmentIdentity {
  char deviceId[64];
  char firmwareVersion[32];
  char chipId[32];
};

class DeviceEnrollment {
 public:
  static DeviceEnrollmentIdentity buildIdentity(
      const char* deviceId);

  static String buildFirstBootJson(
      const DeviceEnrollmentIdentity& identity);
};

}  // namespace sportsos
EOF

cat > "$FW_CPP" <<'EOF'
#include "DeviceEnrollment.h"

#include <ArduinoJson.h>
#include <stdio.h>
#include <string.h>

namespace sportsos {

namespace {

void copyText(
    char* destination,
    size_t destinationSize,
    const char* source) {
  if (
      destination == nullptr ||
      destinationSize == 0
  ) {
    return;
  }

  if (source == nullptr) {
    destination[0] = '\0';
    return;
  }

  strncpy(
      destination,
      source,
      destinationSize - 1);

  destination[
      destinationSize - 1] = '\0';
}

}  // namespace

DeviceEnrollmentIdentity
DeviceEnrollment::buildIdentity(
    const char* deviceId) {
  DeviceEnrollmentIdentity identity{};

  copyText(
      identity.deviceId,
      sizeof(identity.deviceId),
      deviceId);

  copyText(
      identity.firmwareVersion,
      sizeof(identity.firmwareVersion),
      SPORTSOS_FIRMWARE_VERSION);

  const uint64_t chipId =
      ESP.getEfuseMac();

  snprintf(
      identity.chipId,
      sizeof(identity.chipId),
      "%012llX",
      chipId);

  return identity;
}

String DeviceEnrollment::buildFirstBootJson(
    const DeviceEnrollmentIdentity& identity) {
  JsonDocument document;

  document["deviceId"] =
      identity.deviceId;

  document["firmwareVersion"] =
      identity.firmwareVersion;

  document["chipId"] =
      identity.chipId;

  String json;

  serializeJson(
      document,
      json);

  return json;
}

}  // namespace sportsos
EOF

cat > "$PAGE" <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
  useState,
} from "react";

type EnrollmentRecord = {
  deviceId: string;
  firmwareVersion: string;
  chipId: string;
  status:
    | "UNENROLLED"
    | "PENDING"
    | "VERIFIED"
    | "REJECTED";
  firstSeenAt: string;
  lastSeenAt: string;
  verifiedAt: string | null;
};

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

export default function ScoreboardEnrollmentPage() {
  const [
    devices,
    setDevices,
  ] = useState<EnrollmentRecord[]>(
    [],
  );

  const [
    loading,
    setLoading,
  ] = useState(true);

  const load = useCallback(
    async () => {
      setLoading(true);

      try {
        const response =
          await fetch(
            `${API_BASE}/scoreboard-devices/enrollment`,
            {
              cache: "no-store",
            },
          );

        const json =
          await response.json();

        setDevices(
          json?.data?.devices ?? [],
        );
      } finally {
        setLoading(false);
      }
    },
    [],
  );

  useEffect(() => {
    void load();
  }, [load]);

  const act = async (
    deviceId: string,
    action: "verify" | "reject",
  ) => {
    await fetch(
      `${API_BASE}/scoreboard-devices/enrollment/${encodeURIComponent(
        deviceId,
      )}/${action}`,
      {
        method: "POST",
      },
    );

    await load();
  };

  return (
    <main className="mx-auto max-w-6xl p-6">
      <div className="mb-6">
        <h1 className="text-3xl font-bold">
          Scoreboard Enrollment
        </h1>
        <p className="mt-2 text-slate-400">
          Verify newly flashed ESP32 scoreboard devices before
          assigning them to live games.
        </p>
      </div>

      {loading ? (
        <p className="text-slate-400">
          Loading devices…
        </p>
      ) : devices.length === 0 ? (
        <div className="rounded-xl border border-slate-800 p-6">
          <p className="text-slate-300">
            No first-boot enrollment requests yet.
          </p>
        </div>
      ) : (
        <div className="space-y-4">
          {devices.map((device) => (
            <div
              key={device.deviceId}
              className="rounded-xl border border-slate-800 p-5"
            >
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div>
                  <h2 className="text-xl font-semibold">
                    {device.deviceId}
                  </h2>
                  <div className="mt-2 space-y-1 text-sm text-slate-400">
                    <p>
                      Firmware: {device.firmwareVersion}
                    </p>
                    <p>
                      Chip ID: {device.chipId}
                    </p>
                    <p>
                      Status: {device.status}
                    </p>
                  </div>
                </div>

                {device.status === "PENDING" && (
                  <div className="flex gap-2">
                    <button
                      type="button"
                      onClick={() =>
                        void act(
                          device.deviceId,
                          "verify",
                        )
                      }
                      className="rounded-lg border border-slate-600 px-4 py-2"
                    >
                      Verify
                    </button>
                    <button
                      type="button"
                      onClick={() =>
                        void act(
                          device.deviceId,
                          "reject",
                        )
                      }
                      className="rounded-lg border border-slate-600 px-4 py-2"
                    >
                      Reject
                    </button>
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </main>
  );
}
EOF

node <<'NODE'
const fs = require("fs");
const path = "apps/api/src/app.ts";

if (!fs.existsSync(path)) {
  throw new Error("apps/api/src/app.ts not found.");
}

let text = fs.readFileSync(path, "utf8");

const importLine =
  'import { registerScoreboardDeviceEnrollmentRoutes } from "./routes/scoreboardDeviceEnrollment.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error("Unable to locate app.ts import block.");
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
    "registerScoreboardDeviceEnrollmentRoutes",
  ) ||
  !text.includes(
    "await registerScoreboardDeviceEnrollmentRoutes(app)",
  )
) {
  const candidates = [
    "await registerScoreboardDeviceRoutes(app);",
    "await registerRoutes(app);",
  ];

  let patched = false;

  for (const anchor of candidates) {
    if (text.includes(anchor)) {
      text =
        text.replace(
          anchor,
          anchor +
            "\n  await registerScoreboardDeviceEnrollmentRoutes(app);",
        );

      patched = true;
      break;
    }
  }

  if (!patched) {
    const listenAnchor =
      "return app;";

    if (!text.includes(listenAnchor)) {
      throw new Error(
        "Unable to locate API route-registration anchor.",
      );
    }

    text =
      text.replace(
        listenAnchor,
        "await registerScoreboardDeviceEnrollmentRoutes(app);\n\n  " +
          listenAnchor,
      );
  }
}

fs.writeFileSync(path, text);
NODE

cat >> "$README" <<'EOF'

## Milestone 12.3 — Device enrollment / first-boot verification

Newly flashed scoreboard devices now have a first-boot identity contract.

The firmware identity contains:

- device ID
- firmware version
- ESP32 chip ID

The API exposes enrollment endpoints:

- `GET /scoreboard-devices/enrollment`
- `GET /scoreboard-devices/enrollment/:deviceId`
- `POST /scoreboard-devices/enrollment/first-boot`
- `POST /scoreboard-devices/enrollment/:deviceId/verify`
- `POST /scoreboard-devices/enrollment/:deviceId/reject`

The dashboard includes:

`/scoreboards/enrollment`

A newly flashed scoreboard should remain `PENDING` until an operator confirms the expected device ID and chip ID.

Verified devices can then proceed to game assignment and normal scoreboard operations.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.3 scoreboard enrollment", () => {
  it("defines first-boot firmware identity", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/DeviceEnrollment.h",
        import.meta.url,
      ),
      "utf8",
    );

    for (const field of [
      "deviceId",
      "firmwareVersion",
      "chipId",
    ]) {
      expect(header).toContain(field);
    }
  });

  it("derives chip identity from the ESP32", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/DeviceEnrollment.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "ESP.getEfuseMac",
    );

    expect(source).toContain(
      "SPORTSOS_FIRMWARE_VERSION",
    );
  });

  it("defines server enrollment states", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    for (const state of [
      "UNENROLLED",
      "PENDING",
      "VERIFIED",
      "REJECTED",
    ]) {
      expect(service).toContain(state);
    }
  });

  it("defines first-boot verify and reject endpoints", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/scoreboard-devices/enrollment/first-boot",
    );

    expect(routes).toContain(
      "/scoreboard-devices/enrollment/:deviceId/verify",
    );

    expect(routes).toContain(
      "/scoreboard-devices/enrollment/:deviceId/reject",
    );
  });

  it("adds an enrollment dashboard page", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/enrollment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Scoreboard Enrollment",
    );

    expect(page).toContain(
      "Verify",
    );

    expect(page).toContain(
      "Reject",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 12.3 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - first-boot firmware identity"
echo "  - ESP32 chip ID reporting"
echo "  - enrollment service"
echo "  - PENDING / VERIFIED / REJECTED states"
echo "  - first-boot enrollment API"
echo "  - verify/reject API operations"
echo "  - /scoreboards/enrollment dashboard"
echo "  - Milestone 12.3 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then rebuild API/dashboard:"
echo "  docker compose up -d --build api dashboard"
echo
echo "Next after green:"
echo "  Milestone 12.4 - Enrollment Persistence / Device Claim Security"
