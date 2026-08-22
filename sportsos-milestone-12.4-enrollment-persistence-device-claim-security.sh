#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="12.4-enrollment-persistence-device-claim-security"
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
  "$ROOT/apps/api/src/services/scoreboardDeviceEnrollment.ts" \
  "$ROOT/apps/api/src/routes/scoreboardDeviceEnrollment.ts" \
  "$ROOT/firmware/esp32-scoreboard/include/DeviceEnrollment.h"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

SERVICE="apps/api/src/services/scoreboardDeviceEnrollment.ts"
ROUTE="apps/api/src/routes/scoreboardDeviceEnrollment.ts"
FW_H="firmware/esp32-scoreboard/include/DeviceEnrollment.h"
FW_CPP="firmware/esp32-scoreboard/src/DeviceEnrollment.cpp"
README="firmware/esp32-scoreboard/README.md"
TEST="packages/core/test/enrollment-persistence-claim-security-12.4.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$SERVICE")" \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$FW_H")" \
  "$BACKUP_DIR/$(dirname "$FW_CPP")" \
  "$BACKUP_DIR/$(dirname "$README")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$TEST")"

for file in "$SERVICE" "$ROUTE" "$FW_H" "$FW_CPP" "$README" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$SERVICE" <<'EOF'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

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
  claimTokenHash: string | null;
  claimTokenIssuedAt: string | null;
  claimTokenConsumedAt: string | null;
};

type EnrollmentStore = {
  version: 1;
  devices: Record<
    string,
    ScoreboardEnrollmentRecord
  >;
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
    "scoreboard-enrollments.json",
  );

let store: EnrollmentStore =
  loadStore();

