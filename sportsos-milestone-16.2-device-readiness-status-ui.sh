#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-16.2-device-readiness-status-ui-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/routes/scoreboardControlPolicy.ts" \
  "$ROOT/apps/api/src/routes/scoreboardDevices.ts" \
  "$ROOT/apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

PANEL="apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
TEST="packages/core/test/device-readiness-status-ui-16.2.test.ts"

for file in "$PANEL" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx";

let text =
  fs.readFileSync(file, "utf8");

if (!text.includes("type DeviceReadiness")) {
  const marker =
    "type PhysicalControlHealth";

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate PhysicalControlHealth type.",
    );
  }

  text =
    text.slice(0, idx) +
`type DeviceReadiness = {
  ready: boolean;
  deviceId: string;
  lastHeartbeatAt: string | null;
  heartbeatAgeMs: number | null;
  thresholdMs: number;
  reason: string | null;
};

type AssignedDevice = {
  gameId: string;
  deviceId: string;
};

` +
    text.slice(idx);
}

if (!text.includes("const [deviceReadiness")) {
  const marker =
    "const [controlHealth, setControlHealth]";

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate control health state.",
    );
  }

  text =
    text.slice(0, idx) +
`const [deviceReadiness, setDeviceReadiness] =
    useState<DeviceReadiness[]>([]);

  const [assignedDevices, setAssignedDevices] =
    useState<AssignedDevice[]>([]);

  ` +
    text.slice(idx);
}

if (!text.includes("/scoreboard-devices/assignments")) {
  const marker =
`        fetch(
          \`\${API_BASE}/scoreboard-control-health\`,
          { cache: "no-store" },
        ),`;

  if (!text.includes(marker)) {
    throw new Error(
      "Unable to locate health fetch.",
    );
  }

  text =
    text.replace(
      marker,
`${marker}
        fetch(
          \`\${API_BASE}/scoreboard-devices/assignments\`,
          { cache: "no-store" },
        ),`
    );

  text =
    text.replace(
`        healthResponse,
        incidentsResponse,`,
`        healthResponse,
        assignmentsResponse,
        incidentsResponse,`
    );

  const anchor =
`      if (healthResponse.ok) {
        const healthJson =
          await healthResponse.json();

        setControlHealth(
          healthJson?.data?.health ??
          null,
        );
      }`;

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate health response block.",
    );
  }

  text =
    text.replace(
      anchor,
`${anchor}

      if (assignmentsResponse.ok) {
        const assignmentsJson =
          await assignmentsResponse.json();

        const assignments =
          assignmentsJson?.data?.assignments ??
          assignmentsJson?.assignments ??
          [];

        setAssignedDevices(
          assignments,
        );

        const readinessResults =
          await Promise.all(
            assignments.map(
              async (
                assignment: AssignedDevice,
              ) => {
                try {
                  const readinessResponse =
                    await fetch(
                      \`\${API_BASE}/scoreboard-control-readiness/\${encodeURIComponent(assignment.deviceId)}\`,
                      {
                        cache: "no-store",
                      },
                    );

                  if (!readinessResponse.ok) {
                    return {
                      ready: false,
                      deviceId:
                        assignment.deviceId,
                      lastHeartbeatAt:
                        null,
                      heartbeatAgeMs:
                        null,
                      thresholdMs:
                        30000,
                      reason:
                        \`Readiness request failed (\${readinessResponse.status}).\`,
                    } satisfies DeviceReadiness;
                  }

                  const readinessJson =
                    await readinessResponse.json();

                  return (
                    readinessJson?.data?.readiness ??
                    {
                      ready: false,
                      deviceId:
                        assignment.deviceId,
                      lastHeartbeatAt:
                        null,
                      heartbeatAgeMs:
                        null,
                      thresholdMs:
                        30000,
                      reason:
                        "Readiness response was empty.",
                    }
                  ) as DeviceReadiness;
                } catch {
                  return {
                    ready: false,
                    deviceId:
                      assignment.deviceId,
                    lastHeartbeatAt:
                      null,
                    heartbeatAgeMs:
                      null,
                    thresholdMs:
                      30000,
                    reason:
                      "Unable to query device readiness.",
                  } satisfies DeviceReadiness;
                }
              },
            ),
          );

        setDeviceReadiness(
          readinessResults,
        );
      }`
    );
}

