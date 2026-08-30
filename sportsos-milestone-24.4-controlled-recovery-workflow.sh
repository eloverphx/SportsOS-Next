#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-24.4-controlled-recovery-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/broadcastControlledRecovery.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
AUDIT="apps/api/src/services/broadcastCoordinatorAudit.ts"
FOCUS="apps/dashboard/app/broadcast/operations/[gameId]/page.tsx"
TEST="packages/core/test/broadcast-controlled-recovery-24.4.test.ts"
DOC="docs/BROADCAST-RESILIENCE.md"

for required in \
  ".git" \
  "apps/api/src/services/broadcastRecoveryPolicy.ts" \
  "apps/api/src/services/broadcastResilienceSupervisor.ts" \
  "apps/api/src/services/broadcastSessionCoordinator.ts" \
  "$ROUTE" \
  "$AUDIT" \
  "$FOCUS" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$ROUTE" "$AUDIT" "$FOCUS" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/services/broadcastCoordinatorAudit.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes('"RECOVERY_REQUESTED"')) {
  s=s.replace(
`  | "SUPERVISOR_TICK_FAILED";`,
`  | "SUPERVISOR_TICK_FAILED"
  | "RECOVERY_REQUESTED"
  | "RECOVERY_EXECUTED"
  | "RECOVERY_REFUSED";`
  );
}

fs.writeFileSync(f,s);
NODE

cat > "$SERVICE" <<'EOF'
import {
  recordBroadcastCoordinatorAudit,
} from "./broadcastCoordinatorAudit.js";

import {
  prepareBroadcastSession,
  reconcileBroadcastCoordinator,
  stopCoordinatedBroadcast,
} from "./broadcastSessionCoordinator.js";

import {
  evaluateBroadcastResilienceSupervisor,
} from "./broadcastResilienceSupervisor.js";

export type ControlledRecoveryRequest = {
  gameId: string;
  operator: string;
  approveDestructive: boolean;
  coordinatorIntent: string;
  runtimeStatus: string;
  lastActivityAt: string | null;
  stateAgeMs: number;
};

export type ControlledRecoveryResult = {
  executed: boolean;
  action: string;
  message: string;
};

export async function executeControlledBroadcastRecovery(
  input: ControlledRecoveryRequest,
): Promise<ControlledRecoveryResult> {
  const operator =
    input.operator.trim();

  if (!operator) {
    throw new Error(
      "Operator name is required.",
    );
  }

  const decision =
    evaluateBroadcastResilienceSupervisor({
      coordinatorIntent:
        input.coordinatorIntent,
      runtimeStatus:
        input.runtimeStatus,
      lastActivityAt:
        input.lastActivityAt,
      stateAgeMs:
        input.stateAgeMs,
    });

  recordBroadcastCoordinatorAudit({
    gameId:
      input.gameId,
    type:
      "RECOVERY_REQUESTED",
    detail:
      `${operator}: ${decision.recovery.action}`,
  });

  if (
    decision.recovery.action ===
      "require-operator-review"
  ) {
    recordBroadcastCoordinatorAudit({
      gameId:
        input.gameId,
      type:
        "RECOVERY_REFUSED",
      detail:
        `${operator}: supervisor requires operator review.`,
    });

    return {
      executed:
        false,
      action:
        decision.recovery.action,
      message:
        "Recovery was not executed because the supervisor requires operator review.",
    };
  }

  if (
    decision.recovery.destructive &&
    !input.approveDestructive
  ) {
    recordBroadcastCoordinatorAudit({
      gameId:
        input.gameId,
      type:
        "RECOVERY_REFUSED",
      detail:
        `${operator}: destructive recovery requires explicit approval.`,
    });

    return {
      executed:
        false,
      action:
        decision.recovery.action,
      message:
        "Destructive recovery requires explicit operator approval.",
    };
  }

  switch (
    decision.recovery.action
  ) {
    case "request-controlled-start":
      prepareBroadcastSession(
        input.gameId,
      );

      recordBroadcastCoordinatorAudit({
        gameId:
          input.gameId,
        type:
          "RECOVERY_EXECUTED",
        detail:
          `${operator}: prepared controlled restart path.`,
      });

      return {
        executed:
          true,
        action:
          decision.recovery.action,
        message:
          "Controlled start recovery prepared. Final start still requires the normal guarded start flow.",
      };

    case "request-controlled-stop":
      await stopCoordinatedBroadcast(
        input.gameId,
      );

      recordBroadcastCoordinatorAudit({
        gameId:
          input.gameId,
        type:
          "RECOVERY_EXECUTED",
        detail:
          `${operator}: controlled stop executed.`,
      });

      return {
        executed:
          true,
        action:
          decision.recovery.action,
        message:
          "Controlled stop recovery executed.",
      };

    case "reconcile-to-idle":
      await reconcileBroadcastCoordinator(
        input.gameId,
      );

      recordBroadcastCoordinatorAudit({
        gameId:
          input.gameId,
        type:
          "RECOVERY_EXECUTED",
        detail:
          `${operator}: non-destructive reconciliation executed.`,
      });

      return {
        executed:
          true,
        action:
          decision.recovery.action,
        message:
          "Coordinator state reconciled.",
      };

    case "observe":
    case "none":
      return {
        executed:
          false,
        action:
          decision.recovery.action,
        message:
          "No recovery action is required.",
      };
  }
}
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const importLine=`import {
  executeControlledBroadcastRecovery,
} from "../services/broadcastControlledRecovery.js";`;

