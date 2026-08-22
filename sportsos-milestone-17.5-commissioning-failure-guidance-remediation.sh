#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-17.5-commissioning-remediation-guidance-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

PANEL="apps/dashboard/app/scoreboards/operations/ScoreboardCommissioningWizard.tsx"
TEST="packages/core/test/commissioning-remediation-guidance-17.5.test.ts"

for required in \
  ".git" \
  "$PANEL"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

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
  "apps/dashboard/app/scoreboards/operations/ScoreboardCommissioningWizard.tsx";

let text =
  fs.readFileSync(file, "utf8");

if (!text.includes("REMEDIATION_GUIDANCE")) {
  const anchor =
`const STEP_LABELS:
  Record<
    CommissioningStepId,
    string
  > = {`;

  const idx =
    text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate STEP_LABELS.",
    );
  }

  const end =
    text.indexOf(
      "\n};",
      idx,
    );

  if (end === -1) {
    throw new Error(
      "Unable to locate end of STEP_LABELS.",
    );
  }

  const insertAt =
    end + 3;

  const guidance =
`

const REMEDIATION_GUIDANCE:
  Record<
    CommissioningStepId,
    string[]
  > = {
    FLASHED: [
      "Confirm the correct SportsOS production firmware was flashed to the ESP32.",
      "Reconnect USB and re-flash if the controller does not boot normally.",
    ],
    PROVISIONED: [
      "Verify Wi-Fi/network settings and the SportsOS API/MQTT endpoints on the controller.",
      "Confirm the device can reach the SportsOS server from the scoreboard network.",
    ],
    ENROLLED: [
      "Confirm the controller completed device enrollment and received a SportsOS identity.",
      "Restart enrollment if the device never appears in the server device inventory.",
    ],
    VERIFIED: [
      "Open scoreboard device operations and confirm the hardware is marked verified.",
      "Re-run the verification/enrollment workflow if the device is still pending or untrusted.",
    ],
    ASSIGNED: [
      "Assign this scoreboard device to the intended game or scoreboard context.",
      "Confirm the device ID in the assignment matches the controller being commissioned.",
    ],
    CONNECTIVITY: [
      "Check controller power, Wi-Fi/LAN connectivity, MQTT/API reachability, and firewall rules.",
      "Confirm a fresh heartbeat is reaching SportsOS.",
    ],
    READINESS: [
      "Wait for a fresh heartbeat and stable readiness window.",
      "Review Device Readiness Status and Reliability Risk Classification for stale, offline, or at-risk state.",
    ],
    FIRMWARE: [
      "Confirm the installed firmware is on an approved SportsOS release/channel.",
      "Run the firmware update workflow if the device is behind the approved release.",
    ],
    GAME_READY: [
      "Resolve every incomplete commissioning stage, then run validation again.",
      "GAME_READY is set automatically only after all prerequisites pass.",
    ],
  };`;

  text =
    text.slice(0, insertAt) +
    guidance +
    text.slice(insertAt);
}

if (!text.includes("Suggested Remediation")) {
  const anchor =
`                  {step.note && (
                    <p className="mt-2 text-sm text-slate-400">
                      {step.note}
                    </p>
                  )}`;

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate commissioning step note block.",
    );
  }

  const block =
`${anchor}

                  {!step.complete && (
                    <div className="mt-3 rounded-lg border border-slate-800 bg-slate-950/40 p-3">
                      <div className="text-xs font-semibold uppercase tracking-wide text-slate-400">
                        Suggested Remediation
                      </div>
                      <ul className="mt-2 list-disc space-y-1 pl-5 text-xs text-slate-500">
                        {REMEDIATION_GUIDANCE[
                          step.id
                        ].map(
                          (item) => (
                            <li key={item}>
                              {item}
                            </li>
                          ),
                        )}
                      </ul>
                    </div>
                  )}`;

  text =
    text.replace(
      anchor,
      block,
    );
}

if (!text.includes("Blocked commissioning steps")) {
  const anchor =
`          <div className="mt-4 space-y-2">
            {commissioning.steps.map(`;

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate commissioning step list.",
    );
  }

  const summary =
`          {commissioning.status ===
            "BLOCKED" && (
            <div className="mt-4 rounded-xl border border-slate-800 p-4">
              <div className="font-semibold">
                Blocked commissioning steps
              </div>
              <p className="mt-1 text-sm text-slate-500">
                Review the pending stages below, apply the suggested remediation, then allow Live Progress or Run Validation to check again.
              </p>
            </div>
          )}

`;

  text =
    text.replace(
      anchor,
      summary + anchor,
    );
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

describe("Milestone 17.5 commissioning failure guidance / remediation actions", () => {
  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/ScoreboardCommissioningWizard.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("defines remediation guidance for every commissioning step", () => {
    expect(panel).toContain(
      "REMEDIATION_GUIDANCE",
    );

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
      expect(panel).toContain(
        `${step}: [`,
      );
    }
  });

  it("shows guidance only for incomplete steps", () => {
    expect(panel).toContain(
      "!step.complete",
    );

    expect(panel).toContain(
      "Suggested Remediation",
    );
  });

  it("includes connectivity troubleshooting", () => {
    expect(panel).toContain(
      "MQTT/API reachability",
    );

    expect(panel).toContain(
      "fresh heartbeat",
    );
  });

  it("includes readiness and reliability troubleshooting", () => {
    expect(panel).toContain(
      "Device Readiness Status",
    );

    expect(panel).toContain(
      "Reliability Risk Classification",
    );
  });

  it("surfaces blocked commissioning state", () => {
    expect(panel).toContain(
      "Blocked commissioning steps",
    );

    expect(panel).toContain(
      'commissioning.status ===',
    );

    expect(panel).toContain(
      '"BLOCKED"',
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 17.5 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - per-step commissioning remediation guidance"
echo "  - flashed/provisioned troubleshooting"
echo "  - enrollment/verification guidance"
echo "  - assignment remediation"
echo "  - connectivity and heartbeat troubleshooting"
echo "  - readiness/reliability remediation"
echo "  - firmware update guidance"
echo "  - BLOCKED commissioning summary"
echo "  - Milestone 17.5 regression tests"
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
echo "  Milestone 17.6 - Commissioning Test Command / Hardware Self-Test"
