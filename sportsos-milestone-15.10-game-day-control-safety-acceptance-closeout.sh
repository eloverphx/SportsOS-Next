#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-15.10-game-day-control-safety-closeout-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/services/scoreboardControlPolicy.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlAuthorization.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlLifecyclePolicy.ts" \
  "$ROOT/apps/api/src/services/scoreboardEmergencyControlLock.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlPolicyAudit.ts" \
  "$ROOT/apps/api/src/services/scoreboardPhysicalControlHealth.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlAudit.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlIncidentResolution.ts" \
  "$ROOT/apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

RUNNER="scripts/run-game-day-control-safety-acceptance.sh"
CHECKLIST="docs/GAME-DAY-CONTROL-SAFETY-ACCEPTANCE.md"
TEST="packages/core/test/game-day-control-safety-closeout-15.10.test.ts"

for file in "$RUNNER" "$CHECKLIST" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$RUNNER")" "$(dirname "$CHECKLIST")" "$(dirname "$TEST")"

cat > "$RUNNER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

echo "============================================================"
echo " SportsOS Game-Day Control Safety Acceptance"
echo "============================================================"

echo
echo "[1/5] Core build"
npm run build --workspace @sportsos/core

echo
echo "[2/5] Repository typecheck"
npm run typecheck

echo
echo "[3/5] Repository tests"
npm test

echo
echo "[4/5] Production application build"
npm run build

echo
echo "[5/5] Milestone 15 contract presence"
test -f apps/api/src/services/scoreboardControlPolicy.ts
test -f apps/api/src/services/scoreboardControlAuthorization.ts
test -f apps/api/src/services/scoreboardControlLifecyclePolicy.ts
test -f apps/api/src/services/scoreboardEmergencyControlLock.ts
test -f apps/api/src/services/scoreboardControlPolicyAudit.ts
test -f apps/api/src/services/scoreboardPhysicalControlHealth.ts
test -f apps/api/src/services/scoreboardControlIncidentResolution.ts

echo
echo "============================================================"
echo " Game-Day Control Safety Acceptance: PASS"
echo "============================================================"
echo
echo "Final container/browser gate:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
EOF

chmod +x "$RUNNER"

cat > "$CHECKLIST" <<'EOF'
# SportsOS Game-Day Control Safety Acceptance

Milestone 15 closes the server-authoritative safety and permission layer around physical scoreboard controls.

## 15.1 Physical-control enable / lockout policy

- Server owns physical-control policy state.
- GAME, DEVICE, and GAME_DEVICE scopes are supported.
- ENABLED and LOCKED modes are supported.
- Locked controls are rejected before authoritative game mutation.
- Dashboard/localStorage state is not authority.

## 15.2 Operator lockout controls

- Operators can view active policies.
- Operators can enable or lock supported scopes.
- Operators can include a reason.
- Operators can remove explicit policies.
- UI writes only through the server policy API.

## 15.3 Game lifecycle auto-lock

- Physical controls are automatically constrained by authoritative game lifecycle.
- Active lifecycle states may accept controls.
- Final/completed/cancelled/postponed states are locked.
- Lifecycle is checked before authoritative mutation.
- Ambiguous lifecycle fails closed when an authoritative lifecycle route exists.

## 15.4 Role / permission enforcement

- Policy read and write permissions are distinct.
- Elevated operator roles are required for policy mutation.
- Device-originated controls remain authenticated as VERIFIED devices rather than human users.
- Role authority is not accepted from arbitrary request headers.

## 15.5 Policy-change audit / actor attribution

Policy changes record:

- actor user ID
- actor roles
- action
- prior policy
- next policy
- operator reason
- timestamp

## 15.6 Emergency physical-control kill switch

- A global emergency lock can immediately block physical mutations.
- Activation requires a reason.
- The lock is persistent and server-authoritative.
- Activation/clear operations require permission.
- Lock state is checked before authoritative execution.
- Rejected controls receive HTTP 423 while the emergency lock is active.

## 15.7 Health / safety status

The operator surface exposes:

- SAFE
- RESTRICTED
- EMERGENCY_LOCKED
- global physical-input availability
- number of locked policy scopes
- emergency-lock state

## 15.8 Incident / rejection timeline

Rejected or failed physical-control attempts surface:

- device ID
- game ID
- input ID
- input type
- sequence
- disposition
- error/rejection reason
- timestamp

## 15.9 Incident acknowledgement / resolution

- Incidents support OPEN, ACKNOWLEDGED, and RESOLVED states.
- Incident updates are actor-attributed.
- Resolving requires a note.
- Incident changes require elevated write permission.
- Operator UI exposes acknowledge and resolve actions.

## Final Milestone 15 gate

Run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash scripts/run-game-day-control-safety-acceptance.sh
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

Milestone 15 is complete when all commands are green.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 15.10 game-day control safety acceptance / closeout", () => {
  const runner = fs.readFileSync(
    new URL(
      "../../../scripts/run-game-day-control-safety-acceptance.sh",
      import.meta.url,
    ),
    "utf8",
  );

  const checklist = fs.readFileSync(
    new URL(
      "../../../docs/GAME-DAY-CONTROL-SAFETY-ACCEPTANCE.md",
      import.meta.url,
    ),
    "utf8",
  );

  it("adds the full Milestone 15 acceptance runner", () => {
    for (const command of [
      "npm run build --workspace @sportsos/core",
      "npm run typecheck",
      "npm test",
      "npm run build",
    ]) {
      expect(runner).toContain(command);
    }
  });

  it("covers every Milestone 15 safety layer", () => {
    for (const heading of [
      "15.1 Physical-control enable / lockout policy",
      "15.2 Operator lockout controls",
      "15.3 Game lifecycle auto-lock",
      "15.4 Role / permission enforcement",
      "15.5 Policy-change audit / actor attribution",
      "15.6 Emergency physical-control kill switch",
      "15.7 Health / safety status",
      "15.8 Incident / rejection timeline",
      "15.9 Incident acknowledgement / resolution",
    ]) {
      expect(checklist).toContain(heading);
    }
  });

  it("requires server authority for safety decisions", () => {
    expect(checklist).toContain(
      "Server owns physical-control policy state.",
    );

    expect(checklist).toContain(
      "Dashboard/localStorage state is not authority.",
    );
  });

  it("requires emergency lock enforcement before mutation", () => {
    expect(checklist).toContain(
      "Lock state is checked before authoritative execution.",
    );
  });

  it("documents the final browser E2E gate", () => {
    expect(checklist).toContain(
      "npm run test:e2e:docker",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 15.10 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - Game-Day Control Safety acceptance runner"
echo "  - complete Milestone 15 closeout checklist"
echo "  - policy/permission/lifecycle acceptance"
echo "  - emergency lock acceptance"
echo "  - audit/actor attribution acceptance"
echo "  - health/status acceptance"
echo "  - incident timeline and resolution acceptance"
echo "  - Milestone 15.10 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  bash scripts/run-game-day-control-safety-acceptance.sh"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Milestone 15 is closed when all gates are green."
