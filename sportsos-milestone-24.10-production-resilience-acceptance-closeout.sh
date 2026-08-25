#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-24.10-resilience-closeout-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

POLICY="apps/api/src/services/broadcastRecoveryPolicy.ts"
HEARTBEAT="apps/api/src/services/broadcastRuntimeHeartbeat.ts"
SUPERVISOR="apps/api/src/services/broadcastResilienceSupervisor.ts"
CONTROLLED="apps/api/src/services/broadcastControlledRecovery.ts"
SNAPSHOT="apps/api/src/services/broadcastRecoverySnapshotStore.ts"
DEST="apps/api/src/services/streamDestinationFailurePolicy.ts"
BUDGET="apps/api/src/services/broadcastResilienceRetryBudget.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
FOCUS="apps/dashboard/app/broadcast/operations/[gameId]/page.tsx"
TEST="packages/core/test/broadcast-resilience-acceptance-24.10.test.ts"
REPORT="docs/MILESTONE-24-BROADCAST-RESILIENCE-ACCEPTANCE.md"
DOC="docs/BROADCAST-RESILIENCE.md"

for required in \
  ".git" \
  "$POLICY" \
  "$HEARTBEAT" \
  "$SUPERVISOR" \
  "$CONTROLLED" \
  "$SNAPSHOT" \
  "$DEST" \
  "$BUDGET" \
  "$ROUTE" \
  "$FOCUS" \
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

node <<'NODE'
const fs=require("fs");

const files = {
  policy: fs.readFileSync("apps/api/src/services/broadcastRecoveryPolicy.ts","utf8"),
  heartbeat: fs.readFileSync("apps/api/src/services/broadcastRuntimeHeartbeat.ts","utf8"),
  supervisor: fs.readFileSync("apps/api/src/services/broadcastResilienceSupervisor.ts","utf8"),
  controlled: fs.readFileSync("apps/api/src/services/broadcastControlledRecovery.ts","utf8"),
  snapshot: fs.readFileSync("apps/api/src/services/broadcastRecoverySnapshotStore.ts","utf8"),
  destination: fs.readFileSync("apps/api/src/services/streamDestinationFailurePolicy.ts","utf8"),
  budget: fs.readFileSync("apps/api/src/services/broadcastResilienceRetryBudget.ts","utf8"),
  route: fs.readFileSync("apps/api/src/routes/broadcastSessionCoordinator.ts","utf8"),
  focus: fs.readFileSync("apps/dashboard/app/broadcast/operations/[gameId]/page.tsx","utf8"),
};

const checks = [
  ["24.1 recovery policy", files.policy, "evaluateBroadcastRecovery"],
  ["24.2 runtime heartbeat", files.heartbeat, "evaluateBroadcastRuntimeHeartbeat"],
  ["24.3 resilience supervisor", files.supervisor, "evaluateBroadcastResilienceSupervisor"],
  ["24.4 controlled recovery", files.controlled, "executeControlledBroadcastRecovery"],
  ["24.5 recovery persistence", files.snapshot, "broadcast-recovery-snapshots.json"],
  ["24.6 destination failure policy", files.destination, "classifyStreamDestinationFailure"],
  ["24.7 retry budget", files.budget, "evaluateResilienceRetryBudget"],
  ["24.8 telemetry API", files.route, '"/broadcast-coordinator/:gameId/resilience-status"'],
  ["24.8 telemetry UI", files.focus, "Resilience Telemetry"],
  ["24.9 chaos suite prerequisite", fs.existsSync("packages/core/test/broadcast-resilience-chaos-24.9.test.ts") ? "present" : "", "present"],
];

for (const [name, source, needle] of checks) {
  if (!source.includes(needle)) {
    throw new Error(`Milestone 24 prerequisite missing: ${name} (${needle})`);
  }
}
NODE

