#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-23.5-operator-audit-timeline-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
PAGE="apps/dashboard/app/broadcast/operations/page.tsx"
TEST="packages/core/test/broadcast-operator-audit-timeline-23.5.test.ts"
DOC="docs/BROADCAST-OPERATIONS-CONSOLE.md"

for required in \
  ".git" \
  "$ROUTE" \
  "$PAGE" \
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

for file in "$ROUTE" "$PAGE" "$TEST" "$DOC"; do
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

if(!s.includes("listGoLiveAuditEvents")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");

  s=s.replace(
    imports[0],
    imports[0] +
`import {
  listGoLiveAuditEvents,
} from "../services/goLiveAudit.js";
`
  );
}

if(!s.includes('"/broadcast-coordinator/:gameId/operator-timeline"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/:gameId/audit",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("Coordinator audit route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/:gameId/operator-timeline",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const query =
        request.query as {
          limit?: string;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const parsedLimit =
        Number.parseInt(
          query.limit ??
          "100",
          10,
        );

      const limit =
        Number.isFinite(
          parsedLimit,
        )
          ? Math.max(
              1,
              Math.min(
                parsedLimit,
                200,
              ),
            )
          : 100;

      const coordinatorEvents =
        listBroadcastCoordinatorAudit(
          gameId,
          limit,
        ).map(
          (event) => ({
            id:
              event.id,
            source:
              "COORDINATOR",
            type:
              event.type,
            timestamp:
              event.timestamp,
            detail:
              event.detail,
            operator:
              null,
            correlationId:
              event.correlationId,
          }),
        );

      const goLiveEvents =
        listGoLiveAuditEvents(
          gameId,
          limit,
        ).map(
          (event) => ({
            id:
              event.id,
            source:
              "GO_LIVE",
            type:
              event.type,
            timestamp:
              event.timestamp,
            detail:
              event.detail,
            operator:
              event.operator,
            correlationId:
              null,
          }),
        );

      const events =
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
            limit,
          );

      return {
        success: true,
        data: {
          gameId,
          count:
            events.length,
          events,
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
const f="apps/dashboard/app/broadcast/operations/page.tsx";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("type OperatorTimelineEvent =")) {
  const marker="type OperationsItem = {";
  const i=s.indexOf(marker);
  if(i<0) throw Error("OperationsItem type missing.");

  const type=`type OperatorTimelineEvent = {
  id: string;
  source:
    | "COORDINATOR"
    | "GO_LIVE";
  type: string;
  timestamp: string;
  detail: string | null;
  operator: string | null;
  correlationId: string | null;
};

`;

  s=s.slice(0,i)+type+s.slice(i);
}

if(!s.includes("const [timelineGameId")) {
  const marker=`  const [
    emergencyReason,
    setEmergencyReason,
  ] =
    useState("");`;

  if(!s.includes(marker)) throw Error("23.4 emergency state missing.");

  s=s.replace(
    marker,
`${marker}

  const [
    timelineGameId,
    setTimelineGameId,
  ] =
    useState<string | null>(
      null,
    );

  const [
    timelineEvents,
    setTimelineEvents,
  ] =
    useState<OperatorTimelineEvent[]>(
      [],
    );`
  );
}

if(!s.includes("const loadOperatorTimeline =")) {
  const marker="  const runGoLiveAction =";
  const i=s.indexOf(marker);
  if(i<0) throw Error("runGoLiveAction missing.");

  const fn=`  const loadOperatorTimeline =
    useCallback(
      async (
        gameId: string,
      ) => {
        setActionGameId(
          gameId,
        );

        try {
          const response =
            await fetch(
              \`\${API_BASE}/broadcast-coordinator/\${encodeURIComponent(gameId)}/operator-timeline?limit=50\`,
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
              "Unable to load operator timeline.",
            );
          }

          setTimelineGameId(
            gameId,
          );

          setTimelineEvents(
            json?.data?.events ??
            [],
          );

          setActionMessage(
            null,
          );
        } catch (timelineError) {
          setActionMessage(
            timelineError instanceof Error
              ? timelineError.message
              : "Unable to load operator timeline.",
          );
        } finally {
          setActionGameId(
            null,
          );
        }
      },
      [],
    );

`;

  s=s.slice(0,i)+fn+s.slice(i);
}

if(!s.includes("Operator Timeline")) {
  const marker=`                {(item.snapshot.goLive.status === "DEGRADED" ||`;
  const i=s.indexOf(marker);
  if(i<0) throw Error("23.4 incident block missing.");

  const block=`                <div className="mt-4 rounded border border-slate-800 p-3">
                  <div className="flex flex-wrap items-center justify-between gap-3">
                    <div>
                      <div className="text-xs font-semibold">
                        Operator Timeline
                      </div>
                      <p className="mt-1 text-xs text-slate-500">
                        Combined coordinator and go-live history for this broadcast.
                      </p>
                    </div>

                    <button
                      type="button"
                      disabled={
                        actionGameId ===
                        item.gameId
                      }
                      onClick={() =>
                        void loadOperatorTimeline(
                          item.gameId,
                        )
                      }
                      className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
                    >
                      Load Action History
                    </button>
                  </div>

                  {timelineGameId === item.gameId && (
                    <div className="mt-3 space-y-2">
                      {timelineEvents.length === 0 ? (
                        <div className="rounded border border-slate-800 p-3 text-xs text-slate-500">
                          No operator history recorded.
                        </div>
                      ) : (
                        timelineEvents.map(
                          (event) => (
                            <div
                              key={event.id}
                              className="rounded border border-slate-800 p-3"
                            >
                              <div className="flex flex-wrap items-center justify-between gap-2">
                                <div className="flex flex-wrap items-center gap-2">
                                  <span className="text-xs font-semibold">
                                    {event.type}
                                  </span>

                                  <span className="rounded border border-slate-800 px-2 py-0.5 text-[10px] text-slate-500">
                                    {event.source}
                                  </span>
                                </div>

                                <span className="text-xs text-slate-500">
                                  {event.timestamp}
                                </span>
                              </div>

                              {event.detail && (
                                <div className="mt-1 text-xs text-slate-400">
                                  {event.detail}
                                </div>
                              )}

                              {event.operator && (
                                <div className="mt-1 text-xs text-slate-500">
                                  Operator: {event.operator}
                                </div>
                              )}

                              {event.correlationId && (
                                <div className="mt-1 text-[10px] text-slate-600">
                                  Correlation: {event.correlationId}
                                </div>
                              )}
                            </div>
                          ),
                        )
                      )}
                    </div>
                  )}
                </div>

`;

  s=s.slice(0,i)+block+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 23.5 — Operator audit timeline / action history

The operations console now exposes a combined operator timeline.

Sources:

```text
COORDINATOR
GO_LIVE
```

The API merges the existing coordinator audit and go-live audit without creating a third persistence layer.

Endpoint:

```text
GET /broadcast-coordinator/:gameId/operator-timeline?limit=50
```

Timeline events may include:

- preparation
- start / stop orchestration
- drift detection
- reconciliation
- retry scheduling / execution / exhaustion
- supervisor actions
- degraded incidents
- incident acknowledgements
- emergency stops
- recovery
- live confirmation

Coordinator correlation IDs and go-live operator identities are preserved when available.

The operator timeline is read-only.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.5 operator audit timeline / action history", () => {
  const route=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const page=
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("merges existing coordinator and go-live audit sources",()=> {
    expect(route).toContain("listBroadcastCoordinatorAudit");
    expect(route).toContain("listGoLiveAuditEvents");
    expect(route).toContain('"COORDINATOR"');
    expect(route).toContain('"GO_LIVE"');
  });

  it("provides operator timeline endpoint",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/operator-timeline"');
  });

  it("sorts combined events by timestamp",()=> {
    expect(route).toContain("Date.parse");
    expect(route).toContain(".sort(");
  });

  it("provides operator timeline UI",()=> {
    expect(page).toContain("Operator Timeline");
    expect(page).toContain("Load Action History");
    expect(page).toContain("timelineEvents");
  });

  it("shows operator and correlation context",()=> {
    expect(page).toContain("Operator:");
    expect(page).toContain("Correlation:");
  });

  it("does not create new audit persistence in dashboard",()=> {
    expect(page).not.toContain("localStorage");
    expect(page).not.toContain("indexedDB");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 23.5 installed"
echo "============================================================"
echo "Added:"
echo "  - combined operator timeline API"
echo "  - coordinator + go-live history merge"
echo "  - timestamp ordering"
echo "  - operator identity context"
echo "  - coordinator correlation context"
echo "  - operations-console timeline UI"
echo "  - read-only history"
echo "  - Milestone 23.5 regression tests"
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
echo "  Milestone 23.6 - Attention Queue / Operator Prioritization"
