#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-24.8-resilience-telemetry-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
FOCUS="apps/dashboard/app/broadcast/operations/[gameId]/page.tsx"
TEST="packages/core/test/broadcast-resilience-telemetry-24.8.test.ts"
DOC="docs/BROADCAST-RESILIENCE.md"

for required in \
  ".git" \
  "$ROUTE" \
  "$FOCUS" \
  "apps/api/src/services/broadcastResilienceSupervisor.ts" \
  "apps/api/src/services/broadcastRecoverySnapshotStore.ts" \
  "apps/api/src/services/broadcastResilienceRetryBudget.ts" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$ROUTE" "$FOCUS" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes('"/broadcast-coordinator/:gameId/resilience-status"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/:gameId/resilience-supervisor",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("24.3 resilience supervisor route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/:gameId/resilience-status",
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

      const decision =
        evaluateBroadcastResilienceSupervisor({
          coordinatorIntent:
            snapshot.coordinator.intent,
          runtimeStatus:
            snapshot.runtime.session.status,
          lastActivityAt,
          stateAgeMs,
        });

      return {
        success: true,
        data: {
          gameId,
          heartbeat:
            decision.heartbeat,
          recovery:
            decision.recovery,
          persistedSnapshot:
            getBroadcastRecoverySnapshot(
              gameId,
            ),
        },
      };
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

if(!s.includes("type ResilienceStatus =")) {
  const marker="type HandoffSummary = {";
  const i=s.indexOf(marker);
  if(i<0) throw Error("23.9 HandoffSummary type missing.");

  const type=`type ResilienceStatus = {
  heartbeat: {
    state: string;
    stale: boolean;
    ageMs: number | null;
    staleAfterMs: number;
    reason: string;
  };
  recovery: {
    action: string;
    reason: string;
    automatic: boolean;
    destructive: boolean;
  };
  persistedSnapshot: {
    capturedAt: string;
    coordinatorIntent: string;
    runtimeStatus: string;
    recoveryAction: string;
    heartbeatState: string;
  } | null;
};

`;

  s=s.slice(0,i)+type+s.slice(i);
}

if(!s.includes("resilienceStatus,")) {
  const marker=`  const [
    approveDestructiveRecovery,
    setApproveDestructiveRecovery,
  ] =
    useState(false);`;

  if(!s.includes(marker)) throw Error("24.4 destructive recovery state missing.");

  s=s.replace(
    marker,
`${marker}

  const [
    resilienceStatus,
    setResilienceStatus,
  ] =
    useState<ResilienceStatus | null>(
      null,
    );`
  );
}

if(!s.includes("resilience-status")) {
  const marker=`          notesResponse,
        ] =
          await Promise.all([`;

  if(!s.includes(marker)) throw Error("Focus mode load Promise.all missing.");

  s=s.replace(
    marker,
`          notesResponse,
          resilienceResponse,
        ] =
          await Promise.all([`
  );

  const close=`            fetch(
              \`\${API_BASE}/broadcast-coordinator/\${encodeURIComponent(gameId)}/operator-notes\`,
              {
                cache:
                  "no-store",
              },
            ),
          ]);`;

  if(!s.includes(close)) throw Error("23.8 notes fetch block missing.");

  s=s.replace(
    close,
`            fetch(
              \`\${API_BASE}/broadcast-coordinator/\${encodeURIComponent(gameId)}/operator-notes\`,
              {
                cache:
                  "no-store",
              },
            ),
            fetch(
              \`\${API_BASE}/broadcast-coordinator/\${encodeURIComponent(gameId)}/resilience-status\`,
              {
                cache:
                  "no-store",
              },
            ),
          ]);`
  );

  const parseMarker=`        const notesJson =
          await notesResponse.json();`;

  if(!s.includes(parseMarker)) throw Error("Notes JSON parse missing.");

  s=s.replace(
    parseMarker,
`${parseMarker}

        const resilienceJson =
          await resilienceResponse.json();`
  );

  const stateMarker=`        setOperatorNotes(
          notesJson?.data?.notes ??
          [],
        );`;

  if(!s.includes(stateMarker)) throw Error("Operator notes setter missing.");

  s=s.replace(
    stateMarker,
`${stateMarker}

        setResilienceStatus(
          resilienceJson?.data ??
          null,
        );`
  );
}

if(!s.includes("Resilience Telemetry")) {
  const marker=`          <section className="mt-4 rounded-xl border border-amber-900/40 p-5">
            <div className="text-sm font-semibold">
              Controlled Recovery
            </div>`;

  const i=s.indexOf(marker);
  if(i<0) throw Error("24.4 Controlled Recovery section missing.");

  const block=`          <section className="mt-4 rounded-xl border border-slate-800 p-5">
            <div className="text-sm font-semibold">
              Resilience Telemetry
            </div>

            <p className="mt-1 text-xs text-slate-500">
              Read-only recovery context from heartbeat, supervisor, and persisted restart state.
            </p>

            {!resilienceStatus ? (
              <div className="mt-3 text-xs text-slate-500">
                Resilience status unavailable.
              </div>
            ) : (
              <div className="mt-4 space-y-4">
                <div className="grid gap-3 md:grid-cols-4">
                  <div className="rounded border border-slate-800 p-3">
                    <div className="text-xs text-slate-500">
                      Heartbeat
                    </div>
                    <div className="mt-1 text-sm font-semibold">
                      {resilienceStatus.heartbeat.state}
                    </div>
                  </div>

                  <div className="rounded border border-slate-800 p-3">
                    <div className="text-xs text-slate-500">
                      Recovery Action
                    </div>
                    <div className="mt-1 text-sm font-semibold">
                      {resilienceStatus.recovery.action}
                    </div>
                  </div>

                  <div className="rounded border border-slate-800 p-3">
                    <div className="text-xs text-slate-500">
                      Automatic
                    </div>
                    <div className="mt-1 text-sm font-semibold">
                      {resilienceStatus.recovery.automatic
                        ? "YES"
                        : "NO"}
                    </div>
                  </div>

                  <div className="rounded border border-slate-800 p-3">
                    <div className="text-xs text-slate-500">
                      Destructive
                    </div>
                    <div className="mt-1 text-sm font-semibold">
                      {resilienceStatus.recovery.destructive
                        ? "YES"
                        : "NO"}
                    </div>
                  </div>
                </div>

                <div className="rounded border border-slate-800 p-3">
                  <div className="text-xs font-semibold">
                    Heartbeat Reason
                  </div>
                  <div className="mt-1 text-xs text-slate-400">
                    {resilienceStatus.heartbeat.reason}
                  </div>

                  {resilienceStatus.heartbeat.ageMs !== null && (
                    <div className="mt-1 text-[10px] text-slate-600">
                      Age: {resilienceStatus.heartbeat.ageMs} ms · stale after {resilienceStatus.heartbeat.staleAfterMs} ms
                    </div>
                  )}
                </div>

                <div className="rounded border border-slate-800 p-3">
                  <div className="text-xs font-semibold">
                    Recovery Reason
                  </div>
                  <div className="mt-1 text-xs text-slate-400">
                    {resilienceStatus.recovery.reason}
                  </div>
                </div>

                <div className="rounded border border-slate-800 p-3">
                  <div className="text-xs font-semibold">
                    Persisted Recovery Snapshot
                  </div>

                  {!resilienceStatus.persistedSnapshot ? (
                    <div className="mt-1 text-xs text-slate-500">
                      No persisted recovery snapshot has been captured.
                    </div>
                  ) : (
                    <div className="mt-2 space-y-1 text-xs text-slate-400">
                      <div>
                        Captured: {resilienceStatus.persistedSnapshot.capturedAt}
                      </div>
                      <div>
                        Coordinator: {resilienceStatus.persistedSnapshot.coordinatorIntent}
                      </div>
                      <div>
                        Runtime: {resilienceStatus.persistedSnapshot.runtimeStatus}
                      </div>
                      <div>
                        Heartbeat: {resilienceStatus.persistedSnapshot.heartbeatState}
                      </div>
                      <div>
                        Recovery: {resilienceStatus.persistedSnapshot.recoveryAction}
                      </div>
                    </div>
                  )}
                </div>
              </div>
            )}
          </section>

`;

  s=s.slice(0,i)+block+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 24.8 — Resilience telemetry / operator visibility

Focus Mode now displays the current resilience decision before an operator executes controlled recovery.

API:

```text
GET /broadcast-coordinator/:gameId/resilience-status
```

The response includes:

```text
heartbeat
recovery
persistedSnapshot
```

Operator-visible fields include:

- heartbeat state
- heartbeat age / staleness threshold
- heartbeat reason
- recommended recovery action
- recovery reason
- whether the recommendation is automatic
- whether the recommendation is destructive
- last persisted recovery snapshot

This panel is read-only. It does not execute recovery or mutate broadcast state.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 24.8 resilience telemetry / operator visibility", () => {
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

  it("provides resilience status API",()=> {
    expect(route).toContain(
      '"/broadcast-coordinator/:gameId/resilience-status"',
    );

    expect(route).toContain(
      "evaluateBroadcastResilienceSupervisor",
    );

    expect(route).toContain(
      "getBroadcastRecoverySnapshot",
    );
  });

  it("provides operator resilience telemetry UI",()=> {
    expect(focus).toContain(
      "Resilience Telemetry",
    );

    expect(focus).toContain(
      "resilienceStatus",
    );
  });

  it("shows heartbeat and recovery reasoning",()=> {
    expect(focus).toContain(
      "Heartbeat Reason",
    );

    expect(focus).toContain(
      "Recovery Reason",
    );

    expect(focus).toContain(
      "stale after",
    );
  });

  it("shows destructive and automatic flags",()=> {
    expect(focus).toContain(
      "Destructive",
    );

    expect(focus).toContain(
      "Automatic",
    );
  });

  it("shows persisted restart context",()=> {
    expect(focus).toContain(
      "Persisted Recovery Snapshot",
    );

    expect(focus).toContain(
      "persistedSnapshot",
    );
  });

  it("remains read-only",()=> {
    expect(route).not.toContain(
      '"/resilience-status/execute"',
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 24.8 installed"
echo "============================================================"
echo "Added:"
echo "  - resilience-status API"
echo "  - heartbeat operator visibility"
echo "  - recovery recommendation visibility"
echo "  - automatic/destructive flags"
echo "  - persisted restart snapshot visibility"
echo "  - Focus Mode resilience panel"
echo "  - read-only telemetry only"
echo "  - Milestone 24.8 regression tests"
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
echo "  Milestone 24.9 - Failure Injection / Chaos Regression Tests"
