#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-22.7-supervisor-${STAMP}"
[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || { echo "ERROR: refusing to run outside $EXPECTED"; exit 1; }
cd "$ROOT"
SERVICE="apps/api/src/services/broadcastSessionCoordinator.ts"
AUDIT="apps/api/src/services/broadcastCoordinatorAudit.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/broadcast-coordinator-supervisor-22.7.test.ts"
DOC="docs/BROADCAST-COORDINATOR.md"
for f in .git "$SERVICE" "$AUDIT" "$ROUTE" "$DOC"; do
  [[ -e "$f" ]] || { echo "ERROR: prerequisite missing: $ROOT/$f"; echo "Repository was not modified."; exit 1; }
done
for f in "$SERVICE" "$AUDIT" "$ROUTE" "$TEST" "$DOC"; do
  [[ -f "$f" ]] && { mkdir -p "$BACKUP/$(dirname "$f")"; cp -a "$f" "$BACKUP/$f"; }
done
node <<'NODE'
const fs=require("fs");
let f="apps/api/src/services/broadcastCoordinatorAudit.ts",s=fs.readFileSync(f,"utf8");
if(!s.includes('"SUPERVISOR_TICK"')) s=s.replace('  | "RETRY_EXHAUSTED";','  | "RETRY_EXHAUSTED"\n  | "SUPERVISOR_TICK"\n  | "SUPERVISOR_RETRY_EXECUTED"\n  | "SUPERVISOR_RECONCILED"\n  | "SUPERVISOR_ACTION_REFUSED";');
fs.writeFileSync(f,s);
NODE
cat >> "$SERVICE" <<'EOF'

export type BroadcastCoordinatorSupervisorAction =
  | "NONE"
  | "RETRY_EXECUTED"
  | "RECONCILED"
  | "REFUSED";

export type BroadcastCoordinatorSupervisorResult = {
  gameId: string;
  action: BroadcastCoordinatorSupervisorAction;
  checkedAt: string;
  message: string;
  health: BroadcastCoordinatorHealth;
  retry: BroadcastCoordinatorRetry;
  snapshot: BroadcastCoordinatorSnapshot;
};

export async function runBroadcastCoordinatorSupervisorTick(
  gameId: string,
): Promise<BroadcastCoordinatorSupervisorResult> {
  recordBroadcastCoordinatorAudit({
    gameId,
    type: "SUPERVISOR_TICK",
    correlationId: getBroadcastCoordinatorRecord(gameId).correlationId,
  });

  const retry = getBroadcastCoordinatorRetry(gameId);

  if (
    retry.state === "SCHEDULED" &&
    retry.nextRetryAt &&
    Date.now() >= Date.parse(retry.nextRetryAt)
  ) {
    const result = await executeBroadcastCoordinatorRetry(gameId);
    recordBroadcastCoordinatorAudit({
      gameId,
      type: "SUPERVISOR_RETRY_EXECUTED",
      correlationId: getBroadcastCoordinatorRecord(gameId).correlationId,
      detail: result.retry.state,
    });
    return {
      gameId,
      action: "RETRY_EXECUTED",
      checkedAt: new Date().toISOString(),
      message: "Scheduled coordinator retry was executed.",
      health: evaluateBroadcastCoordinatorHealth(gameId),
      retry: result.retry,
      snapshot: result.snapshot,
    };
  }

  const health = evaluateBroadcastCoordinatorHealth(gameId);
  if (!health.healthy) {
    const ids = new Set(health.issues.map((issue) => issue.id));
    const repairable =
      ids.has("EMERGENCY_STOP_RUNTIME_ACTIVE") ||
      ids.has("INTENT_STOP_RUNTIME_ACTIVE") ||
      (
        ids.has("INTENT_GO_LIVE_RUNTIME_STOPPED") &&
        ids.has("INTENT_GO_LIVE_SESSION_NOT_ACTIVE")
      );

    if (repairable) {
      const result = await reconcileBroadcastCoordinator(gameId);
      const refused = result.action === "REFUSE_AMBIGUOUS";
      recordBroadcastCoordinatorAudit({
        gameId,
        type: refused ? "SUPERVISOR_ACTION_REFUSED" : "SUPERVISOR_RECONCILED",
        correlationId: getBroadcastCoordinatorRecord(gameId).correlationId,
        detail: result.action,
      });
      return {
        gameId,
        action: refused ? "REFUSED" : "RECONCILED",
        checkedAt: new Date().toISOString(),
        message: result.message,
        health: result.health,
        retry: getBroadcastCoordinatorRetry(gameId),
        snapshot: result.snapshot,
      };
    }

    recordBroadcastCoordinatorAudit({
      gameId,
      type: "SUPERVISOR_ACTION_REFUSED",
      correlationId: getBroadcastCoordinatorRecord(gameId).correlationId,
      detail: "Drift requires operator review.",
    });
    return {
      gameId,
      action: "REFUSED",
      checkedAt: new Date().toISOString(),
      message: "Coordinator drift requires operator review.",
      health,
      retry,
      snapshot: getBroadcastCoordinatorSnapshot(gameId),
    };
  }

  return {
    gameId,
    action: "NONE",
    checkedAt: new Date().toISOString(),
    message: "Coordinator is healthy and no retry is due.",
    health,
    retry,
    snapshot: getBroadcastCoordinatorSnapshot(gameId),
  };
}
EOF
node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");
if(!s.includes("runBroadcastCoordinatorSupervisorTick")) {
  s=s.replace("  scheduleBroadcastCoordinatorRetry,","  runBroadcastCoordinatorSupervisorTick,\n  scheduleBroadcastCoordinatorRetry,");
}
if(!s.includes('"/broadcast-coordinator/:gameId/supervisor/tick"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/:gameId/retry",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("22.6 retry route prerequisite missing.");
  const route=`  app.post(
    "/broadcast-coordinator/:gameId/supervisor/tick",
    async (request, reply) => {
      const gameId = (request.params as { gameId?: string }).gameId?.trim();
      if (!gameId) {
        return reply.code(400).send({ success: false, error: "Game ID is required." });
      }
      const result = await runBroadcastCoordinatorSupervisorTick(gameId);
      if (result.action === "REFUSED") {
        return reply.code(409).send({ success: false, error: result.message, data: result });
      }
      return { success: true, data: result };
    },
  );

`;
  s=s.slice(0,i)+route+s.slice(i);
}
fs.writeFileSync(f,s);
NODE
cat >> "$DOC" <<'EOF'

## Milestone 22.7 — Coordinator supervisor / automatic retry tick

A bounded supervisor tick now executes due retries, invokes only previously defined safe reconciliation, refuses ambiguous drift, and otherwise performs no action.

```text
POST /broadcast-coordinator/:gameId/supervisor/tick
```

Supervisor actions are `NONE`, `RETRY_EXECUTED`, `RECONCILED`, and `REFUSED`.

The supervisor deliberately remains a single tick rather than an internal timer loop. It never automatically starts FFmpeg; successful retry returns only to preparation.
EOF
mkdir -p "$(dirname "$TEST")"
cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.7 coordinator supervisor", () => {
  const service=fs.readFileSync(new URL("../../../apps/api/src/services/broadcastSessionCoordinator.ts",import.meta.url),"utf8");
  const audit=fs.readFileSync(new URL("../../../apps/api/src/services/broadcastCoordinatorAudit.ts",import.meta.url),"utf8");
  const route=fs.readFileSync(new URL("../../../apps/api/src/routes/broadcastSessionCoordinator.ts",import.meta.url),"utf8");

  it("supports bounded actions",()=> {
    ["NONE","RETRY_EXECUTED","RECONCILED","REFUSED"].forEach(x=>expect(service).toContain(`"${x}"`));
  });
  it("executes only due scheduled retries",()=> {
    expect(service).toContain('retry.state === "SCHEDULED"');
    expect(service).toContain("Date.parse(retry.nextRetryAt)");
    expect(service).toContain("executeBroadcastCoordinatorRetry");
  });
  it("reuses safe reconciliation",()=>expect(service).toContain("reconcileBroadcastCoordinator"));
  it("audits supervisor decisions",()=> {
    ["SUPERVISOR_TICK","SUPERVISOR_RETRY_EXECUTED","SUPERVISOR_RECONCILED","SUPERVISOR_ACTION_REFUSED"].forEach(x=>expect(audit).toContain(`"${x}"`));
  });
  it("does not auto-start encoder",()=> {
    const block=service.slice(service.indexOf("export async function runBroadcastCoordinatorSupervisorTick"));
    expect(block).not.toContain("startEncoderRuntime(");
    expect(block).not.toContain("startCoordinatedBroadcast(");
  });
  it("provides tick endpoint",()=>expect(route).toContain('"/broadcast-coordinator/:gameId/supervisor/tick"'));
});
EOF
echo "============================================================"
echo " SportsOS-Next Milestone 22.7 installed"
echo "============================================================"
echo "Backup: $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 22.8 - Supervisor Runtime Scheduling / Lifecycle"
