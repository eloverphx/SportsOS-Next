#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="14.10-physical-control-acceptance-closeout"
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
  "$ROOT/firmware/esp32-scoreboard/build-in-docker.sh" \
  "$ROOT/firmware/esp32-scoreboard/include/GpioButtonInput.h" \
  "$ROOT/firmware/esp32-scoreboard/include/ScoreboardControlRetryQueue.h" \
  "$ROOT/apps/api/src/routes/scoreboardControlInputs.ts" \
  "$ROOT/apps/api/src/services/scoreboardPhysicalControlExecution.ts" \
  "$ROOT/apps/api/src/services/scoreboardPhysicalControlReconciliation.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlAudit.ts" \
  "$ROOT/apps/dashboard/app/scoreboards/operations/PhysicalControlDiagnosticsPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

ACCEPT="firmware/esp32-scoreboard/run-physical-control-acceptance.sh"
CHECKLIST="firmware/esp32-scoreboard/PHYSICAL-CONTROL-ACCEPTANCE-CHECKLIST.md"
README="firmware/esp32-scoreboard/README.md"
TEST="packages/core/test/physical-control-acceptance-closeout-14.10.test.ts"

for file in "$ACCEPT" "$CHECKLIST" "$README" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
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
echo " SportsOS Physical Control Acceptance"
echo "============================================================"

echo
echo "[1/6] Core package build"
npm run build --workspace @sportsos/core

echo
echo "[2/6] Repository typecheck"
npm run typecheck

echo
echo "[3/6] Repository tests"
npm test