mkdir -p "$(dirname "$TEST")" "$(dirname "$REPORT")"

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 24.10 production resilience acceptance", () => {
  const policy=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastRecoveryPolicy.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const heartbeat=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastRuntimeHeartbeat.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const supervisor=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastResilienceSupervisor.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const controlled=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastControlledRecovery.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const snapshot=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastRecoverySnapshotStore.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const destination=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/streamDestinationFailurePolicy.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const budget=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastResilienceRetryBudget.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const focus=
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/[gameId]/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("retains fail-safe recovery policy",()=> {
    expect(policy).toContain("require-operator-review");
    expect(policy).toContain("request-controlled-stop");
    expect(policy).toContain("request-controlled-start");
    expect(policy).toContain("startup-grace-period");
  });

  it("retains stale/missing heartbeat detection",()=> {
    expect(heartbeat).toContain('"STALE"');
    expect(heartbeat).toContain('"MISSING"');
    expect(heartbeat).toContain('"UNKNOWN"');
  });

  it("retains heartbeat + recovery supervisor composition",()=> {
    expect(supervisor).toContain("evaluateBroadcastRuntimeHeartbeat");
    expect(supervisor).toContain("evaluateBroadcastRecovery");
  });

  it("keeps recovery operator-controlled",()=> {
    expect(controlled).toContain("Operator name is required.");
    expect(controlled).toContain("approveDestructive");
    expect(controlled).toContain("RECOVERY_REFUSED");
  });

  it("does not let controlled recovery directly manipulate encoder runtime",()=> {
    expect(controlled).not.toContain("startEncoderRuntime");
    expect(controlled).not.toContain("stopEncoderRuntime");
  });

  it("retains persistent restart/crash context",()=> {
    expect(snapshot).toContain("SPORTSOS_DATA_DIR");
    expect(snapshot).toContain("broadcast-recovery-snapshots.json");
  });

  it("retains destination failure classification",()=> {
    expect(destination).toContain('"AUTHENTICATION"');
    expect(destination).toContain('"TRANSIENT_NETWORK"');
    expect(destination).toContain('"RATE_LIMITED"');
    expect(destination).toContain('"TIMEOUT"');
  });

  it("retains bounded retry budget and backoff",()=> {
    expect(budget).toContain("DEFAULT_MAX_ATTEMPTS");
    expect(budget).toContain("DEFAULT_BASE_DELAY_MS");
    expect(budget).toContain("DEFAULT_MAX_DELAY_MS");
    expect(budget).toContain("EXHAUSTED");
    expect(budget).toContain("REFUSED");
  });

  it("retains resilience operator visibility",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/resilience-status"');
    expect(focus).toContain("Resilience Telemetry");
    expect(focus).toContain("Controlled Recovery");
  });

  it("retains chaos regression suite",()=> {
    const chaos=
      fs.readFileSync(
        new URL(
          "../../../packages/core/test/broadcast-resilience-chaos-24.9.test.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(chaos).toContain("failure injection / chaos regression tests");
    expect(chaos).toContain("retry budget");
    expect(chaos).toContain("require-operator-review");
  });
});
EOF

cat > "$REPORT" <<'EOF'
# SportsOS Milestone 24 — Broadcast Resilience Acceptance

Milestone 24 completes the first production-hardening pass for broadcast resilience.

## Accepted capabilities

- deterministic recovery policy
- runtime heartbeat / stale-process detection
- coordinator/runtime reconciliation supervisor
- operator-approved controlled recovery
- restart/crash recovery snapshots
- stream destination failure classification
- bounded retry budgets and exponential backoff
- resilience telemetry in Focus Mode
- deterministic failure-injection / chaos regression coverage

## Safety invariants

The resilience layer must never silently perform an unsafe destructive action.

Specifically:

- missing runtime does not auto-start FFmpeg
- unexpected live runtime does not auto-stop without approval
- stale/failed/unknown runtime requires operator review
- destructive recovery requires explicit operator approval
- destination auth/config failures do not retry blindly
- retryable failures remain bounded by a retry budget
- exhausted budgets stop retrying
- startup grace prevents recovery flapping
- persistence is context only and does not auto-execute recovery

## Production acceptance gate

Milestone 24 is accepted only when all of the following are green:

```text
npm run typecheck
npm test
docker compose up -d --build api dashboard
docker compose ps
curl -fsS http://127.0.0.1:4001/health
npm run test:e2e:docker
```

The API must remain healthy after the combined Compose startup.

## Closeout

After acceptance, commit and tag Milestone 24 before beginning Milestone 25.
EOF

cat >> "$DOC" <<'EOF'

## Milestone 24.10 — Production resilience acceptance / closeout

Milestone 24 acceptance is documented in:

```text
docs/MILESTONE-24-BROADCAST-RESILIENCE-ACCEPTANCE.md
```

The closeout regression suite verifies recovery policy, heartbeat detection, resilience supervision, controlled recovery, restart/crash persistence, destination failure classification, retry budgets, operator telemetry, and failure-injection coverage.

Milestone 24 is complete only after typecheck, unit tests, combined API/dashboard Docker startup, API health verification, and Docker E2E tests are all green.
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 24.10 installed"
echo "============================================================"
echo "Added:"
echo "  - Milestone 24 prerequisite validation"
echo "  - production resilience acceptance regression suite"
echo "  - resilience safety invariant checks"
echo "  - production Docker health acceptance"
echo "  - Milestone 24 acceptance document"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Acceptance run:"
echo "  npm run typecheck && npm test"
echo "  docker compose up -d --build api dashboard"
echo "  docker compose ps"
echo "  curl -fsS http://127.0.0.1:4001/health"
echo "  npm run test:e2e:docker"
echo
echo "If everything is green:"
echo '  git add -A'
echo '  git commit -m "feat(broadcast): complete milestone 24 resilience hardening"'
echo '  git tag -a sportsos-m24-complete -m "SportsOS Milestone 24 complete"'
echo
echo "Next after commit/tag:"
echo "  Milestone 25 - Broadcast Deployment / Release Readiness"
