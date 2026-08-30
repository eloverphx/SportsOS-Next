#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-24.1-broadcast-recovery-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/broadcastRecoveryPolicy.ts"
TEST="packages/core/test/broadcast-recovery-policy-24.1.test.ts"
DOC="docs/BROADCAST-RESILIENCE.md"
M23="docs/MILESTONE-23-BROADCAST-OPERATIONS-ACCEPTANCE.md"

for required in ".git" "package.json" "apps/api/src/services" "packages/core/test"; do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    exit 1
  }
done

[[ -f "$M23" ]] || {
  echo "ERROR: Milestone 23 acceptance document is missing."
  echo "Complete 23.10 before starting Milestone 24."
  exit 1
}

mkdir -p "$BACKUP"
for file in "$SERVICE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")" "$(dirname "$DOC")"

cat > "$SERVICE" <<'EOF'
export type BroadcastRecoveryRuntimeState =
  | "idle"
  | "starting"
  | "live"
  | "stopping"
  | "failed"
  | "unknown";

export type BroadcastRecoveryCoordinatorIntent =
  | "idle"
  | "live"
  | "stopped";

export type BroadcastRecoveryAction =
  | "none"
  | "observe"
  | "reconcile-to-idle"
  | "request-controlled-start"
  | "request-controlled-stop"
  | "require-operator-review";

export type BroadcastRecoveryReason =
  | "state-consistent"
  | "startup-grace-period"
  | "runtime-missing"
  | "unexpected-runtime"
  | "runtime-transition-stale"
  | "runtime-failed"
  | "runtime-state-unknown";

export interface BroadcastRecoveryInput {
  coordinatorIntent: BroadcastRecoveryCoordinatorIntent;
  runtimeState: BroadcastRecoveryRuntimeState;
  stateAgeMs: number;
  startupGraceMs?: number;
  transitionTimeoutMs?: number;
}

export interface BroadcastRecoveryDecision {
  action: BroadcastRecoveryAction;
  reason: BroadcastRecoveryReason;
  automatic: boolean;
  destructive: boolean;
}

const DEFAULT_STARTUP_GRACE_MS = 30_000;
const DEFAULT_TRANSITION_TIMEOUT_MS = 45_000;

export function evaluateBroadcastRecovery(
  input: BroadcastRecoveryInput,
): BroadcastRecoveryDecision {
  const startupGraceMs =
    input.startupGraceMs ?? DEFAULT_STARTUP_GRACE_MS;
  const transitionTimeoutMs =
    input.transitionTimeoutMs ?? DEFAULT_TRANSITION_TIMEOUT_MS;

  if (!Number.isFinite(input.stateAgeMs) || input.stateAgeMs < 0) {
    return {
      action: "require-operator-review",
      reason: "runtime-state-unknown",
      automatic: false,
      destructive: false,
    };
  }

  if (input.runtimeState === "unknown") {
    return {
      action: "require-operator-review",
      reason: "runtime-state-unknown",
      automatic: false,
      destructive: false,
    };
  }

  if (input.runtimeState === "failed") {
    return {
      action: "require-operator-review",
      reason: "runtime-failed",
      automatic: false,
      destructive: false,
    };
  }

  if (
    (input.runtimeState === "starting" ||
      input.runtimeState === "stopping") &&
    input.stateAgeMs > transitionTimeoutMs
  ) {
    return {
      action: "require-operator-review",
      reason: "runtime-transition-stale",
      automatic: false,
      destructive: false,
    };
  }

  if (input.stateAgeMs < startupGraceMs) {
    return {
      action: "observe",
      reason: "startup-grace-period",
      automatic: true,
      destructive: false,
    };
  }

  if (
    input.coordinatorIntent === "live" &&
    input.runtimeState === "idle"
  ) {
    return {
      action: "request-controlled-start",
      reason: "runtime-missing",
      automatic: false,
      destructive: false,
    };
  }

  if (
    input.coordinatorIntent !== "live" &&
    input.runtimeState === "live"
  ) {
    return {
      action: "request-controlled-stop",
      reason: "unexpected-runtime",
      automatic: false,
      destructive: true,
    };
  }

  if (
    input.coordinatorIntent === "stopped" &&
    input.runtimeState === "idle"
  ) {
    return {
      action: "reconcile-to-idle",
      reason: "state-consistent",
      automatic: true,
      destructive: false,
    };
  }

  return {
    action: "none",
    reason: "state-consistent",
    automatic: true,
    destructive: false,
  };
}
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  evaluateBroadcastRecovery,
} from "../../../apps/api/src/services/broadcastRecoveryPolicy";