if(!s.includes("executeControlledBroadcastRecovery")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/:gameId/recovery/execute"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/:gameId/resilience-supervisor",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("24.3 resilience supervisor route missing.");

  const route=`  app.post(
    "/broadcast-coordinator/:gameId/recovery/execute",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          operator?: string;
          approveDestructive?: boolean;
        };

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

      const lastActivityAt =
        snapshot.runtime.telemetry.lastProgressAt ??
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

      try {
        const result =
          await executeControlledBroadcastRecovery({
            gameId,
            operator:
              body.operator ??
              "",
            approveDestructive:
              body.approveDestructive ===
              true,
            coordinatorIntent:
              snapshot.coordinator.intent,
            runtimeStatus:
              snapshot.runtime.session.status,
            lastActivityAt,
            stateAgeMs,
          });

        return {
          success: true,
          data:
            result,
        };
      } catch (error) {
        return reply.code(400).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Controlled recovery failed.",
        });
      }
    },
  );

`;

  s=s.slice(0,i)+route+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/dashboard/app/broadcast/operations/[gameId]/page.tsx";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("recoveryOperator,")) {
  const marker=`  const [
    handoffSummary,
    setHandoffSummary,
  ] =
    useState<HandoffSummary | null>(
      null,
    );`;

  if(!s.includes(marker)) throw Error("23.9 handoff summary state missing.");

  s=s.replace(
    marker,
`${marker}

  const [
    recoveryOperator,
    setRecoveryOperator,
  ] =
    useState("");

  const [
    approveDestructiveRecovery,
    setApproveDestructiveRecovery,
  ] =
    useState(false);`
  );
}

if(!s.includes("const executeRecovery =")) {
  const marker="  const loadHandoffSummary =";
  const i=s.indexOf(marker);
  if(i<0) throw Error("23.9 handoff loader missing.");

  const fn=`  const executeRecovery =
    useCallback(
      async () => {
        if (!recoveryOperator.trim()) {
          setMessage(
            "Operator name is required for controlled recovery.",
          );
          return;
        }

        setBusy(
          true,
        );

        try {
          const response =
            await fetch(
              \`\${API_BASE}/broadcast-coordinator/\${encodeURIComponent(gameId)}/recovery/execute\`,
              {
                method:
                  "POST",
                headers: {
                  "Content-Type":
                    "application/json",
                },
                body:
                  JSON.stringify({
                    operator:
                      recoveryOperator.trim(),
                    approveDestructive:
                      approveDestructiveRecovery,
                  }),
              },
            );

          const json =
            await response.json();

          if (!response.ok) {
            throw new Error(
              json?.error ??
              "Controlled recovery failed.",
            );
          }

          setMessage(
            json?.data?.message ??
            "Controlled recovery completed.",
          );

          setApproveDestructiveRecovery(
            false,
          );

          await load();
        } catch (error) {
          setMessage(
            error instanceof Error
              ? error.message
              : "Controlled recovery failed.",
          );
        } finally {
          setBusy(
            false,
          );
        }
      },
      [
        approveDestructiveRecovery,
        gameId,
        load,
        recoveryOperator,
      ],
    );

`;

  s=s.slice(0,i)+fn+s.slice(i);
}