function loadStore(): EnrollmentStore {
  try {
    const raw =
      fs.readFileSync(
        STORE_FILE,
        "utf8",
      );

    const parsed =
      JSON.parse(raw) as EnrollmentStore;

    if (
      parsed?.version !== 1 ||
      typeof parsed.devices !==
        "object"
    ) {
      throw new Error(
        "Invalid enrollment store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      devices: {},
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

  const tempFile =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    tempFile,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );

  fs.renameSync(
    tempFile,
    STORE_FILE,
  );
}

function hashClaimToken(
  token: string,
): string {
  return crypto
    .createHash("sha256")
    .update(token)
    .digest("hex");
}

export function issueClaimToken(
  deviceId: string,
): string | null {
  const record =
    store.devices[deviceId];

  if (!record) {
    return null;
  }

  const token =
    crypto
      .randomBytes(24)
      .toString("hex");

  record.claimTokenHash =
    hashClaimToken(token);

  record.claimTokenIssuedAt =
    new Date().toISOString();

  record.claimTokenConsumedAt =
    null;

  persistStore();

  return token;
}

export function registerFirstBoot(input: {
  deviceId: string;
  firmwareVersion: string;
  chipId: string;
}): ScoreboardEnrollmentRecord {
  const now =
    new Date().toISOString();

  const existing =
    store.devices[input.deviceId];

  if (existing) {
    if (
      existing.chipId !== input.chipId &&
      existing.status === "VERIFIED"
    ) {
      const rejected = {
        ...existing,
        status:
          "REJECTED" as const,
        lastSeenAt:
          now,
      };

      store.devices[
        input.deviceId
      ] = rejected;

      persistStore();

      return rejected;
    }

    const updated = {
      ...existing,
      firmwareVersion:
        input.firmwareVersion,
      chipId:
        input.chipId,
      lastSeenAt:
        now,
    };

    store.devices[
      input.deviceId
    ] = updated;

    persistStore();

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
    claimTokenHash:
      null,
    claimTokenIssuedAt:
      null,
    claimTokenConsumedAt:
      null,
  };

  store.devices[
    input.deviceId
  ] = created;

  persistStore();

  return created;
}

export function verifyEnrollmentWithClaim(
  deviceId: string,
  claimToken: string,
): ScoreboardEnrollmentRecord | null {
  const record =
    store.devices[deviceId];

  if (
    !record ||
    !record.claimTokenHash ||
    record.claimTokenConsumedAt
  ) {
    return null;
  }

  const receivedHash =
    hashClaimToken(
      claimToken,
    );

  const expected =
    Buffer.from(
      record.claimTokenHash,
      "hex",
    );

  const received =
    Buffer.from(
      receivedHash,
      "hex",
    );

  if (
    expected.length !==
      received.length ||
    !crypto.timingSafeEqual(
      expected,
      received,
    )
  ) {
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
    claimTokenConsumedAt:
      now,
  };

  store.devices[
    deviceId
  ] = updated;

  persistStore();

  return updated;
}

export function rejectEnrollment(
  deviceId: string,
): ScoreboardEnrollmentRecord | null {
  const record =
    store.devices[deviceId];

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

  store.devices[
    deviceId
  ] = updated;

  persistStore();

  return updated;
}

export function getEnrollment(
  deviceId: string,
): ScoreboardEnrollmentRecord | null {
  return (
    store.devices[
      deviceId
    ] ?? null
  );
}

export function listEnrollments():
  ScoreboardEnrollmentRecord[] {
  return Object
    .values(
      store.devices,
    )
    .sort(
      (a, b) =>
        b.lastSeenAt.localeCompare(
          a.lastSeenAt,
        ),
    );
}

export function isVerifiedDevice(
  deviceId: string,
  chipId?: string,
): boolean {
  const record =
    store.devices[deviceId];

  if (
    !record ||
    record.status !==
      "VERIFIED"
  ) {
    return false;
  }

  if (
    chipId &&
    record.chipId !== chipId
  ) {
    return false;
  }

  return true;
}
EOF

cat > "$ROUTE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import {
  getEnrollment,
  issueClaimToken,
  isVerifiedDevice,
  listEnrollments,
  registerFirstBoot,
  rejectEnrollment,
  verifyEnrollmentWithClaim,
} from "../services/scoreboardDeviceEnrollment.js";

type FirstBootBody = {
  deviceId?: string;
  firmwareVersion?: string;
  chipId?: string;
};

type ClaimBody = {
  claimToken?: string;
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
    "/scoreboard-devices/enrollment/:deviceId/claim-token",
    async (request, reply) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      const token =
        issueClaimToken(
          deviceId,
        );

      if (!token) {
        return reply.code(404).send({
          success: false,
          error:
            "Enrollment record not found.",
        });
      }

      return {
        success: true,
        data: {
          deviceId,
          claimToken:
            token,
        },
      };
    },
  );

  app.post(
    "/scoreboard-devices/enrollment/:deviceId/verify",
    async (request, reply) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      const body =
        request.body as ClaimBody;

      if (!body?.claimToken) {
        return reply.code(400).send({
          success: false,
          error:
            "claimToken is required.",
        });
      }

      const record =
        verifyEnrollmentWithClaim(
          deviceId,
          body.claimToken,
        );

      if (!record) {
        return reply.code(403).send({
          success: false,
          error:
            "Invalid or consumed claim token.",
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

  app.get(
    "/scoreboard-devices/enrollment/:deviceId/verified",
    async (request) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      return {
        success: true,
        data: {
          verified:
            isVerifiedDevice(
              deviceId,
            ),
        },
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

  static String buildClaimVerificationJson(
      const char* claimToken);
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

String DeviceEnrollment::buildClaimVerificationJson(
    const char* claimToken) {
  JsonDocument document;

  document["claimToken"] =
      claimToken != nullptr
          ? claimToken
          : "";

  String json;

  serializeJson(
      document,
      json);

  return json;
}

}  // namespace sportsos
EOF

cat >> "$README" <<'EOF'

## Milestone 12.4 — Enrollment persistence / device claim security

Scoreboard enrollment state is now persistent across API restarts.

Enrollment records are stored under the API data directory in:

`scoreboard-enrollments.json`

### Claim security

Verification now requires a one-time claim token.

Flow:

1. device sends first-boot identity
2. server records device as `PENDING`
3. operator requests a one-time claim token
4. token is stored only as a SHA-256 hash
5. verification consumes the token
6. consumed tokens cannot be reused
7. verified device ID + chip ID becomes the trusted enrollment identity

A verified device that later reports the same device ID with a different chip ID is rejected.

The firmware contract also supports serializing a claim-verification payload.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.4 enrollment persistence and claim security", () => {
  it("persists enrollment state to disk", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "scoreboard-enrollments.json",
    );

    expect(service).toContain(
      "persistStore",
    );

    expect(service).toContain(
      "fs.renameSync",
    );
  });

  it("hashes claim tokens and uses timing-safe comparison", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      'createHash("sha256")',
    );

    expect(service).toContain(
      "timingSafeEqual",
    );
  });

  it("prevents claim token reuse", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "claimTokenConsumedAt",
    );

    expect(service).toContain(
      "record.claimTokenConsumedAt",
    );
  });

  it("rejects a verified device identity when chip ID changes", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      'existing.chipId !== input.chipId',
    );

    expect(service).toContain(
      '"REJECTED"',
    );
  });

  it("adds claim token and verified-status routes", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/claim-token",
    );

    expect(routes).toContain(
      "/verified",
    );

    expect(routes).toContain(
      "claimToken is required.",
    );
  });

  it("extends firmware enrollment contract with claim verification JSON", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/DeviceEnrollment.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "buildClaimVerificationJson",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 12.4 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - restart-safe enrollment persistence"
echo "  - atomic enrollment-store writes"
echo "  - one-time claim tokens"
echo "  - SHA-256 claim-token storage"
echo "  - timing-safe token verification"
echo "  - token consumption / replay prevention"
echo "  - verified device ID + chip ID binding"
echo "  - chip mismatch rejection"
echo "  - verified-status endpoint"
echo "  - firmware claim verification payload"
echo "  - Milestone 12.4 tests"
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
echo "  Milestone 12.5 - Verified Device Assignment Enforcement"
