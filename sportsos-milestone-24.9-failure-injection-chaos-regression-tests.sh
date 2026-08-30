#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-24.9-chaos-regression-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

TEST="packages/core/test/broadcast-resilience-chaos-24.9.test.ts"
DOC="docs/BROADCAST-RESILIENCE.md"

for required in \
  ".git" \
  "apps/api/src/services/broadcastRecoveryPolicy.ts" \
  "apps/api/src/services/broadcastRuntimeHeartbeat.ts" \
  "apps/api/src/services/broadcastResilienceSupervisor.ts" \
  "apps/api/src/services/streamDestinationFailurePolicy.ts" \
  "apps/api/src/services/broadcastResilienceRetryBudget.ts" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";

import {
  evaluateBroadcastRecovery,
} from "../../../apps/api/src/services/broadcastRecoveryPolicy";

import {
  evaluateBroadcastRuntimeHeartbeat,
} from "../../../apps/api/src/services/broadcastRuntimeHeartbeat";

import {
  evaluateBroadcastResilienceSupervisor,
} from "../../../apps/api/src/services/broadcastResilienceSupervisor";

import {
  classifyStreamDestinationFailure,
} from "../../../apps/api/src/services/streamDestinationFailurePolicy";

import {
  evaluateResilienceRetryBudget,
} from "../../../apps/api/src/services/broadcastResilienceRetryBudget";

describe("Milestone 24.9 failure injection / chaos regression tests", () => {
  it("fails safe when heartbeat disappears during intended live state",()=> {
    const result=
      evaluateBroadcastResilienceSupervisor({
        coordinatorIntent:
          "GO_LIVE",
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          null,
        stateAgeMs:
          60_000,
      });

    expect(
      result.heartbeat.state,
    ).toBe(
      "MISSING",
    );

    expect(
      result.recovery.action,
    ).toBe(
      "require-operator-review",
    );

    expect(
      result.recovery.automatic,
    ).toBe(
      false,
    );
  });

  it("fails safe when runtime heartbeat is stale",()=> {
    const now=
      1_000_000;

    const result=
      evaluateBroadcastResilienceSupervisor({
        coordinatorIntent:
          "GO_LIVE",
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          new Date(
            now -
            120_000,
          ).toISOString(),
        stateAgeMs:
          120_000,
        nowMs:
          now,
      });

    expect(
      result.heartbeat.state,
    ).toBe(
      "STALE",
    );

    expect(
      result.recovery.action,
    ).toBe(
      "require-operator-review",
    );
  });

  it("does not silently recover failed runtime",()=> {
    const result=
      evaluateBroadcastRecovery({
        coordinatorIntent:
          "live",
        runtimeState:
          "failed",
        stateAgeMs:
          60_000,
      });

    expect(
      result.action,
    ).toBe(
      "require-operator-review",
    );

    expect(
      result.automatic,
    ).toBe(
      false,
    );
  });

  it("does not silently kill unexpected live runtime",()=> {
    const result=
      evaluateBroadcastRecovery({
        coordinatorIntent:
          "stopped",
        runtimeState:
          "live",
        stateAgeMs:
          60_000,
      });

    expect(
      result.action,
    ).toBe(
      "request-controlled-stop",
    );

    expect(
      result.destructive,
    ).toBe(
      true,
    );

    expect(
      result.automatic,
    ).toBe(
      false,
    );
  });

  it("treats destination auth failure as non-retryable",()=> {
    const failure=
      classifyStreamDestinationFailure({
        ok:
          false,
        statusCode:
          401,
      });

    const budget=
      evaluateResilienceRetryBudget({
        attempts:
          0,
        failure,
      });

    expect(
      failure.failureClass,
    ).toBe(
      "AUTHENTICATION",
    );

    expect(
      budget.state,
    ).toBe(
      "REFUSED",
    );

    expect(
      budget.retryAllowed,
    ).toBe(
      false,
    );
  });

  it("backs off transient remote failure",()=> {
    const failure=
      classifyStreamDestinationFailure({
        ok:
          false,
        statusCode:
          503,
      });

    const budget=
      evaluateResilienceRetryBudget({
        attempts:
          2,
        failure,
      });

    expect(
      failure.retryable,
    ).toBe(
      true,
    );

    expect(
      budget.state,
    ).toBe(
      "SCHEDULED",
    );

    expect(
      budget.delayMs,
    ).toBe(
      20_000,
    );
  });

  it("exhausts retry budget instead of retrying forever",()=> {
    const failure=
      classifyStreamDestinationFailure({
        ok:
          false,
        errorCode:
          "ECONNRESET",
      });

    const budget=
      evaluateResilienceRetryBudget({
        attempts:
          5,
        maxAttempts:
          5,
        failure,
      });

    expect(
      budget.state,
    ).toBe(
      "EXHAUSTED",
    );

    expect(
      budget.retryAllowed,
    ).toBe(
      false,
    );
  });

  it("uses startup grace to prevent recovery flapping",()=> {
    const result=
      evaluateBroadcastRecovery({
        coordinatorIntent:
          "live",
        runtimeState:
          "idle",
        stateAgeMs:
          3_000,
      });

    expect(
      result.action,
    ).toBe(
      "observe",
    );

    expect(
      result.automatic,
    ).toBe(
      true,
    );
  });

  it("detects stale transitional runtime without destructive automation",()=> {
    const result=
      evaluateBroadcastRecovery({
        coordinatorIntent:
          "live",
        runtimeState:
          "starting",
        stateAgeMs:
          90_000,
      });

    expect(
      result.action,
    ).toBe(
      "require-operator-review",
    );

    expect(
      result.destructive,
    ).toBe(
      false,
    );
  });

  it("treats malformed heartbeat timestamp conservatively",()=> {
    const result=
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          "definitely-not-a-date",
      });

    expect(
      result.state,
    ).toBe(
      "UNKNOWN",
    );

    expect(
      result.stale,
    ).toBe(
      true,
    );
  });

  it("survives repeated transient failures without exceeding cap",()=> {
    const failure=
      classifyStreamDestinationFailure({
        ok:
          false,
        errorCode:
          "ECONNREFUSED",
      });

    const delays=
      Array.from(
        {
          length:
            10,
        },
        (
          _,
          attempts,
        ) =>
          evaluateResilienceRetryBudget({
            attempts,
            maxAttempts:
              20,
            failure,
          }).delayMs,
      );

    for (
      const delay
      of delays
    ) {
      expect(
        delay,
      ).not.toBeNull();

      expect(
        delay!,
      ).toBeLessThanOrEqual(
        120_000,
      );
    }
  });
});
EOF

