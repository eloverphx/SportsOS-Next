#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="13.10-firmware-fleet-acceptance-closeout"
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
  "$ROOT/apps/api/src/routes/scoreboardFirmwareReleases.ts" \
  "$ROOT/apps/api/src/routes/scoreboardFirmwareRollouts.ts" \
  "$ROOT/apps/api/src/routes/scoreboardFirmwareDeploymentStatus.ts" \
  "$ROOT/apps/dashboard/app/scoreboards/firmware/page.tsx" \
  "$ROOT/firmware/esp32-scoreboard/build-in-docker.sh"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

ACCEPT="firmware/esp32-scoreboard/run-fleet-acceptance.sh"
CHECKLIST="firmware/esp32-scoreboard/FLEET-ACCEPTANCE-CHECKLIST.md"
TEST="packages/core/test/firmware-fleet-acceptance-closeout-13.10.test.ts"
README="firmware/esp32-scoreboard/README.md"

for file in "$ACCEPT" "$CHECKLIST" "$TEST" "$README"; do
  if [[ -f "$file" ]]; then
    rel="${file#$ROOT/}"
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$file" "$BACKUP_DIR/$rel"
  fi
done

mkdir -p \
  "$(dirname "$ACCEPT")" \
  "$(dirname "$CHECKLIST")" \
  "$(dirname "$TEST")"

cat > "$ACCEPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  exit 1
fi

cd "$ROOT"

echo "============================================================"
echo " SportsOS Firmware Fleet Acceptance"
echo "============================================================"

echo
echo "[1/5] Repository typecheck"
npm run typecheck

echo
echo "[2/5] Repository tests"
npm test

echo
echo "[3/5] Firmware behavior simulator"
node --test firmware/esp32-scoreboard/simulator/test/*.test.js

echo
echo "[4/5] Real ESP32 compile"
bash firmware/esp32-scoreboard/build-in-docker.sh

echo
echo "[5/5] Build dashboard/API"
npm run build

echo
echo "============================================================"
echo " Firmware Fleet Acceptance: PASS"
echo "============================================================"
echo
echo "Recommended runtime verification:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
EOF

chmod +x "$ACCEPT"

cat > "$CHECKLIST" <<'EOF'
# SportsOS Firmware Fleet Acceptance Checklist

Milestone 13 closes the firmware-fleet-management software path.

## Release acceptance

- OTA release manifest can be created.
- Release contains SHA-256 and firmware size.
- Release can be registered in SportsOS.
- Artifact import rejects invalid size.
- Artifact import rejects invalid SHA-256.
- Valid artifact is stored by SportsOS.

## Device-offer acceptance

- Device must be VERIFIED.
- Device must belong to an ACTIVE rollout.
- Rollout release must exist.
- Channel must match.
- hardware target must match.
- Device already on target version receives no update.
- Eligible device receives a device-bound artifact URL.

## OTA staging acceptance

- Firmware downloads from SportsOS.
- HTTP failures abort.
- size mismatches abort.
- SHA-256 mismatch aborts.
- OTA partition is finalized only after integrity verification.

## Install policy acceptance

- Unverified device cannot install.
- Unsafe live runtime blocks install.
- Staged image is required.
- Boot is marked pending validation before restart.
- Successful authoritative startup confirms boot healthy.

## Reporting acceptance

- Update reports require VERIFIED device identity.
- Progress can be recorded.
- failures can include error details.
- latest deployment state can be queried per device.
- report history is retained.

## Rollout acceptance

- Rollout starts as DRAFT.
- ACTIVE rollout offers updates.
- PAUSED rollout stops new offers.
- ACTIVE rollout can be completed.
- DRAFT/ACTIVE/PAUSED rollout can be cancelled.
- All targets must be VERIFIED devices.

## Dashboard acceptance

`/scoreboards/firmware` shows:

- release inventory
- rollout plans
- rollout controls
- current firmware version
- target firmware version
- deployment progress
- deployment failures

## Final Milestone 13 gate

Run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash firmware/esp32-scoreboard/run-fleet-acceptance.sh
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

Milestone 13 is complete when all commands above are green.
EOF

cat >> "$README" <<'EOF'

## Milestone 13.10 — Firmware fleet acceptance / closeout

Milestone 13 provides the complete SportsOS firmware fleet-management foundation:

1. OTA release contract
2. release registry
3. artifact validation and serving
4. device update offer discovery
5. OTA download and integrity validation
6. controlled install/reboot policy
7. deployment reporting
8. firmware fleet dashboard
9. rollout orchestration
10. fleet acceptance gate

Run the full software + firmware acceptance gate with:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash firmware/esp32-scoreboard/run-fleet-acceptance.sh
```

Then run the container and browser workflow gates:

```bash
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

See `FLEET-ACCEPTANCE-CHECKLIST.md` for the detailed closeout criteria.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.10 firmware fleet acceptance / closeout", () => {
  it("adds a single fleet acceptance runner", () => {
    const script = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/run-fleet-acceptance.sh",
        import.meta.url,
      ),
      "utf8",
    );

    expect(script).toContain(
      "npm run typecheck",
    );

    expect(script).toContain(
      "npm test",
    );

    expect(script).toContain(
      "node --test firmware/esp32-scoreboard/simulator/test/*.test.js",
    );

    expect(script).toContain(
      "build-in-docker.sh",
    );

    expect(script).toContain(
      "npm run build",
    );
  });

  it("documents release, rollout, OTA, and reporting acceptance", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/FLEET-ACCEPTANCE-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    for (const heading of [
      "Release acceptance",
      "Device-offer acceptance",
      "OTA staging acceptance",
      "Install policy acceptance",
      "Reporting acceptance",
      "Rollout acceptance",
      "Dashboard acceptance",
    ]) {
      expect(checklist).toContain(
        heading,
      );
    }
  });

  it("requires verified devices throughout fleet management", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/FLEET-ACCEPTANCE-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(checklist).toContain(
      "Device must be VERIFIED.",
    );

    expect(checklist).toContain(
      "All targets must be VERIFIED devices.",
    );
  });

  it("requires browser E2E after fleet acceptance", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/FLEET-ACCEPTANCE-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(checklist).toContain(
      "npm run test:e2e:docker",
    );
  });

  it("documents the Milestone 13 closeout sequence", () => {
    const readme = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/README.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(readme).toContain(
      "Milestone 13.10",
    );

    expect(readme).toContain(
      "run-fleet-acceptance.sh",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 13.10 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - firmware fleet acceptance runner"
echo "  - release acceptance checklist"
echo "  - rollout acceptance checklist"
echo "  - OTA staging/install acceptance"
echo "  - deployment reporting acceptance"
echo "  - fleet dashboard acceptance"
echo "  - Milestone 13 closeout documentation"
echo "  - Milestone 13.10 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run full Milestone 13 gate:"
echo "  bash firmware/esp32-scoreboard/run-fleet-acceptance.sh"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Milestone 13 is closed when all gates are green."
