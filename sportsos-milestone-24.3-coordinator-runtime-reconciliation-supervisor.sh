#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-24.3-reconciliation-supervisor-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/broadcastResilienceSupervisor.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/broadcast-resilience-supervisor-24.3.test.ts"
DOC="docs/BROADCAST-RESILIENCE.md"

for required in \
  ".git" \
  "apps/api/src/services/broadcastRecoveryPolicy.ts" \
  "apps/api/src/services/broadcastRuntimeHeartbeat.ts" \
  "apps/api/src/services/broadcastSessionCoordinator.ts" \
  "$ROUTE" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$ROUTE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import {
  evaluateBroadcastRecovery,
  type BroadcastRecoveryCoordinatorIntent,
  type BroadcastRecoveryDecision,
  type BroadcastRecoveryRuntimeState,
} from "./broadcastRecoveryPolicy.js";

import {
  evaluateBroadcastRuntimeHeartbeat,
  type BroadcastRuntimeHeartbeat,
} from "./broadcastRuntimeHeartbeat.js";

export type BroadcastResilienceSupervisorInput = {
  coordinatorIntent: string;
  runtimeStatus: string;
  lastActivityAt: string | null;
  stateAgeMs: number;
  nowMs?: number;
};

export type BroadcastResilienceSupervisorDecision = {
  heartbeat:
    BroadcastRuntimeHeartbeat;
  recovery:
    BroadcastRecoveryDecision;
};

function normalizeCoordinatorIntent(
  value: string,
): BroadcastRecoveryCoordinatorIntent {
  const normalized =
    value
      .trim()
      .toUpperCase();

  if (
    normalized ===
      "GO_LIVE" ||
    normalized ===
      "LIVE"
  ) {
    return "live";
  }

  if (
    normalized ===
      "STOP" ||
    normalized ===
      "STOPPED" ||
    normalized ===
      "COMPLETE"
  ) {
    return "stopped";
  }

  return "idle";
}

function normalizeRuntimeState(
  value: string,
): BroadcastRecoveryRuntimeState {
  const normalized =
    value
      .trim()
      .toUpperCase();

  if (
    normalized ===
      "STARTING"
  ) {
    return "starting";
  }

  if (
    normalized ===
      "LIVE" ||
    normalized ===
      "RUNNING"
  ) {
    return "live";
  }

  if (
    normalized ===
      "STOPPING"
  ) {
    return "stopping";
  }

  if (
    normalized ===
      "ERROR" ||
    normalized ===
      "FAILED"
  ) {
    return "failed";
  }

  if (
    normalized ===
      "STOPPED" ||
    normalized ===
      "IDLE"
  ) {
    return "idle";
  }

  return "unknown";
}

export function evaluateBroadcastResilienceSupervisor(
  input: BroadcastResilienceSupervisorInput,
): BroadcastResilienceSupervisorDecision {
  const heartbeat =
    evaluateBroadcastRuntimeHeartbeat({
      runtimeStatus:
        input.runtimeStatus,
      lastActivityAt:
        input.lastActivityAt,
      nowMs:
        input.nowMs,
    });

  let runtimeState =
    normalizeRuntimeState(
      input.runtimeStatus,
    );

  if (
    heartbeat.state ===
      "STALE" ||
    heartbeat.state ===
      "MISSING" ||
    heartbeat.state ===
      "UNKNOWN"
  ) {
    runtimeState =
      "unknown";
  }

  if (
    heartbeat.state ===
      "FAILED"
  ) {
    runtimeState =
      "failed";
  }

  const recovery =
    evaluateBroadcastRecovery({
      coordinatorIntent:
        normalizeCoordinatorIntent(
          input.coordinatorIntent,
        ),
      runtimeState,
      stateAgeMs:
        input.stateAgeMs,
    });

  return {
    heartbeat,
    recovery,
  };
}
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const importLine=`import {
  evaluateBroadcastResilienceSupervisor,
} from "../services/broadcastResilienceSupervisor.js";`;