describe("Milestone 24.1 broadcast recovery policy", () => {
  it("does not restart a missing live runtime automatically", () => {
    expect(
      evaluateBroadcastRecovery({
        coordinatorIntent: "live",
        runtimeState: "idle",
        stateAgeMs: 60_000,
      }),
    ).toEqual({
      action: "request-controlled-start",
      reason: "runtime-missing",
      automatic: false,
      destructive: false,
    });
  });

  it("does not stop an unexpected runtime automatically", () => {
    expect(
      evaluateBroadcastRecovery({
        coordinatorIntent: "stopped",
        runtimeState: "live",
        stateAgeMs: 60_000,
      }),
    ).toEqual({
      action: "request-controlled-stop",
      reason: "unexpected-runtime",
      automatic: false,
      destructive: true,
    });
  });

  it("observes during startup grace instead of flapping state", () => {
    const result = evaluateBroadcastRecovery({
      coordinatorIntent: "live",
      runtimeState: "idle",
      stateAgeMs: 5_000,
    });

    expect(result.action).toBe("observe");
    expect(result.automatic).toBe(true);
    expect(result.destructive).toBe(false);
  });

  it("escalates stale transitions to operator review", () => {
    const result = evaluateBroadcastRecovery({
      coordinatorIntent: "live",
      runtimeState: "starting",
      stateAgeMs: 60_000,
    });

    expect(result.action).toBe("require-operator-review");
    expect(result.reason).toBe("runtime-transition-stale");
    expect(result.automatic).toBe(false);
  });

  it("escalates failed runtime state", () => {
    const result = evaluateBroadcastRecovery({
      coordinatorIntent: "live",
      runtimeState: "failed",
      stateAgeMs: 60_000,
    });

    expect(result.action).toBe("require-operator-review");
    expect(result.reason).toBe("runtime-failed");
  });

  it("escalates unknown runtime state", () => {
    const result = evaluateBroadcastRecovery({
      coordinatorIntent: "live",
      runtimeState: "unknown",
      stateAgeMs: 60_000,
    });

    expect(result.action).toBe("require-operator-review");
    expect(result.reason).toBe("runtime-state-unknown");
  });

  it("allows non-destructive reconciliation when stopped runtime is idle", () => {
    const result = evaluateBroadcastRecovery({
      coordinatorIntent: "stopped",
      runtimeState: "idle",
      stateAgeMs: 60_000,
    });

    expect(result.action).toBe("reconcile-to-idle");
    expect(result.automatic).toBe(true);
    expect(result.destructive).toBe(false);
  });

  it("rejects invalid state age conservatively", () => {
    const result = evaluateBroadcastRecovery({
      coordinatorIntent: "live",
      runtimeState: "idle",
      stateAgeMs: -1,
    });

    expect(result.action).toBe("require-operator-review");
    expect(result.automatic).toBe(false);
  });
});
EOF

cat > "$DOC" <<'EOF'
# SportsOS Broadcast Resilience

## Milestone 24.1 — Recovery policy foundation

Milestone 24 begins production hardening of the broadcast lifecycle.

The first resilience layer is intentionally a **decision policy**, not an
automatic FFmpeg watchdog. It compares coordinator intent with observed runtime
state and determines whether SportsOS should:

- do nothing
- observe during a startup grace period
- reconcile harmless idle state
- request a controlled start
- request a controlled stop
- require operator review

### Safety rule

A disagreement between coordinator intent and encoder runtime must never cause
an automatic destructive action.

In particular:

- a missing runtime is not silently restarted
- an unexpected live runtime is not silently killed
- failed or unknown runtime state requires operator review
- stale starting/stopping transitions require operator review
- startup grace prevents restart/recovery flapping

This keeps the coordinator authoritative while creating a deterministic basis
for later supervisor and recovery work.

### Milestone 24 sequence

24.1 Recovery policy foundation  
24.2 Runtime heartbeat and stale-process detection  
24.3 Coordinator/runtime reconciliation supervisor  
24.4 Controlled recovery workflow  
24.5 Restart/crash recovery persistence  
24.6 Stream destination failure handling  
24.7 Backoff and retry budgets  
24.8 Resilience telemetry and operator visibility  
24.9 Failure-injection / chaos regression tests  
24.10 Production resilience acceptance / closeout
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 24.1 installed"
echo "============================================================"
echo "Added:"
echo "  - deterministic broadcast recovery policy"
echo "  - startup grace / anti-flap behavior"
echo "  - stale transition detection"
echo "  - conservative failed/unknown-state escalation"
echo "  - no automatic destructive recovery"
echo "  - Milestone 24 resilience roadmap"
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
echo "Next:"
echo "  Milestone 24.2 - Runtime Heartbeat / Stale Process Detection"