if(!s.includes("Controlled Recovery")) {
  const marker=`          <section className="mt-4 rounded-xl border border-slate-800 p-5">
            <div className="text-sm font-semibold">Operator Timeline</div>`;

  const i=s.indexOf(marker);
  if(i<0) throw Error("Operator Timeline section missing.");

  const block=`          <section className="mt-4 rounded-xl border border-amber-900/40 p-5">
            <div className="text-sm font-semibold">
              Controlled Recovery
            </div>

            <p className="mt-1 text-xs text-slate-500">
              Recovery recommendations remain operator-approved. Destructive recovery requires explicit approval.
            </p>

            <div className="mt-3 grid gap-3 md:grid-cols-2">
              <input
                value={recoveryOperator}
                onChange={(event) =>
                  setRecoveryOperator(
                    event.target.value,
                  )
                }
                placeholder="Operator name"
                className="rounded-lg border border-slate-800 bg-transparent px-3 py-2 text-xs"
              />

              <label className="flex items-center gap-2 rounded-lg border border-slate-800 px-3 py-2 text-xs">
                <input
                  type="checkbox"
                  checked={approveDestructiveRecovery}
                  onChange={(event) =>
                    setApproveDestructiveRecovery(
                      event.target.checked,
                    )
                  }
                />
                Approve destructive recovery if recommended
              </label>
            </div>

            <button
              type="button"
              disabled={
                busy ||
                !recoveryOperator.trim()
              }
              onClick={() =>
                void executeRecovery()
              }
              className="mt-3 rounded-lg border border-amber-800 px-3 py-2 text-xs font-semibold disabled:opacity-50"
            >
              Execute Controlled Recovery
            </button>
          </section>

`;

  s=s.slice(0,i)+block+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 24.4 — Controlled recovery workflow

SportsOS can now execute a recovery recommendation through an explicit operator-approved API.

Endpoint:

```text
POST /broadcast-coordinator/:gameId/recovery/execute
```

Required operator input:

```text
operator
```

Destructive recovery additionally requires:

```text
approveDestructive = true
```

Behavior:

```text
request-controlled-start
  -> returns to PREPARE only
  -> normal guarded Start Broadcast flow is still required

request-controlled-stop
  -> executes existing coordinated stop path
  -> requires explicit destructive approval

reconcile-to-idle
  -> executes existing coordinator reconciliation

require-operator-review
  -> refused

observe / none
  -> no action
```

Recovery requests, successful executions, and refusals are added to the coordinator audit history.

The controlled recovery service does not call encoder-runtime internals directly.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 24.4 controlled recovery workflow", () => {
  const service=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastControlledRecovery.ts",
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

  const audit=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastCoordinatorAudit.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("requires operator identity",()=> {
    expect(service).toContain("Operator name is required.");
  });

  it("requires explicit approval for destructive recovery",()=> {
    expect(service).toContain("approveDestructive");
    expect(service).toContain("Destructive recovery requires explicit operator approval.");
  });

  it("refuses supervisor operator-review state",()=> {
    expect(service).toContain('"require-operator-review"');
    expect(service).toContain("RECOVERY_REFUSED");
  });

  it("does not directly control encoder runtime",()=> {
    expect(service).not.toContain("startEncoderRuntime");
    expect(service).not.toContain("stopEncoderRuntime");
  });

  it("uses existing coordinator control paths",()=> {
    expect(service).toContain("prepareBroadcastSession");
    expect(service).toContain("stopCoordinatedBroadcast");
    expect(service).toContain("reconcileBroadcastCoordinator");
  });

  it("provides controlled recovery API",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/recovery/execute"');
    expect(route).toContain("executeControlledBroadcastRecovery");
  });

  it("provides operator-controlled Focus Mode UI",()=> {
    expect(focus).toContain("Controlled Recovery");
    expect(focus).toContain("Execute Controlled Recovery");
    expect(focus).toContain("Approve destructive recovery if recommended");
  });

  it("audits recovery workflow",()=> {
    expect(audit).toContain('"RECOVERY_REQUESTED"');
    expect(audit).toContain('"RECOVERY_EXECUTED"');
    expect(audit).toContain('"RECOVERY_REFUSED"');
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 24.4 installed"
echo "============================================================"
echo "Added:"
echo "  - operator-approved controlled recovery"
echo "  - destructive-action approval gate"
echo "  - controlled prepare/stop/reconcile paths"
echo "  - recovery audit events"
echo "  - Focus Mode recovery controls"
echo "  - no direct encoder runtime control"
echo "  - Milestone 24.4 regression tests"
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
echo "  Milestone 24.5 - Restart / Crash Recovery Persistence"
