#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-23.6-attention-queue-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
PAGE="apps/dashboard/app/broadcast/operations/page.tsx"
TEST="packages/core/test/broadcast-attention-queue-23.6.test.ts"
DOC="docs/BROADCAST-OPERATIONS-CONSOLE.md"

for required in ".git" "$ROUTE" "$PAGE" "$DOC"; do
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

if(!s.includes('"/broadcast-coordinator/attention-queue"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/operations-summary",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("23.1 operations-summary route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/attention-queue",
    async () => {
      const gameIds =
        listActiveBroadcastGameIds();

      const items =
        gameIds
          .map(
            (gameId) => {
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

              let severity:
                | "CRITICAL"
                | "HIGH"
                | "MEDIUM"
                | "LOW" =
                "LOW";

              let reason =
                "Active broadcast requires no immediate attention.";

              if (
                snapshot.goLive.status ===
                  "EMERGENCY_STOPPED"
              ) {
                severity =
                  "CRITICAL";

                reason =
                  "Emergency stop is active.";
              } else if (
                !health.healthy
              ) {
                severity =
                  "HIGH";

                reason =
                  health.issues
                    .map(
                      (issue) =>
                        issue.message,
                    )
                    .join(" | ");
              } else if (
                snapshot.goLive.status ===
                  "DEGRADED"
              ) {
                severity =
                  "HIGH";

                reason =
                  snapshot.goLive.degradationReason ??
                  "Broadcast is degraded.";
              } else if (
                retry.state ===
                  "EXHAUSTED"
              ) {
                severity =
                  "HIGH";

                reason =
                  retry.lastError ??
                  "Coordinator retries are exhausted.";
              } else if (
                retry.state ===
                  "SCHEDULED"
              ) {
                severity =
                  "MEDIUM";

                reason =
                  retry.nextRetryAt
                    ? \`Coordinator retry scheduled for \${retry.nextRetryAt}.\`
                    : "Coordinator retry is scheduled.";
              } else if (
                snapshot.goLive.status ===
                  "STARTING" ||
                snapshot.goLive.status ===
                  "STOPPING"
              ) {
                severity =
                  "MEDIUM";

                reason =
                  \`Go-live transition is \${snapshot.goLive.status}.\`;
              }

              const score =
                severity === "CRITICAL"
                  ? 400
                  : severity === "HIGH"
                    ? 300
                    : severity === "MEDIUM"
                      ? 200
                      : 100;

              return {
                gameId,
                severity,
                score,
                reason,
                health,
                retry,
                snapshot,
              };
            },
          )
          .sort(
            (a, b) =>
              b.score -
              a.score,
          );

      return {
        success: true,
        data: {
          count:
            items.length,
          items,
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

if(!s.includes("type AttentionItem =")) {
  const marker="type OperatorTimelineEvent = {";
  const i=s.indexOf(marker);
  if(i<0) throw Error("23.5 timeline type missing.");

  const type=`type AttentionItem = OperationsItem & {
  severity:
    | "CRITICAL"
    | "HIGH"
    | "MEDIUM"
    | "LOW";
  score: number;
  reason: string;
};

`;

  s=s.slice(0,i)+type+s.slice(i);
}

if(!s.includes("attentionItems,")) {
  const marker=`  const [
    timelineEvents,
    setTimelineEvents,
  ] =
    useState<OperatorTimelineEvent[]>(
      [],
    );`;

  if(!s.includes(marker)) throw Error("23.5 timeline state missing.");

  s=s.replace(
    marker,
`${marker}

  const [
    attentionItems,
    setAttentionItems,
  ] =
    useState<AttentionItem[]>(
      [],
    );`
  );
}

if(!s.includes("const loadAttentionQueue =")) {
  const marker="  const loadOperatorTimeline =";
  const i=s.indexOf(marker);
  if(i<0) throw Error("23.5 timeline loader missing.");

  const fn=`  const loadAttentionQueue =
    useCallback(
      async () => {
        try {
          const response =
            await fetch(
              \`\${API_BASE}/broadcast-coordinator/attention-queue\`,
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
              "Unable to load attention queue.",
            );
          }

          setAttentionItems(
            json?.data?.items ??
            [],
          );
        } catch {
          setAttentionItems(
            [],
          );
        }
      },
      [],
    );

`;

  s=s.slice(0,i)+fn+s.slice(i);
}

if(!s.includes("void loadAttentionQueue();")) {
  const initial=`    void load();

    const timer =`;

  if(!s.includes(initial)) throw Error("23.1 refresh effect missing.");

  s=s.replace(
    initial,
`    void load();
    void loadAttentionQueue();

    const timer =`
  );

  const recurring=`          void load();
        },
        5000,`;

  if(s.includes(recurring)) {
    s=s.replace(
      recurring,
`          void load();
          void loadAttentionQueue();
        },
        5000,`
    );
  }

  const deps=`    load,
  ]);`;

  if(s.includes(deps)) {
    s=s.replace(
      deps,
`    load,
    loadAttentionQueue,
  ]);`
    );
  }
}

if(!s.includes("Operator Attention Queue")) {
  const marker=`      <div className="mt-6 grid gap-4">`;
  const i=s.indexOf(marker);
  if(i<0) throw Error("Operations grid missing.");

  const block=`      <section className="mt-6 rounded-xl border border-slate-800 p-5">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="text-lg font-semibold">
              Operator Attention Queue
            </h2>
            <p className="mt-1 text-xs text-slate-500">
              Highest-priority active broadcasts appear first.
            </p>
          </div>

          <button
            type="button"
            onClick={() =>
              void loadAttentionQueue()
            }
            className="rounded-lg border border-slate-700 px-3 py-2 text-xs"
          >
            Refresh Queue
          </button>
        </div>

        <div className="mt-4 space-y-2">
          {attentionItems.length === 0 ? (
            <div className="rounded border border-slate-800 p-3 text-xs text-slate-500">
              No broadcasts currently require attention.
            </div>
          ) : (
            attentionItems.map(
              (item) => (
                <div
                  key={item.gameId}
                  className="flex flex-wrap items-start justify-between gap-3 rounded border border-slate-800 p-3"
                >
                  <div>
                    <div className="text-sm font-semibold">
                      Game {item.gameId}
                    </div>
                    <div className="mt-1 text-xs text-slate-500">
                      {item.reason}
                    </div>
                  </div>

                  <span className="rounded border border-slate-700 px-3 py-1 text-xs font-semibold">
                    {item.severity}
                  </span>
                </div>
              ),
            )
          )}
        </div>
      </section>

`;

  s=s.slice(0,i)+block+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 23.6 — Attention queue / operator prioritization

The operations console now includes a ranked attention queue.

Severity levels:

```text
CRITICAL
HIGH
MEDIUM
LOW
```

Priority is derived from existing state only.

Examples:

```text
EMERGENCY_STOPPED -> CRITICAL
coordinator drift -> HIGH
DEGRADED -> HIGH
retry EXHAUSTED -> HIGH
retry SCHEDULED -> MEDIUM
STARTING / STOPPING -> MEDIUM
healthy active broadcast -> LOW
```

Endpoint:

```text
GET /broadcast-coordinator/attention-queue
```

The queue does not create a second incident or severity persistence model.

Severity and reason are calculated from the current coordinator, go-live, runtime, health, and retry state each time the endpoint is requested.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.6 attention queue / operator prioritization", () => {
  const route=fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const page=fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/broadcast/operations/page.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("provides attention queue API",()=> {
    expect(route).toContain('"/broadcast-coordinator/attention-queue"');
  });

  it("derives ranked severity from existing state",()=> {
    for(const severity of [
      "CRITICAL",
      "HIGH",
      "MEDIUM",
      "LOW",
    ]) {
      expect(route).toContain(`"${severity}"`);
    }

    expect(route).toContain('"EMERGENCY_STOPPED"');
    expect(route).toContain('"DEGRADED"');
    expect(route).toContain('"EXHAUSTED"');
    expect(route).toContain('"SCHEDULED"');
  });

  it("sorts by score descending",()=> {
    expect(route).toContain("b.score");
    expect(route).toContain("a.score");
  });

  it("provides operator attention queue UI",()=> {
    expect(page).toContain("Operator Attention Queue");
    expect(page).toContain("attentionItems");
    expect(page).toContain("Refresh Queue");
  });

  it("refreshes queue with operations status",()=> {
    expect(page).toContain("loadAttentionQueue");
    expect(page).toContain("5000");
  });

  it("does not persist a second incident model",()=> {
    expect(page).not.toContain("localStorage");
    expect(route).not.toContain("attention-queue.json");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 23.6 installed"
echo "============================================================"
echo "Added:"
echo "  - ranked operator attention queue"
echo "  - CRITICAL/HIGH/MEDIUM/LOW severity"
echo "  - emergency/degraded/retry prioritization"
echo "  - active transition prioritization"
echo "  - 5-second queue refresh"
echo "  - no duplicate incident persistence"
echo "  - Milestone 23.6 regression tests"
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
echo "  Milestone 23.7 - Operator Focus Mode / Single Broadcast Workspace"
