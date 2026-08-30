#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-22.10-broadcast-automation-closeout-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

COORD="apps/api/src/services/broadcastSessionCoordinator.ts"
SUPERVISOR="apps/api/src/services/broadcastSessionCoordinatorSupervisor.ts"
AUDIT="apps/api/src/services/broadcastCoordinatorAudit.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
APP="apps/api/src/app.ts"
DOC="docs/BROADCAST-COORDINATOR.md"
TEST="packages/core/test/broadcast-automation-acceptance-22.10.test.ts"
REPORT="docs/MILESTONE-22-BROADCAST-AUTOMATION-ACCEPTANCE.md"

for required in \
  ".git" \
  "$COORD" \
  "$SUPERVISOR" \
  "$AUDIT" \
  "$ROUTE" \
  "$APP" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$TEST" "$REPORT" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

# Fail before modification if the Milestone 22 chain is incomplete.
node <<'NODE'
const fs=require("fs");

const files = {
  coordinator: fs.readFileSync("apps/api/src/services/broadcastSessionCoordinator.ts","utf8"),
  supervisor: fs.readFileSync("apps/api/src/services/broadcastSessionCoordinatorSupervisor.ts","utf8"),
  audit: fs.readFileSync("apps/api/src/services/broadcastCoordinatorAudit.ts","utf8"),
  route: fs.readFileSync("apps/api/src/routes/broadcastSessionCoordinator.ts","utf8"),
  app: fs.readFileSync("apps/api/src/app.ts","utf8"),
};

const checks = [
  ["22.1 coordinator service", files.coordinator, "BroadcastCoordinator"],
  ["22.3 health evaluator", files.coordinator, "evaluateBroadcastCoordinatorHealth"],
  ["22.4 reconciliation", files.coordinator, "reconcileBroadcastCoordinator"],
  ["22.5 audit", files.audit, "recordBroadcastCoordinatorAudit"],
  ["22.6 retry policy", files.coordinator, "BroadcastCoordinatorRetry"],
  ["22.7 supervisor tick", files.coordinator, "runBroadcastCoordinatorSupervisorTick"],
  ["22.8 supervisor runtime", files.supervisor, "startBroadcastCoordinatorSupervisor"],
  ["22.9 active discovery", files.coordinator, "listActiveBroadcastGameIds"],
  ["22.9 lifecycle wiring", files.app, "gameIds: () => listActiveBroadcastGameIds()"],
  ["active discovery API", files.route, '"/broadcast-coordinator/active"'],
];

for (const [name, source, needle] of checks) {
  if (!source.includes(needle)) {
    throw new Error(`Milestone 22 prerequisite missing: ${name} (${needle})`);
  }
}
NODE

mkdir -p "$(dirname "$TEST")" "$(dirname "$REPORT")"

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.10 broadcast automation acceptance", () => {
  const coordinator=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/broadcastSessionCoordinator.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const supervisor=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/broadcastSessionCoordinatorSupervisor.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const audit=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/broadcastCoordinatorAudit.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route=fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const app=fs.readFileSync(
    new URL(
      "../../../apps/api/src/app.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("retains coordinator health and bounded reconciliation",()=> {
    expect(coordinator).toContain("evaluateBroadcastCoordinatorHealth");
    expect(coordinator).toContain("reconcileBroadcastCoordinator");
    expect(coordinator).toContain('"REFUSE_AMBIGUOUS"');
  });

  it("retains bounded retry and supervisor behavior",()=> {
    expect(coordinator).toContain("BroadcastCoordinatorRetry");
    expect(coordinator).toContain("runBroadcastCoordinatorSupervisorTick");
    expect(coordinator).toContain('"EXHAUSTED"');
  });

  it("retains persistent automation audit history",()=> {
    expect(audit).toContain("broadcast-coordinator-audit.json");
    expect(audit).toContain('"DRIFT_DETECTED"');
    expect(audit).toContain('"RECONCILE_REFUSED"');
    expect(audit).toContain('"SUPERVISOR_TICK_FAILED"');
  });

  it("uses controlled runtime scheduling and clean shutdown",()=> {
    expect(supervisor).toContain("setInterval");
    expect(supervisor).toContain("clearInterval");
    expect(supervisor).toContain("runBroadcastCoordinatorSupervisorTick");
    expect(app).toContain("stopBroadcastCoordinatorSupervisor?.()");
  });

  it("uses authoritative active broadcast discovery",()=> {
    expect(coordinator).toContain("listActiveBroadcastGameIds");
    expect(app).toContain("gameIds: () => listActiveBroadcastGameIds()");
    expect(app).not.toContain("gameIds: () => []");
  });

  it("does not let the supervisor runtime directly start a broadcast",()=> {
    expect(supervisor).not.toContain("startEncoderRuntime");
    expect(supervisor).not.toContain("startCoordinatedBroadcast");
  });

  it("keeps operator-facing inspection endpoints",()=> {
    expect(route).toContain('"/broadcast-coordinator/active"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/health"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/audit"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/retry"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/supervisor/tick"');
  });
});
EOF

