#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="12.10-device-lifecycle-deployment-closeout"
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
  "$ROOT/apps/dashboard/app/scoreboards/enrollment/page.tsx" \
  "$ROOT/apps/dashboard/app/scoreboards/operations/EnrollmentTrustPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

SERVICE="apps/api/src/services/scoreboardDeviceEnrollment.ts"
ROUTE="apps/api/src/routes/scoreboardDeviceEnrollment.ts"
ENROLL_PAGE="apps/dashboard/app/scoreboards/enrollment/page.tsx"
OPS_PANEL="apps/dashboard/app/scoreboards/operations/EnrollmentTrustPanel.tsx"
CHECKLIST="firmware/esp32-scoreboard/DEPLOYMENT-READINESS-CHECKLIST.md"
README="firmware/esp32-scoreboard/README.md"
TEST="packages/core/test/device-lifecycle-deployment-closeout-12.10.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$SERVICE")" \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$ENROLL_PAGE")" \
  "$BACKUP_DIR/$(dirname "$OPS_PANEL")" \
  "$BACKUP_DIR/$(dirname "$CHECKLIST")" \
  "$BACKUP_DIR/$(dirname "$README")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$TEST")"

for file in "$SERVICE" "$ROUTE" "$ENROLL_PAGE" "$OPS_PANEL" "$CHECKLIST" "$README" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

node <<'NODE'
const fs = require("fs");

const serviceFile =
  "apps/api/src/services/scoreboardDeviceEnrollment.ts";

let service =
  fs.readFileSync(serviceFile, "utf8");

service = service.replace(
`export type EnrollmentStatus =
  | "UNENROLLED"
  | "PENDING"
  | "VERIFIED"
  | "REJECTED";`,
`export type EnrollmentStatus =
  | "UNENROLLED"
  | "PENDING"
  | "VERIFIED"
  | "REJECTED"
  | "RETIRED";`,
);

if (!service.includes("retiredAt: string | null;")) {
  service = service.replace(
    "  claimTokenConsumedAt: string | null;\n};",
    "  claimTokenConsumedAt: string | null;\n  retiredAt: string | null;\n};",
  );
}

if (!service.includes("retiredAt:")) {
  throw new Error(
    "Unable to add retiredAt field to enrollment record.",
  );
}

service = service.replace(
`    claimTokenConsumedAt:
      null,
  };`,
`    claimTokenConsumedAt:
      null,
    retiredAt:
      null,
  };`,
);

if (!service.includes("export function retireEnrollment(")) {
  service += `

export function retireEnrollment(
  deviceId: string,
): ScoreboardEnrollmentRecord | null {
  const record =
    store.devices[deviceId];

  if (!record) {
    return null;
  }

  const now =
    new Date().toISOString();

  const updated = {
    ...record,
    status:
      "RETIRED" as const,
    retiredAt:
      now,
    lastSeenAt:
      now,
    claimTokenHash:
      null,
    claimTokenConsumedAt:
      record.claimTokenConsumedAt ??
      now,
  };

  store.devices[
    deviceId
  ] = updated;

  persistStore();

  return updated;
}

export function reactivateEnrollment(
  deviceId: string,
): ScoreboardEnrollmentRecord | null {
  const record =
    store.devices[deviceId];

  if (
    !record ||
    record.status !==
      "RETIRED"
  ) {
    return null;
  }

  const now =
    new Date().toISOString();

  const updated = {
    ...record,
    status:
      "PENDING" as const,
    verifiedAt:
      null,
    retiredAt:
      null,
    lastSeenAt:
      now,
    claimTokenHash:
      null,
    claimTokenIssuedAt:
      null,
    claimTokenConsumedAt:
      null,
  };

  store.devices[
    deviceId
  ] = updated;

  persistStore();

  return updated;
}
`;
}

fs.writeFileSync(
  serviceFile,
  service,
);

const routeFile =
  "apps/api/src/routes/scoreboardDeviceEnrollment.ts";

let routes =
  fs.readFileSync(routeFile, "utf8");

if (!routes.includes("retireEnrollment")) {
  routes = routes.replace(
`  registerFirstBoot,
  rejectEnrollment,
  verifyEnrollmentWithClaim,`,
`  registerFirstBoot,
  rejectEnrollment,
  retireEnrollment,
  reactivateEnrollment,
  verifyEnrollmentWithClaim,`,
  );
}

if (!routes.includes("/:deviceId/retire")) {
  const end =
    routes.lastIndexOf("\n}");

  if (end === -1) {
    throw new Error(
      "Unable to locate enrollment route function end.",
    );
  }

  const addition = `

  app.post(
    "/scoreboard-devices/enrollment/:deviceId/retire",
    async (request, reply) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      const record =
        retireEnrollment(
          deviceId,
        );

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
    "/scoreboard-devices/enrollment/:deviceId/reactivate",
    async (request, reply) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      const record =
        reactivateEnrollment(
          deviceId,
        );

      if (!record) {
        return reply.code(409).send({
          success: false,
          error:
            "Only retired devices can be reactivated.",
        });
      }

      return {
        success: true,
        data: record,
      };
    },
  );
`;

  routes =
    routes.slice(0, end) +
    addition +
    routes.slice(end);
}

