#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-22.4-coordinator-reconciliation-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/broadcastSessionCoordinator.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/broadcast-coordinator-reconciliation-22.4.test.ts"
DOC="docs/BROADCAST-COORDINATOR.md"

for required in ".git" "$SERVICE" "$ROUTE" "$DOC"; do
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

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/services/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("export type BroadcastCoordinatorReconciliation")) {
  s += `

export type BroadcastCoordinatorReconciliationAction =
  | "NONE"
  | "RESET_INTENT"
  | "STOP_RUNTIME"
  | "REFUSE_AMBIGUOUS";

export type BroadcastCoordinatorReconciliation = {
  gameId: string;
  action:
    BroadcastCoordinatorReconciliationAction;
  repaired: boolean;
  message: string;
  health:
    BroadcastCoordinatorHealth;
  snapshot:
    BroadcastCoordinatorSnapshot;
};

export async function reconcileBroadcastCoordinator(
  gameId: string,
): Promise<BroadcastCoordinatorReconciliation> {
  const before =
    evaluateBroadcastCoordinatorHealth(
      gameId,
    );

  if (before.healthy) {
    return {
      gameId,
      action:
        "NONE",
      repaired:
        false,
      message:
        "Coordinator state is already healthy.",
      health:
        before,
      snapshot:
        getBroadcastCoordinatorSnapshot(
          gameId,
        ),
    };
  }

  const ids =
    new Set(
      before.issues.map(
        (issue) =>
          issue.id,
      ),
    );

  if (
    ids.has(
      "EMERGENCY_STOP_RUNTIME_ACTIVE",
    ) ||
    ids.has(
      "INTENT_STOP_RUNTIME_ACTIVE",
    )
  ) {
    await stopEncoderRuntime(
      gameId,
    );

    setBroadcastCoordinatorIntent({
      gameId,
      intent:
        "IDLE",
      lastError:
        null,
    });

    const health =
      evaluateBroadcastCoordinatorHealth(
        gameId,
      );

    return {
      gameId,
      action:
        "STOP_RUNTIME",
      repaired:
        health.healthy,
      message:
        health.healthy
          ? "Unexpected active runtime was stopped and coordinator intent reset."
          : "Runtime stop was attempted, but coordinator health still reports drift.",
      health,
      snapshot:
        getBroadcastCoordinatorSnapshot(
          gameId,
        ),
    };
  }

  if (
    ids.has(
      "INTENT_GO_LIVE_RUNTIME_STOPPED",
    ) &&
    ids.has(
      "INTENT_GO_LIVE_SESSION_NOT_ACTIVE",
    )
  ) {
    setBroadcastCoordinatorIntent({
      gameId,
      intent:
        "IDLE",
      lastError:
        null,
    });

    const health =
      evaluateBroadcastCoordinatorHealth(
        gameId,
      );

    return {
      gameId,
      action:
        "RESET_INTENT",
      repaired:
        health.healthy,
      message:
        health.healthy
          ? "Stale GO_LIVE intent was reset to IDLE."
          : "Coordinator intent was reset, but health still reports drift.",
      health,
      snapshot:
        getBroadcastCoordinatorSnapshot(
          gameId,
        ),
    };
  }

  return {
    gameId,
    action:
      "REFUSE_AMBIGUOUS",
    repaired:
      false,
    message:
      "Coordinator drift is ambiguous and requires operator review.",
    health:
      before,
    snapshot:
      getBroadcastCoordinatorSnapshot(
        gameId,
      ),
  };
}
`;
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("reconcileBroadcastCoordinator")) {
  s=s.replace(
`  prepareBroadcastSession,
  setBroadcastCoordinatorIntent,`,
`  prepareBroadcastSession,
  reconcileBroadcastCoordinator,
  setBroadcastCoordinatorIntent,`
  );
}

if(!s.includes('"/broadcast-coordinator/:gameId/reconcile"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/:gameId/health",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("22.3 health route prerequisite missing.");

  const route=`  app.post(
    "/broadcast-coordinator/:gameId/reconcile",
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

      const result =
        await reconcileBroadcastCoordinator(
          gameId,
        );

      if (
        result.action ===
        "REFUSE_AMBIGUOUS"
      ) {
        return reply.code(409).send({
          success: false,
          error:
            result.message,
          data:
            result,
        });
      }

      return {
        success: true,
        data:
          result,
      };
    },
  );

`;

  s=s.slice(0,i)+route+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 22.4 — Coordinator reconciliation / safe repair actions

The coordinator can now attempt narrowly scoped repair for known drift states.

Supported reconciliation actions:

```text
NONE
RESET_INTENT
STOP_RUNTIME
REFUSE_AMBIGUOUS
```

Safe repairs:

- reset stale `GO_LIVE` intent to `IDLE` when both runtime and go-live state are inactive
- stop an unexpectedly active encoder when coordinator intent is `STOP`
- stop an unexpectedly active encoder when go-live state is `EMERGENCY_STOPPED`

Ambiguous drift is never auto-repaired.

The reconciliation layer must not:

- start FFmpeg
- arm a go-live session
- confirm a session LIVE
- clear a degraded incident
- modify authoritative game state

API:

```text
POST /broadcast-coordinator/:gameId/reconcile
```

Ambiguous repair requests return HTTP 409 for operator review.
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.4 coordinator reconciliation / safe repair actions", () => {
  const service=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/broadcastSessionCoordinator.ts",
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

  it("defines bounded reconciliation actions",()=> {
    for(const action of [
      "NONE",
      "RESET_INTENT",
      "STOP_RUNTIME",
      "REFUSE_AMBIGUOUS",
    ]) {
      expect(service).toContain(`"${action}"`);
    }
  });

  it("can reset stale intent",()=> {
    expect(service).toContain("Stale GO_LIVE intent was reset to IDLE.");
    expect(service).toContain('intent:\n        "IDLE"');
  });

  it("can stop unexpectedly active runtime",()=> {
    expect(service).toContain("stopEncoderRuntime");
    expect(service).toContain("Unexpected active runtime was stopped");
  });

  it("refuses ambiguous drift",()=> {
    expect(service).toContain("Coordinator drift is ambiguous and requires operator review.");
    expect(route).toContain('"REFUSE_AMBIGUOUS"');
    expect(route).toContain("reply.code(409)");
  });

  it("does not auto-start or confirm live during reconciliation",()=> {
    const start=service.indexOf("export async function reconcileBroadcastCoordinator");
    const block=service.slice(start);
    expect(block).not.toContain("startEncoderRuntime(");
    expect(block).not.toContain("armGoLiveSession(");
    expect(block).not.toContain("markGoLiveLive(");
  });

  it("provides reconciliation API",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/reconcile"');
    expect(route).toContain("reconcileBroadcastCoordinator");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 22.4 installed"
echo "============================================================"
echo "Added:"
echo "  - bounded coordinator reconciliation"
echo "  - stale-intent reset"
echo "  - unexpected-runtime stop"
echo "  - ambiguous repair refusal"
echo "  - no automatic start/arm/live confirmation"
echo "  - reconciliation API"
echo "  - Milestone 22.4 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 22.5 - Coordinator Audit / Reconciliation History"