cat > "$REPORT" <<'EOF'
# SportsOS Milestone 22 — Broadcast Automation Acceptance

Milestone 22 closes the first production-safety pass for broadcast automation.

## Accepted capabilities

- broadcast-session coordinator
- composed coordinator / go-live / encoder snapshots
- health and drift detection
- bounded safe reconciliation
- persistent coordinator audit history
- bounded retry policy and backoff
- single supervisor tick
- application-lifecycle supervisor scheduler
- authoritative active-broadcast discovery

## Safety invariants

The automation layer must not create a second authoritative game lifecycle.

The supervisor runtime must not directly:

- start FFmpeg
- arm a go-live session
- mark a broadcast LIVE
- bypass final game-day go-live preflight
- silently repair ambiguous drift

Ambiguous conditions remain operator-review conditions.

## Operational inspection

```text
GET  /broadcast-coordinator/active
GET  /broadcast-coordinator/:gameId
GET  /broadcast-coordinator/:gameId/health
GET  /broadcast-coordinator/:gameId/audit
GET  /broadcast-coordinator/:gameId/retry
POST /broadcast-coordinator/:gameId/reconcile
POST /broadcast-coordinator/:gameId/supervisor/tick
```

## Acceptance gate

Milestone 22 is accepted only after all of the following are green:

```text
npm run typecheck
npm test
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

After acceptance, create a clean commit and annotated tag before beginning Milestone 23.
EOF

cat >> "$DOC" <<'EOF'

## Milestone 22.10 — Broadcast automation acceptance / closeout

Milestone 22 acceptance is documented in:

```text
docs/MILESTONE-22-BROADCAST-AUTOMATION-ACCEPTANCE.md
```

The closeout regression test verifies that health/drift detection, bounded reconciliation, retry/backoff, audit history, supervisor scheduling, clean shutdown, and authoritative active-broadcast discovery remain wired together.

Milestone 22 is not considered complete until typecheck, unit tests, rebuilt API/dashboard containers, and Docker E2E tests are all green.
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 22.10 installed"
echo "============================================================"
echo "Added:"
echo "  - Milestone 22 prerequisite validation"
echo "  - broadcast automation acceptance regression suite"
echo "  - production safety invariant checks"
echo "  - active-discovery lifecycle verification"
echo "  - operator inspection endpoint verification"
echo "  - Milestone 22 acceptance document"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Acceptance run:"
echo "  npm run typecheck && npm test"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "If everything is green:"
echo '  git add -A'
echo '  git commit -m "feat(broadcast): complete milestone 22 automation safety"'
echo '  git tag -a sportsos-m22-complete -m "SportsOS Milestone 22 complete"'
echo
echo "Next after commit/tag:"
echo "  Milestone 23 - Broadcast Operations / Operator Experience"