fs.writeFileSync(
  routeFile,
  routes,
);
NODE

node <<'NODE'
const fs = require("fs");

const files = [
  "apps/dashboard/app/scoreboards/enrollment/page.tsx",
  "apps/dashboard/app/scoreboards/operations/EnrollmentTrustPanel.tsx",
];

for (const file of files) {
  let text =
    fs.readFileSync(file, "utf8");

  text =
    text.replace(
`    | "VERIFIED"
    | "REJECTED";`,
`    | "VERIFIED"
    | "REJECTED"
    | "RETIRED";`,
    );

  fs.writeFileSync(
    file,
    text,
  );
}

const pageFile =
  "apps/dashboard/app/scoreboards/enrollment/page.tsx";

let page =
  fs.readFileSync(pageFile, "utf8");

if (!page.includes("retiredCount")) {
  page = page.replace(
`  const rejectedCount =
    useMemo(
      () =>
        devices.filter(
          (device) =>
            device.status ===
            "REJECTED",
        ).length,
      [devices],
    );`,
`  const rejectedCount =
    useMemo(
      () =>
        devices.filter(
          (device) =>
            device.status ===
            "REJECTED",
        ).length,
      [devices],
    );

  const retiredCount =
    useMemo(
      () =>
        devices.filter(
          (device) =>
            device.status ===
            "RETIRED",
        ).length,
      [devices],
    );`,
  );
}

if (!page.includes('action: "retire" | "reactivate"')) {
  const anchor =
    "  const reject = async (";

  const idx =
    page.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate enrollment reject action.",
    );
  }

  const action = `  const lifecycle = async (
    deviceId: string,
    action: "retire" | "reactivate",
  ) => {
    setBusyDeviceId(
      deviceId,
    );

    try {
      const response =
        await fetch(
          \`\${API_BASE}/scoreboard-devices/enrollment/\${encodeURIComponent(
            deviceId,
          )}/\${action}\`,
          {
            method: "POST",
          },
        );

      const json =
        await response.json();

      if (
        !response.ok ||
        !json?.success
      ) {
        setMessages((current) => ({
          ...current,
          [deviceId]:
            json?.error ??
            \`Unable to \${action} device.\`,
        }));

        return;
      }

      setClaimTokens((current) => {
        const next = {
          ...current,
        };

        delete next[deviceId];

        return next;
      });

      setMessages((current) => ({
        ...current,
        [deviceId]:
          action === "retire"
            ? "Device retired. Authoritative operations are disabled."
            : "Device reactivated to PENDING and must be claimed again.",
      }));

      await load();
    } finally {
      setBusyDeviceId(
        null,
      );
    }
  };

`;

  page =
    page.slice(0, idx) +
    action +
    page.slice(idx);
}

page = page.replace(
'className="mb-6 grid gap-3 sm:grid-cols-3"',
'className="mb-6 grid gap-3 sm:grid-cols-4"',
);

if (!page.includes("{retiredCount}")) {
  const rejectedCard = `        <div className="rounded-xl border border-slate-800 p-4">
          <div className="text-sm text-slate-400">
            Rejected
          </div>
          <div className="mt-1 text-2xl font-semibold">
            {rejectedCount}
          </div>
        </div>`;

  if (!page.includes(rejectedCard)) {
    throw new Error(
      "Unable to locate rejected metric card.",
    );
  }

  page = page.replace(
    rejectedCard,
    rejectedCard + `

        <div className="rounded-xl border border-slate-800 p-4">
          <div className="text-sm text-slate-400">
            Retired
          </div>
          <div className="mt-1 text-2xl font-semibold">
            {retiredCount}
          </div>
        </div>`,
  );
}

if (!page.includes("Retire Device")) {
  const marker =
    `{device.status ===
                    "PENDING" && (`;

  const idx =
    page.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate pending action block.",
    );
  }

  const insertAfter =
    page.indexOf(
      "                )}",
      idx,
    );

  if (insertAfter === -1) {
    throw new Error(
      "Unable to locate end of pending action block.",
    );
  }

  const lifecycleUi = `

                {device.status ===
                  "VERIFIED" && (
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      void lifecycle(
                        device.deviceId,
                        "retire",
                      )
                    }
                    className="rounded-lg border border-slate-600 px-4 py-2 disabled:opacity-50"
                  >
                    Retire Device
                  </button>
                )}

                {device.status ===
                  "RETIRED" && (
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      void lifecycle(
                        device.deviceId,
                        "reactivate",
                      )
                    }
                    className="rounded-lg border border-slate-600 px-4 py-2 disabled:opacity-50"
                  >
                    Reactivate
                  </button>
                )}`;

  page =
    page.slice(
      0,
      insertAfter + 18,
    ) +
    lifecycleUi +
    page.slice(
      insertAfter + 18,
    );
}