echo
echo "[4/6] Firmware simulator tests"
node --test firmware/esp32-scoreboard/simulator/test/*.test.js

echo
echo "[5/6] Real ESP32 firmware compile"
bash firmware/esp32-scoreboard/build-in-docker.sh

echo
echo "[6/6] Application build"
npm run build

echo
echo "============================================================"
echo " Physical Control Acceptance: PASS"
echo "============================================================"
echo
echo "Final runtime verification:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
EOF

chmod +x "$ACCEPT"

cat > "$CHECKLIST" <<'EOF'
# SportsOS Physical Control Acceptance Checklist

Milestone 14 closes the physical scoreboard input/control path.

## GPIO input acceptance

- Physical controls use a shared control-input contract.
- GPIO bindings are configurable.
- Active-high and active-low inputs are supported.
- Pull-up/input modes are configurable.
- Button debounce is applied before an event is emitted.
- A held button does not repeatedly emit new presses.
- Press and release edges are tracked.

## Control transport acceptance

- Physical button presses create unique input IDs.
- Each press gets a monotonic sequence number.
- Firmware submits control intent to SportsOS.
- Server validates protocol version.
- Server validates control type.
- Server requires VERIFIED device enrollment.
- Server rejects unassigned devices.

## Duplicate/idempotency acceptance

- Same device sequence cannot be applied twice.
- Duplicate replay returns `IGNORED_DUPLICATE`.
- Offline retry reuses the original sequence number.
- Retries cannot create a second authoritative mutation.

## Authoritative execution acceptance

Accepted physical controls map to server-side command intent for:

- home score +1
- home score -1
- away score +1
- away score -1
- clock start
- clock pause
- clock toggle
- period +1
- period -1
- horn trigger

Score, clock, and period actions re-enter the existing SportsOS API mutation path.

The ESP32 does not directly modify authoritative game state.

## Realtime reconciliation acceptance

- Game/device assignment is revalidated after mutation.
- Automatic scoreboard sync remains the sync source of truth.
- Existing dedupe fingerprint is invalidated after physical mutations.
- Physical scoreboard, dashboard, and broadcast surfaces converge on the next authoritative state.

## Horn/output acceptance

- Horn is treated as a physical side-effect.
- Horn does not become persistent game state.
- Horn routes through the existing scoreboard-device command API.
- No duplicate direct MQTT path is introduced.
- Missing device assignment fails safely.

## Audit/diagnostics acceptance

Each physical-control attempt records:

- input ID
- device ID
- game ID when available
- sequence
- input type
- disposition
- command intent
- execution result
- reconciliation result
- error information
- timestamp

Operator diagnostics expose recent accepted, rejected, duplicate, and execution-failed controls.

## Offline/retry acceptance

- Queue capacity is bounded.
- Retry attempts are bounded.
- Retry delay uses bounded exponential backoff.
- `ACCEPTED`, `REJECTED`, and `IGNORED_DUPLICATE` are terminal.
- Only transport/invalid-response failures retry.
- Queue-full and exhausted retries are diagnostic events.

## Final Milestone 14 gate

Run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash firmware/esp32-scoreboard/run-physical-control-acceptance.sh
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

Milestone 14 is complete when all commands above are green.
EOF

cat >> "$README" <<'EOF'

## Milestone 14.10 — Physical control acceptance / closeout

Milestone 14 provides the complete SportsOS physical scoreboard control foundation:

1. hardware control-input contract
2. GPIO/debounce driver
3. device-to-SportsOS input transport
4. authoritative command mapping
5. server-side game mutation binding
6. realtime scoreboard reconciliation
7. control audit and operator diagnostics
8. physical horn/output binding
9. offline retry/idempotency policy
10. acceptance and closeout

Run the full physical-control acceptance gate with:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash firmware/esp32-scoreboard/run-physical-control-acceptance.sh
```

Then run the container/browser gate:

```bash
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

See `PHYSICAL-CONTROL-ACCEPTANCE-CHECKLIST.md` for the complete closeout criteria.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.10 physical control acceptance / closeout", () => {
  it("adds a complete physical-control acceptance runner", () => {
    const script = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/run-physical-control-acceptance.sh",
        import.meta.url,
      ),
      "utf8",
    );

    for (const command of [
      "npm run build --workspace @sportsos/core",
      "npm run typecheck",
      "npm test",
      "node --test firmware/esp32-scoreboard/simulator/test/*.test.js",
      "build-in-docker.sh",
      "npm run build",
    ]) {
      expect(script).toContain(command);
    }
  });

  it("documents GPIO transport execution reconciliation and retry acceptance", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/PHYSICAL-CONTROL-ACCEPTANCE-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    for (const heading of [
      "GPIO input acceptance",
      "Control transport acceptance",
      "Duplicate/idempotency acceptance",
      "Authoritative execution acceptance",
      "Realtime reconciliation acceptance",
      "Horn/output acceptance",
      "Audit/diagnostics acceptance",
      "Offline/retry acceptance",
    ]) {
      expect(checklist).toContain(
        heading,
      );
    }
  });

  it("requires server authority for game mutations", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/PHYSICAL-CONTROL-ACCEPTANCE-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(checklist).toContain(
      "The ESP32 does not directly modify authoritative game state.",
    );
  });

  it("requires duplicate-safe retry", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/PHYSICAL-CONTROL-ACCEPTANCE-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(checklist).toContain(
      "Offline retry reuses the original sequence number.",
    );

    expect(checklist).toContain(
      "Retries cannot create a second authoritative mutation.",
    );
  });

  it("documents final browser E2E gate", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/PHYSICAL-CONTROL-ACCEPTANCE-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(checklist).toContain(
      "npm run test:e2e:docker",
    );
  });

  it("documents the Milestone 14 closeout runner", () => {
    const readme = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/README.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(readme).toContain(
      "Milestone 14.10",
    );

    expect(readme).toContain(
      "run-physical-control-acceptance.sh",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 14.10 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - full physical-control acceptance runner"
echo "  - GPIO/debounce acceptance criteria"
echo "  - transport/verification acceptance"
echo "  - duplicate/idempotency acceptance"
echo "  - authoritative execution acceptance"
echo "  - realtime reconciliation acceptance"
echo "  - horn/output acceptance"
echo "  - audit/operator diagnostics acceptance"
echo "  - offline retry acceptance"
echo "  - Milestone 14 closeout documentation"
echo "  - Milestone 14.10 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run full Milestone 14 gate:"
echo "  bash firmware/esp32-scoreboard/run-physical-control-acceptance.sh"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Milestone 14 is closed when all gates are green."