if (!text.includes("Device Readiness Status")) {
  const marker =
    '      <div className="mt-6 rounded-xl border border-slate-800 p-4">\n        <h3 className="font-semibold">\n          Control Readiness Probe';

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate readiness probe panel.",
    );
  }

  const block =
`      <div className="mt-6 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="font-semibold">
              Device Readiness Status
            </h3>
            <p className="mt-1 text-sm text-slate-500">
              Assigned scoreboard devices and their current heartbeat readiness.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-2 py-1 text-xs">
            {deviceReadiness.filter(
              (item) => item.ready,
            ).length}
            /
            {assignedDevices.length}
            {" "}ready
          </span>
        </div>

        {assignedDevices.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">
            No scoreboard devices are currently assigned.
          </p>
        ) : (
          <div className="mt-4 overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-slate-500">
                <tr>
                  <th className="pb-2 pr-4">
                    Device
                  </th>
                  <th className="pb-2 pr-4">
                    Game
                  </th>
                  <th className="pb-2 pr-4">
                    Readiness
                  </th>
                  <th className="pb-2 pr-4">
                    Heartbeat Age
                  </th>
                  <th className="pb-2">
                    Detail
                  </th>
                </tr>
              </thead>
              <tbody>
                {assignedDevices.map(
                  (assignment) => {
                    const readiness =
                      deviceReadiness.find(
                        (item) =>
                          item.deviceId ===
                          assignment.deviceId,
                      );

                    return (
                      <tr
                        key={[
                          assignment.gameId,
                          assignment.deviceId,
                        ].join(":")}
                        className="border-t border-slate-800"
                      >
                        <td className="py-3 pr-4 font-mono text-xs">
                          {assignment.deviceId}
                        </td>
                        <td className="py-3 pr-4 font-mono text-xs">
                          {assignment.gameId}
                        </td>
                        <td className="py-3 pr-4">
                          {readiness
                            ? readiness.ready
                              ? "READY"
                              : "NOT READY"
                            : "CHECKING"}
                        </td>
                        <td className="py-3 pr-4">
                          {readiness?.heartbeatAgeMs != null
                            ? \`\${Math.round(
                                readiness.heartbeatAgeMs / 1000,
                              )}s\`
                            : "—"}
                        </td>
                        <td className="py-3 text-slate-400">
                          {readiness?.reason ??
                            (
                              readiness?.lastHeartbeatAt
                                ? \`Last heartbeat \${readiness.lastHeartbeatAt}\`
                                : "—"
                            )}
                        </td>
                      </tr>
                    );
                  },
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>

`;

  text =
    text.slice(0, idx) +
    block +
    text.slice(idx);
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

describe("Milestone 16.2 device readiness status UI", () => {
  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("loads scoreboard assignments", () => {
    expect(panel).toContain(
      "/scoreboard-devices/assignments",
    );
  });

  it("queries server readiness for assigned devices", () => {
    expect(panel).toContain(
      "/scoreboard-control-readiness/",
    );

    expect(panel).toContain(
      "DeviceReadiness",
    );
  });

  it("renders device readiness status", () => {
    expect(panel).toContain(
      "Device Readiness Status",
    );

    expect(panel).toContain(
      "READY",
    );

    expect(panel).toContain(
      "NOT READY",
    );
  });

  it("shows game, device, heartbeat age, and detail", () => {
    for (const value of [
      "Device",
      "Game",
      "Heartbeat Age",
      "Detail",
    ]) {
      expect(panel).toContain(
        value,
      );
    }
  });

  it("does not make readiness authoritative in the browser", () => {
    expect(panel).toContain(
      "/scoreboard-control-readiness/",
    );

    expect(panel).not.toContain(
      "localStorage.setItem(\"deviceReadiness",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 16.2 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - assigned-device readiness inventory"
echo "  - server readiness queries per device"
echo "  - READY / NOT READY / CHECKING display"
echo "  - heartbeat age display"
echo "  - readiness reason/detail display"
echo "  - ready-device summary count"
echo "  - Milestone 16.2 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 16.3 - Readiness Degradation / Offline Incident Generation"
