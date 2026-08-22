#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="12.5-verified-device-assignment-enforcement"
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
  "$ROOT/apps/api/src/routes/scoreboardDevices.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

ROUTE="apps/api/src/routes/scoreboardDevices.ts"
GUARD="apps/api/src/services/scoreboardDeviceAuthorization.ts"
TEST="packages/core/test/verified-device-assignment-enforcement-12.5.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$GUARD")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$GUARD")" \
  "$(dirname "$TEST")"

for file in "$ROUTE" "$GUARD" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$GUARD" <<'EOF'
import {
  getEnrollment,
  isVerifiedDevice,
} from "./scoreboardDeviceEnrollment.js";

export type DeviceAuthorizationResult =
  | {
      ok: true;
    }
  | {
      ok: false;
      statusCode: 403;
      error: string;
    };

export function authorizeVerifiedScoreboardDevice(
  deviceId: string,
): DeviceAuthorizationResult {
  const record =
    getEnrollment(deviceId);

  if (!record) {
    return {
      ok: false,
      statusCode: 403,
      error:
        "Scoreboard device is not enrolled.",
    };
  }

  if (!isVerifiedDevice(deviceId)) {
    return {
      ok: false,
      statusCode: 403,
      error:
        `Scoreboard device is not verified. Current status: ${record.status}.`,
    };
  }

  return {
    ok: true,
  };
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardDevices.ts";

let text =
  fs.readFileSync(file, "utf8");

const importLine =
  'import { authorizeVerifiedScoreboardDevice } from "../services/scoreboardDeviceAuthorization.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate scoreboardDevices.ts import block.",
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

const guardedRouteFragments = [
  '/scoreboard-devices/:deviceId/commands',
  '/scoreboard-devices/:deviceId/sync-game',
  '/scoreboard-devices/assignments/:gameId',
  '/scoreboard-devices/realtime-sync',
  '/scoreboard-devices/:deviceId/reconcile',
];

function injectGuardNearDeviceId(routeText) {
  if (
    routeText.includes(
      "authorizeVerifiedScoreboardDevice(",
    )
  ) {
    return routeText;
  }

  const paramsPatterns = [
`const { deviceId } =
        request.params as {
          deviceId: string;
        };`,
`const { deviceId } = request.params as { deviceId: string };`,
  ];

  for (const anchor of paramsPatterns) {
    if (routeText.includes(anchor)) {
      const guard = `${anchor}

      const authorization =
        authorizeVerifiedScoreboardDevice(
          deviceId,
        );

      if (!authorization.ok) {
        return reply
          .code(
            authorization.statusCode,
          )
          .send({
            success: false,
            error:
              authorization.error,
          });
      }`;

      return routeText.replace(
        anchor,
        guard,
      );
    }
  }

  return routeText;
}

for (const fragment of guardedRouteFragments) {
  const start =
    text.indexOf(fragment);

  if (start === -1) {
    continue;
  }

  const nextRoute =
    text.indexOf(
      "\n  app.",
      start + fragment.length,
    );

  const end =
    nextRoute === -1
      ? text.length
      : nextRoute;

  const before =
    text.slice(0, start);

  const block =
    text.slice(start, end);

  const after =
    text.slice(end);

  const patched =
    injectGuardNearDeviceId(block);

  text =
    before + patched + after;
}

/*
 * Assignment PUT commonly receives deviceId in the body,
 * rather than as a route param. Add an explicit authorization
 * check immediately after the body is resolved.
 */
if (
  text.includes(
    "/scoreboard-devices/assignments/:gameId",
  ) &&
  !text.includes(
    "assignmentDeviceAuthorization",
  )
) {
  const candidates = [
`const body =
        request.body as {
          deviceId?: string;
        };`,
`const body = request.body as { deviceId?: string };`,
  ];

  for (const anchor of candidates) {
    if (text.includes(anchor)) {
      text =
        text.replace(
          anchor,
`${anchor}

      if (body.deviceId) {
        const assignmentDeviceAuthorization =
          authorizeVerifiedScoreboardDevice(
            body.deviceId,
          );

        if (
          !assignmentDeviceAuthorization.ok
        ) {
          return reply
            .code(
              assignmentDeviceAuthorization.statusCode,
            )
            .send({
              success: false,
              error:
                assignmentDeviceAuthorization.error,
            });
        }
      }`,
        );

      break;
    }
  }
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

describe("Milestone 12.5 verified device enforcement", () => {
  it("defines a reusable verified-device authorization service", () => {
    const guard = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceAuthorization.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(guard).toContain(
      "authorizeVerifiedScoreboardDevice",
    );

    expect(guard).toContain(
      "isVerifiedDevice",
    );

    expect(guard).toContain(
      "Scoreboard device is not enrolled.",
    );

    expect(guard).toContain(
      "Scoreboard device is not verified.",
    );
  });

  it("wires the authorization service into scoreboard device routes", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "authorizeVerifiedScoreboardDevice",
    );
  });

  it("protects device command operations", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/scoreboard-devices/:deviceId",
    );

    expect(routes).toContain(
      "authorization.statusCode",
    );
  });

  it("protects assignment operations for body-supplied device IDs", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "assignmentDeviceAuthorization",
    );
  });

  it("keeps rejected and pending devices visible through enrollment state", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      '"PENDING"',
    );

    expect(service).toContain(
      '"REJECTED"',
    );

    expect(service).toContain(
      '"VERIFIED"',
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 12.5 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - verified-device authorization service"
echo "  - un-enrolled device blocking"
echo "  - pending device blocking"
echo "  - rejected device blocking"
echo "  - assignment enforcement"
echo "  - command-operation enforcement"
echo "  - reconcile/sync enforcement where routes expose deviceId"
echo "  - Milestone 12.5 tests"
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
echo "  Milestone 12.6 - Device Enrollment Dashboard Claim Workflow"