fs.writeFileSync(
  pageFile,
  page,
);
NODE

cat > "$CHECKLIST" <<'EOF'
# SportsOS Scoreboard Deployment Readiness

Milestone 12 closes the software-side deployment lifecycle for ESP32 scoreboard devices.

## Lifecycle

A production device progresses through:

1. `FLASHED`
2. `PROVISIONED`
3. `PENDING`
4. `VERIFIED`
5. `ASSIGNED`
6. `ACTIVE`
7. `RETIRED`

A retired device must be reactivated to `PENDING` and claimed again before it can return to authoritative operations.

## Build gate

- repository typecheck passes
- repository tests pass
- firmware behavior simulator passes
- Dockerized PlatformIO compile passes
- release package contains `firmware.bin`
- SHA-256 release hashes exist

## Enrollment gate

- physical device ID reviewed
- firmware version reviewed
- ESP32 chip ID reviewed
- one-time claim token generated
- claim token successfully consumed
- device status is `VERIFIED`

## Operations gate

- device is visible in hardware operations
- enrollment trust is `VERIFIED`
- presence is online
- telemetry is current
- device can be assigned
- reconcile succeeds
- authoritative state matches the game
- horn/status/display outputs pass physical validation

## Retirement gate

Retire a device when:

- hardware is removed from service
- ESP32 is replaced
- identity is suspected compromised
- scoreboard is reassigned to a different physical controller

Retirement must:

- change trust status to `RETIRED`
- invalidate any outstanding claim token
- block verified-device authorization
- require reactivation and a new claim before reuse

## Milestone 12 release gate

Milestone 12 is complete when:

- repository tests are green
- API and dashboard build successfully
- firmware simulator is green
- the operations dashboard loads
- enrollment lifecycle controls load
- a test or physical device can move through pending → verified → retired → pending
EOF

cat >> "$README" <<'EOF'

## Milestone 12.10 — Device lifecycle / deployment closeout

SportsOS now defines the complete scoreboard trust lifecycle.

Enrollment states include:

- `PENDING`
- `VERIFIED`
- `REJECTED`
- `RETIRED`

A verified device may be explicitly retired. Retirement invalidates the operational trust relationship and blocks verified-device authorization.

A retired device may be reactivated, which moves it back to `PENDING`. It must receive a new one-time claim token and be verified again before authoritative scoreboard operations are permitted.

See:

`DEPLOYMENT-READINESS-CHECKLIST.md`

for the full Milestone 12 deployment release gate.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.10 device lifecycle / deployment closeout", () => {
  it("adds retired enrollment state", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      '"RETIRED"',
    );

    expect(service).toContain(
      "retiredAt",
    );
  });

  it("supports retirement and reactivation", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "retireEnrollment",
    );

    expect(service).toContain(
      "reactivateEnrollment",
    );

    expect(service).toContain(
      '"PENDING" as const',
    );
  });

  it("exposes retire and reactivate API routes", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/retire",
    );

    expect(routes).toContain(
      "/reactivate",
    );
  });

  it("adds lifecycle controls to enrollment dashboard", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/enrollment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Retire Device",
    );

    expect(page).toContain(
      "Reactivate",
    );

    expect(page).toContain(
      "retiredCount",
    );
  });

  it("documents the deployment lifecycle and release gate", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/DEPLOYMENT-READINESS-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(checklist).toContain(
      "FLASHED",
    );

    expect(checklist).toContain(
      "VERIFIED",
    );

    expect(checklist).toContain(
      "ACTIVE",
    );

    expect(checklist).toContain(
      "RETIRED",
    );

    expect(checklist).toContain(
      "Milestone 12 release gate",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 12.10 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - RETIRED device lifecycle state"
echo "  - retirement timestamp"
echo "  - retirement API"
echo "  - reactivation API"
echo "  - retirement invalidates trust"
echo "  - reactivation returns device to PENDING"
echo "  - enrollment dashboard retire/reactivate controls"
echo "  - deployment readiness checklist"
echo "  - Milestone 12 closeout tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run full repository gate:"
echo "  npm run typecheck && npm test && npm run build"
echo
echo "Then rebuild services:"
echo "  docker compose up -d --build api dashboard"
echo
echo "Then run E2E:"
echo "  npm run test:e2e:docker"
echo
echo "Then firmware simulator:"
echo "  node --test firmware/esp32-scoreboard/simulator/test/*.test.js"
echo
echo "Milestone 12 is closed when all gates above are green."