cat >> "$DOC" <<'EOF'

## Milestone 24.9 — Failure injection / chaos regression tests

The resilience layer now includes deterministic failure-injection coverage for:

- missing heartbeat during intended live state
- stale heartbeat
- failed encoder runtime
- unexpected live runtime after stop intent
- authentication failure
- transient remote 5xx failure
- transient network failure
- retry budget exhaustion
- startup grace / anti-flapping behavior
- stale starting transitions
- malformed heartbeat timestamps
- repeated retry attempts under maximum-delay caps

These tests intentionally exercise failure states without starting real encoders or requiring live stream destinations.

The acceptance condition is fail-safe behavior:

```text
ambiguous / unsafe -> operator review
destructive action -> never automatic
retryable failure  -> bounded retry
non-retryable      -> refused
retry budget spent -> exhausted
startup transition -> grace before recovery
```
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 24.9 installed"
echo "============================================================"
echo "Added:"
echo "  - resilience failure-injection suite"
echo "  - stale/missing heartbeat scenarios"
echo "  - runtime failure scenarios"
echo "  - destination outage scenarios"
echo "  - retry exhaustion scenarios"
echo "  - anti-flap regression coverage"
echo "  - fail-safe recovery assertions"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  docker compose ps"
echo "  curl -fsS http://127.0.0.1:4001/health"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 24.10 - Production Resilience Acceptance / Closeout"