if(!s.includes("evaluateBroadcastResilienceSupervisor")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/:gameId/resilience-supervisor"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/:gameId/runtime-heartbeat",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("24.2 runtime-heartbeat route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/:gameId/resilience-supervisor",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const snapshot =
        getBroadcastCoordinatorSnapshot(
          gameId,
        );

      const telemetry =
        snapshot.runtime.telemetry;

      const session =
        snapshot.runtime.session;

      const lastActivityAt =
        telemetry.lastProgressAt ??
        null;

      const stateAgeMs =
        lastActivityAt
          ? Math.max(
              0,
              Date.now() -
                Date.parse(
                  lastActivityAt,
                ),
            )
          : 0;

      const decision =
        evaluateBroadcastResilienceSupervisor({
          coordinatorIntent:
            snapshot.coordinator.intent,
          runtimeStatus:
            session.status,
          lastActivityAt,
          stateAgeMs,
        });

      return {
        success: true,
        data: {
          gameId,
          decision,
        },
      };
    },
  );

`;

  s=s.slice(0,i)+route+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 24.3 — Coordinator / runtime reconciliation supervisor

SportsOS now combines the Milestone 24.1 recovery policy and Milestone 24.2 runtime heartbeat into one read-only reconciliation decision.

The supervisor normalizes current coordinator intent and encoder runtime state, evaluates heartbeat freshness, then returns a recommended recovery action.

API:

```text
GET /broadcast-coordinator/:gameId/resilience-supervisor
```

Response includes:

```text
heartbeat
recovery
```

The supervisor does **not** execute the recommended action.

A stale, missing, failed, or unknown heartbeat is conservatively converted into operator-review recovery behavior.

Milestone 24.3 therefore establishes deterministic reconciliation logic without enabling automatic start/stop recovery.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  evaluateBroadcastResilienceSupervisor,
} from "../../../apps/api/src/services/broadcastResilienceSupervisor";

describe("Milestone 24.3 coordinator/runtime reconciliation supervisor", () => {
  it("keeps healthy live state consistent",()=> {
    const now=100_000;

    const result=
      evaluateBroadcastResilienceSupervisor({
        coordinatorIntent:
          "GO_LIVE",
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          new Date(
            now -
            5_000,
          ).toISOString(),
        stateAgeMs:
          5_000,
        nowMs:
          now,
      });

    expect(
      result.heartbeat.state,
    ).toBe(
      "HEALTHY",
    );

    expect(
      result.recovery.action,
    ).toBe(
      "observe",
    );
  });

  it("escalates stale runtime to operator review",()=> {
    const now=100_000;

    const result=
      evaluateBroadcastResilienceSupervisor({
        coordinatorIntent:
          "GO_LIVE",
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          new Date(
            now -
            30_000,
          ).toISOString(),
        stateAgeMs:
          30_000,
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

  it("does not auto-stop unexpected live runtime",()=> {
    const now=100_000;

    const result=
      evaluateBroadcastResilienceSupervisor({
        coordinatorIntent:
          "STOPPED",
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          new Date(
            now -
            60_000,
          ).toISOString(),
        stateAgeMs:
          60_000,
        nowMs:
          now,
      });

    expect(
      result.recovery.action,
    ).toBe(
      "require-operator-review",
    );
  });

  it("escalates failed runtime",()=> {
    const result=
      evaluateBroadcastResilienceSupervisor({
        coordinatorIntent:
          "GO_LIVE",
        runtimeStatus:
          "ERROR",
        lastActivityAt:
          null,
        stateAgeMs:
          60_000,
      });

    expect(
      result.recovery.action,
    ).toBe(
      "require-operator-review",
    );
  });

  it("provides read-only supervisor API",()=> {
    const route=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/:gameId/resilience-supervisor"',
    );

    expect(route).toContain(
      "evaluateBroadcastResilienceSupervisor",
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 24.3 installed"
echo "============================================================"
echo "Added:"
echo "  - coordinator/runtime resilience supervisor"
echo "  - heartbeat + recovery policy composition"
echo "  - conservative stale/missing/failed escalation"
echo "  - read-only resilience-supervisor API"
echo "  - no automatic recovery execution"
echo "  - Milestone 24.3 regression tests"
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
echo "  Milestone 24.4 - Controlled Recovery Workflow"
