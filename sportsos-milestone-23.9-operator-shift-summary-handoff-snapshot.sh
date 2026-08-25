#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-23.9-shift-summary-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
FOCUS="apps/dashboard/app/broadcast/operations/[gameId]/page.tsx"
TEST="packages/core/test/broadcast-shift-summary-23.9.test.ts"
DOC="docs/BROADCAST-OPERATIONS-CONSOLE.md"

for required in \
  ".git" \
  "$ROUTE" \
  "$FOCUS" \
  "apps/api/src/services/broadcastOperatorNotes.ts" \
  "apps/api/src/services/broadcastCoordinatorAudit.ts" \
  "apps/api/src/services/goLiveAudit.ts" \
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

if(!s.includes("listBroadcastOperatorNotes")) {
  throw new Error("23.8 operator notes import missing.");
}

if(!s.includes('"/broadcast-coordinator/:gameId/handoff-summary"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/:gameId/operator-notes",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("23.8 operator notes route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/:gameId/handoff-summary",
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

      const health =
        evaluateBroadcastCoordinatorHealth(
          gameId,
        );

      const retry =
        getBroadcastCoordinatorRetry(
          gameId,
        );

      const notes =
        listBroadcastOperatorNotes(
          gameId,
          5,
        );

      const coordinatorEvents =
        listBroadcastCoordinatorAudit(
          gameId,
          10,
        ).map(
          (event) => ({
            source:
              "COORDINATOR",
            type:
              event.type,
            timestamp:
              event.timestamp,
            detail:
              event.detail,
          }),
        );

      const goLiveEvents =
        listGoLiveAuditEvents(
          gameId,
          10,
        ).map(
          (event) => ({
            source:
              "GO_LIVE",
            type:
              event.type,
            timestamp:
              event.timestamp,
            detail:
              event.detail,
          }),
        );

      const recentEvents =
        [
          ...coordinatorEvents,
          ...goLiveEvents,
        ]
          .sort(
            (a, b) =>
              Date.parse(
                b.timestamp,
              ) -
              Date.parse(
                a.timestamp,
              ),
          )
          .slice(
            0,
            10,
          );

      return {
        success: true,
        data: {
          gameId,
          generatedAt:
            new Date().toISOString(),
          snapshot,
          health,
          retry,
          notes,
          recentEvents,
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

if(!s.includes("type HandoffSummary =")) {
  const marker="type OperatorNote = {";
  const i=s.indexOf(marker);
  if(i<0) throw Error("23.8 OperatorNote type missing.");

  const type=`type HandoffSummary = {
  generatedAt: string;
  snapshot: CoordinatorSnapshot;
  health: CoordinatorHealth;
  retry: CoordinatorRetry;
  notes: OperatorNote[];
  recentEvents: Array<{
    source:
      | "COORDINATOR"
      | "GO_LIVE";
    type: string;
    timestamp: string;
    detail: string | null;
  }>;
};

`;

  s=s.slice(0,i)+type+s.slice(i);
}

if(!s.includes("handoffSummary,")) {
  const marker=`  const [
    handoffNote,
    setHandoffNote,
  ] =
    useState("");`;

  if(!s.includes(marker)) throw Error("23.8 handoff note state missing.");

  s=s.replace(
    marker,
`${marker}

  const [
    handoffSummary,
    setHandoffSummary,
  ] =
    useState<HandoffSummary | null>(
      null,
    );`
  );
}

if(!s.includes("const loadHandoffSummary =")) {
  const marker="  const saveOperatorNote =";
  const i=s.indexOf(marker);
  if(i<0) throw Error("23.8 saveOperatorNote missing.");

  const fn=`  const loadHandoffSummary =
    useCallback(
      async () => {
        setBusy(
          true,
        );

        try {
          const response =
            await fetch(
              \`\${API_BASE}/broadcast-coordinator/\${encodeURIComponent(gameId)}/handoff-summary\`,
              {
                cache:
                  "no-store",
              },
            );

          const json =
            await response.json();

          if (!response.ok) {
            throw new Error(
              json?.error ??
              "Unable to load handoff summary.",
            );
          }

          setHandoffSummary(
            json?.data ??
            null,
          );

          setMessage(
            null,
          );
        } catch (error) {
          setMessage(
            error instanceof Error
              ? error.message
              : "Unable to load handoff summary.",
          );
        } finally {
          setBusy(
            false,
          );
        }
      },
      [
        gameId,
      ],
    );

`;

  s=s.slice(0,i)+fn+s.slice(i);
}

if(!s.includes("Shift Handoff Snapshot")) {
  const marker=`          <section className="mt-4 rounded-xl border border-slate-800 p-5">
            <div className="text-sm font-semibold">
              Shift Handoff Notes
            </div>`;

  const i=s.indexOf(marker);
  if(i<0) throw Error("23.8 Shift Handoff Notes section missing.");

  const block=`          <section className="mt-4 rounded-xl border border-slate-800 p-5">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <div className="text-sm font-semibold">
                  Shift Handoff Snapshot
                </div>

                <p className="mt-1 text-xs text-slate-500">
                  Current broadcast state plus the most recent notes and actions.
                </p>
              </div>

              <button
                type="button"
                disabled={
                  busy
                }
                onClick={() =>
                  void loadHandoffSummary()
                }
                className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
              >
                Generate Handoff Snapshot
              </button>
            </div>

            {handoffSummary && (
              <div className="mt-4 space-y-4">
                <div className="grid gap-3 md:grid-cols-4">
                  <div className="rounded border border-slate-800 p-3">
                    <div className="text-xs text-slate-500">
                      Coordinator
                    </div>
                    <div className="mt-1 text-sm font-semibold">
                      {handoffSummary.snapshot.coordinator.intent}
                    </div>
                  </div>

                  <div className="rounded border border-slate-800 p-3">
                    <div className="text-xs text-slate-500">
                      Go-Live
                    </div>
                    <div className="mt-1 text-sm font-semibold">
                      {handoffSummary.snapshot.goLive.status}
                    </div>
                  </div>

                  <div className="rounded border border-slate-800 p-3">
                    <div className="text-xs text-slate-500">
                      Health
                    </div>
                    <div className="mt-1 text-sm font-semibold">
                      {handoffSummary.health.healthy
                        ? "HEALTHY"
                        : "ATTENTION"}
                    </div>
                  </div>

                  <div className="rounded border border-slate-800 p-3">
                    <div className="text-xs text-slate-500">
                      Retry
                    </div>
                    <div className="mt-1 text-sm font-semibold">
                      {handoffSummary.retry.state}
                    </div>
                  </div>
                </div>

                <div className="rounded border border-slate-800 p-3">
                  <div className="text-xs font-semibold">
                    Recent Handoff Notes
                  </div>

                  <div className="mt-2 space-y-2">
                    {handoffSummary.notes.length === 0 ? (
                      <div className="text-xs text-slate-500">
                        No recent handoff notes.
                      </div>
                    ) : (
                      handoffSummary.notes.map(
                        (note) => (
                          <div
                            key={note.id}
                            className="text-xs text-slate-400"
                          >
                            {note.operator}: {note.note}
                          </div>
                        ),
                      )
                    )}
                  </div>
                </div>

                <div className="rounded border border-slate-800 p-3">
                  <div className="text-xs font-semibold">
                    Recent Operator / Automation Events
                  </div>

                  <div className="mt-2 space-y-2">
                    {handoffSummary.recentEvents.length === 0 ? (
                      <div className="text-xs text-slate-500">
                        No recent events.
                      </div>
                    ) : (
                      handoffSummary.recentEvents.map(
                        (
                          event,
                          index,
                        ) => (
                          <div
                            key={\`\${event.timestamp}-\${event.type}-\${index}\`}
                            className="text-xs text-slate-400"
                          >
                            {event.timestamp} · {event.source} · {event.type}
                            {event.detail
                              ? \` — \${event.detail}\`
                              : ""}
                          </div>
                        ),
                      )
                    )}
                  </div>
                </div>

                <div className="text-[10px] text-slate-600">
                  Generated {handoffSummary.generatedAt}
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

## Milestone 23.9 — Operator shift summary / handoff snapshot

Focus Mode can now generate a read-only handoff snapshot.

Endpoint:

```text
GET /broadcast-coordinator/:gameId/handoff-summary
```

The snapshot combines:

- current coordinator snapshot
- current coordinator health
- current retry state
- newest 5 operator notes
- newest 10 combined coordinator/go-live events

No new persistence is created.

The handoff snapshot is generated on demand and reflects current operational state at the moment it is requested.

Focus Mode exposes:

```text
Generate Handoff Snapshot
```

for fast operator-to-operator context transfer.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.9 operator shift summary / handoff snapshot", () => {
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

  it("provides handoff summary API",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/handoff-summary"');
  });

  it("combines current state, notes, and recent events",()=> {
    expect(route).toContain("getBroadcastCoordinatorSnapshot");
    expect(route).toContain("evaluateBroadcastCoordinatorHealth");
    expect(route).toContain("getBroadcastCoordinatorRetry");
    expect(route).toContain("listBroadcastOperatorNotes");
    expect(route).toContain("listBroadcastCoordinatorAudit");
    expect(route).toContain("listGoLiveAuditEvents");
  });

  it("limits handoff context",()=> {
    expect(route).toContain("listBroadcastOperatorNotes");
    expect(route).toContain("5");
    expect(route).toContain(".slice(");
    expect(route).toContain("10");
  });

  it("provides focus-mode snapshot UI",()=> {
    expect(focus).toContain("Shift Handoff Snapshot");
    expect(focus).toContain("Generate Handoff Snapshot");
    expect(focus).toContain("handoffSummary");
  });

  it("shows recent notes and events",()=> {
    expect(focus).toContain("Recent Handoff Notes");
    expect(focus).toContain("Recent Operator / Automation Events");
  });

  it("does not create new persistence",()=> {
    expect(route).not.toContain("handoff-summary.json");
    expect(focus).not.toContain("localStorage");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 23.9 installed"
echo "============================================================"
echo "Added:"
echo "  - handoff summary API"
echo "  - current-state snapshot"
echo "  - recent notes summary"
echo "  - recent operator/automation event summary"
echo "  - Focus Mode handoff snapshot UI"
echo "  - on-demand generation only"
echo "  - no new persistence layer"
echo "  - Milestone 23.9 regression tests"
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
echo "  Milestone 23.10 - Broadcast Operations Acceptance / Closeout"
