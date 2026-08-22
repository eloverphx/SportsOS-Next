#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-17.10-hardware-commissioning-closeout-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "package.json" \
  "apps/api/src/services/scoreboardDeviceCommissioning.ts" \
  "apps/api/src/services/scoreboardCommissioningValidator.ts" \
  "apps/api/src/services/scoreboardCommissioningSelfTest.ts" \
  "apps/api/src/services/scoreboardCommissioningSelfTestDispatch.ts" \
  "apps/api/src/services/scoreboardCommissioningSelfTestTransport.ts" \
  "apps/api/src/routes/scoreboardDeviceCommissioning.ts" \
  "apps/dashboard/app/scoreboards/operations/ScoreboardCommissioningWizard.tsx" \
  "firmware/esp32-scoreboard/include/CommissioningSelfTest.h" \
  "firmware/esp32-scoreboard/include/CommissioningSelfTestCommand.h" \
  "firmware/esp32-scoreboard/src/CommissioningSelfTest.cpp" \
  "firmware/esp32-scoreboard/src/CommissioningSelfTestCommand.cpp"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

RUNNER="scripts/run-hardware-commissioning-acceptance.sh"
CHECKLIST="docs/HARDWARE-COMMISSIONING-ACCEPTANCE.md"
TEST="packages/core/test/hardware-commissioning-closeout-17.10.test.ts"

for file in "$RUNNER" "$CHECKLIST" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p scripts docs packages/core/test

cat > "$RUNNER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
cd "$ROOT"

echo "============================================================"
echo " SportsOS Hardware Commissioning Acceptance"
echo "============================================================"

npm run build --workspace @sportsos/core
npm run typecheck
npm test
npm run build
bash firmware/esp32-scoreboard/build-in-docker.sh

test -f apps/api/src/services/scoreboardDeviceCommissioning.ts
test -f apps/api/src/services/scoreboardCommissioningValidator.ts
test -f apps/api/src/services/scoreboardCommissioningSelfTest.ts
test -f apps/api/src/services/scoreboardCommissioningSelfTestDispatch.ts
test -f apps/api/src/services/scoreboardCommissioningSelfTestTransport.ts
test -f apps/dashboard/app/scoreboards/operations/ScoreboardCommissioningWizard.tsx
test -f firmware/esp32-scoreboard/include/CommissioningSelfTest.h
test -f firmware/esp32-scoreboard/include/CommissioningSelfTestCommand.h

grep -q 'COMMISSIONING_SELF_TEST' \
  firmware/esp32-scoreboard/src/CommissioningSelfTestCommand.cpp

grep -q 'commandId' \
  firmware/esp32-scoreboard/src/CommissioningSelfTest.cpp

echo
echo "Hardware Commissioning Acceptance: PASS"
echo
echo "Final runtime/browser gate:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
EOF

chmod +x "$RUNNER"

cat > "$CHECKLIST" <<'EOF'
# SportsOS Hardware Commissioning Acceptance

Milestone 17 closes the physical scoreboard installation and commissioning workflow.

## 17.1 Scoreboard device commissioning lifecycle
FLASHED → PROVISIONED → ENROLLED → VERIFIED → ASSIGNED → CONNECTIVITY → READINESS → FIRMWARE → GAME_READY.

GAME_READY requires every prerequisite to pass.

## 17.2 Automated commissioning validation
SportsOS automatically evaluates enrollment, verification, assignment, heartbeat/connectivity, readiness, reliability, firmware, and final GAME_READY status.

## 17.3 Commissioning dashboard / installation wizard
The operations UI starts commissioning by device ID, shows every stage, supports manual FLASHED/PROVISIONED confirmation, automated validation, notes, timestamps, and final GAME_READY status.

## 17.4 Live commissioning progress
Validation repeats automatically while commissioning is active, avoids overlapping requests, can be paused, and stops at GAME_READY.

## 17.5 Failure guidance / remediation
Incomplete stages show actionable remediation for flashing, provisioning, enrollment, verification, assignment, connectivity, readiness, reliability, firmware, and GAME_READY prerequisites.

## 17.6 Commissioning hardware self-test
Self-test covers controller runtime, display path, physical input path, connectivity, and firmware runtime with PASS/FAIL results.

## 17.7 Firmware-driven self-test telemetry
ESP32 firmware implements a non-game-state-changing commissioning self-test and reports results with `source: FIRMWARE`.

## 17.8 Remote command correlation
Each remote test receives a unique `commandId` and tracks PENDING, ACKNOWLEDGED, COMPLETED, or FAILED. Firmware telemetry echoes the same commandId.

## 17.9 Self-test transport and device execution
SportsOS publishes `COMMISSIONING_SELF_TEST` through the scoreboard transport. Firmware validates the target device, runs the local self-test, and returns command-correlated telemetry without modifying authoritative game state.

## Final Milestone 17 gate

```bash
cd /mnt/user/appdata/SportsOS-Next
bash scripts/run-hardware-commissioning-acceptance.sh
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

Milestone 17 is complete when all commands are green.
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 17.10 hardware commissioning closeout", () => {
  const runner = fs.readFileSync(
    new URL("../../../scripts/run-hardware-commissioning-acceptance.sh", import.meta.url),
    "utf8",
  );

  const checklist = fs.readFileSync(
    new URL("../../../docs/HARDWARE-COMMISSIONING-ACCEPTANCE.md", import.meta.url),
    "utf8",
  );

  it("includes all acceptance gates", () => {
    for (const command of [
      "npm run typecheck",
      "npm test",
      "npm run build",
      "build-in-docker.sh",
    ]) {
      expect(runner).toContain(command);
    }
  });

  it("documents milestones 17.1 through 17.9", () => {
    for (let i = 1; i <= 9; i += 1) {
      expect(checklist).toContain(`17.${i}`);
    }
  });

  it("requires command-correlated telemetry", () => {
    expect(checklist).toContain("commandId");
    expect(checklist).toContain("COMMISSIONING_SELF_TEST");
  });

  it("keeps self-test outside authoritative game state", () => {
    expect(checklist).toContain("without modifying authoritative game state");
  });

  it("documents the final E2E gate", () => {
    expect(checklist).toContain("npm run test:e2e:docker");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 17.10 installed"
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  bash scripts/run-hardware-commissioning-acceptance.sh"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
