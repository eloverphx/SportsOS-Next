#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-23.1-broadcast-ops-console-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
PAGE="apps/dashboard/app/broadcast/operations/page.tsx"
TEST="packages/core/test/broadcast-operations-console-23.1.test.ts"
DOC="docs/BROADCAST-OPERATIONS-CONSOLE.md"
STATUS="docs/MILESTONE-STATUS.md"

for required in \
  ".git" \
  "apps/api/src/services/broadcastSessionCoordinator.ts" \
  "apps/api/src/services/broadcastCoordinatorAudit.ts" \
  "$ROUTE"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$ROUTE" "$PAGE" "$TEST" "$DOC" "$STATUS"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$PAGE")" "$(dirname "$TEST")" docs

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes('"/broadcast-coordinator/operations-summary"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/active",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("22.9 active broadcast route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/operations-summary",
    async () => {
      const gameIds =
        listActiveBroadcastGameIds();

      const items =
        gameIds.map(
          (gameId) => ({
            gameId,
            snapshot:
              getBroadcastCoordinatorSnapshot(
                gameId,
              ),
            health:
              evaluateBroadcastCoordinatorHealth(
                gameId,
              ),
            retry:
              getBroadcastCoordinatorRetry(
                gameId,
              ),
          }),
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

cat > "$PAGE" <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
  useState,
} from "react";

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

type OperationsItem = {
  gameId: string;
  snapshot: {
    coordinator: {
      intent: string;
      correlationId: string;
      updatedAt: string;
      lastError: string | null;
    };
    goLive: {
      status: string;
      degradationReason?: string | null;
      emergencyStopReason?: string | null;
    };
    runtime: {
      session: {
        status: string;
      };
      telemetry: {
        health: string;
      };
    };
  };
  health: {
    healthy: boolean;
    issues: Array<{
      id: string;
      message: string;
    }>;
  };
  retry: {
    state: string;
    attempts: number;
    maxAttempts: number;
    nextRetryAt: string | null;
    lastError: string | null;
  };
};

export default function BroadcastOperationsPage() {
  const [
    items,
    setItems,
  ] =
    useState<OperationsItem[]>(
      [],
    );

  const [
    loading,
    setLoading,
  ] =
    useState(false);

  const [
    error,
    setError,
  ] =
    useState<string | null>(
      null,
    );

  const load =
    useCallback(
      async () => {
        setLoading(true);

        try {
          const response =
            await fetch(
              `${API_BASE}/broadcast-coordinator/operations-summary`,
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
              "Unable to load broadcast operations.",
            );
          }

          setItems(
            json?.data?.items ??
            [],
          );

          setError(
            null,
          );
        } catch (loadError) {
          setError(
            loadError instanceof Error
              ? loadError.message
              : "Unable to load broadcast operations.",
          );
        } finally {
          setLoading(false);
        }
      },
      [],
    );

  useEffect(() => {
    void load();

    const timer =
      window.setInterval(
        () => {
          void load();
        },
        5000,
      );

    return () =>
      window.clearInterval(
        timer,
      );
  }, [
    load,
  ]);

  return (
    <main className="mx-auto max-w-7xl p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">
            Broadcast Operations
          </h1>
          <p className="mt-1 text-sm text-slate-500">
            Consolidated production view of coordinator, go-live, encoder, health, and retry state.
          </p>
        </div>

        <button
          type="button"
          disabled={
            loading
          }
          onClick={() =>
            void load()
          }
          className="rounded-lg border border-slate-700 px-4 py-2 text-sm disabled:opacity-50"
        >
          {loading
            ? "Refreshing..."
            : "Refresh"}
        </button>
      </div>

      {error && (
        <div className="mt-4 rounded-lg border border-red-900/50 bg-red-950/20 p-4 text-sm text-red-300">
          {error}
        </div>
      )}

      <div className="mt-6 grid gap-4">
        {items.length === 0 ? (
          <div className="rounded-xl border border-slate-800 p-6 text-sm text-slate-500">
            No active broadcasts.
          </div>
        ) : (
          items.map(
            (item) => (
              <section
                key={item.gameId}
                className="rounded-xl border border-slate-800 p-5"
              >
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <div className="text-lg font-semibold">
                      Game {item.gameId}
                    </div>
                    <div className="mt-1 text-xs text-slate-500">
                      Correlation: {item.snapshot.coordinator.correlationId}
                    </div>
                  </div>

                  <span className="rounded border border-slate-700 px-3 py-1 text-xs font-semibold">
                    {item.health.healthy
                      ? "HEALTHY"
                      : "ATTENTION"}
                  </span>
                </div>

                <div className="mt-4 grid gap-3 md:grid-cols-5">
                  <div className="rounded border border-slate-800 p-3">
                    <div className="text-xs text-slate-500">
                      Coordinator
                    </div>
                    <div className="mt-1 font-semibold">
                      {item.snapshot.coordinator.intent}
                    </div>
                  </div>

                  <div className="rounded border border-slate-800 p-3">
                    <div className="text-xs text-slate-500">
                      Go-Live
                    </div>
                    <div className="mt-1 font-semibold">
                      {item.snapshot.goLive.status}
                    </div>
                  </div>

                  <div className="rounded border border-slate-800 p-3">
                    <div className="text-xs text-slate-500">
                      Encoder
                    </div>
                    <div className="mt-1 font-semibold">
                      {item.snapshot.runtime.session.status}
                    </div>
                  </div>

                  <div className="rounded border border-slate-800 p-3">
                    <div className="text-xs text-slate-500">
                      Publish Health
                    </div>
                    <div className="mt-1 font-semibold">
                      {item.snapshot.runtime.telemetry.health}
                    </div>
                  </div>

                  <div className="rounded border border-slate-800 p-3">
                    <div className="text-xs text-slate-500">
                      Retry
                    </div>
                    <div className="mt-1 font-semibold">
                      {item.retry.state}
                    </div>
                    <div className="mt-1 text-xs text-slate-500">
                      {item.retry.attempts}/{item.retry.maxAttempts}
                    </div>
                  </div>
                </div>

                {item.health.issues.length > 0 && (
                  <div className="mt-4 rounded border border-amber-900/40 bg-amber-950/10 p-3">
                    <div className="text-xs font-semibold">
                      Coordinator Issues
                    </div>

                    <div className="mt-2 space-y-2">
                      {item.health.issues.map(
                        (issue) => (
                          <div
                            key={issue.id}
                            className="text-xs text-slate-400"
                          >
                            {issue.id}: {issue.message}
                          </div>
                        ),
                      )}
                    </div>
                  </div>
                )}
              </section>
            ),
          )
        )}
      </div>
    </main>
  );
}
EOF

cat > "$DOC" <<'EOF'
# Broadcast Operations Console

Milestone 23 begins the operator-experience layer for production broadcast operations.

## Milestone 23.1 — Operations console foundation

The dashboard adds:

```text
/broadcast/operations
```

The page consolidates:

- coordinator intent
- go-live session state
- encoder runtime state
- publish health
- coordinator health/drift
- retry state
- correlation ID

API:

```text
GET /broadcast-coordinator/operations-summary
```

The operations console is read-only in Milestone 23.1.

It does not introduce new lifecycle state or bypass existing safety controls.

The page refreshes every 5 seconds and also supports manual refresh.
EOF

if [[ -f "$STATUS" ]]; then
cat >> "$STATUS" <<'EOF'

### Milestone 23

Broadcast operations and operator experience.

Current work:

- 23.1 broadcast operations console foundation
EOF
fi

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.1 broadcast operations console foundation", () => {
  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const page =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("provides consolidated operations summary API",()=> {
    expect(route).toContain(
      '"/broadcast-coordinator/operations-summary"',
    );

    expect(route).toContain(
      "getBroadcastCoordinatorSnapshot",
    );

    expect(route).toContain(
      "evaluateBroadcastCoordinatorHealth",
    );

    expect(route).toContain(
      "getBroadcastCoordinatorRetry",
    );
  });

  it("provides broadcast operations page",()=> {
    expect(page).toContain(
      "Broadcast Operations",
    );

    expect(page).toContain(
      "/broadcast-coordinator/operations-summary",
    );
  });

  it("shows coordinator, go-live, encoder, health, and retry state",()=> {
    expect(page).toContain(
      "Coordinator",
    );

    expect(page).toContain(
      "Go-Live",
    );

    expect(page).toContain(
      "Encoder",
    );

    expect(page).toContain(
      "Publish Health",
    );

    expect(page).toContain(
      "Retry",
    );
  });

  it("surfaces coordinator issues",()=> {
    expect(page).toContain(
      "Coordinator Issues",
    );

    expect(page).toContain(
      "item.health.issues",
    );
  });

  it("refreshes every five seconds",()=> {
    expect(page).toContain(
      "5000",
    );

    expect(page).toContain(
      "setInterval",
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 23.1 installed"
echo "============================================================"
echo "Added:"
echo "  - consolidated operations-summary API"
echo "  - /broadcast/operations dashboard page"
echo "  - active broadcast status cards"
echo "  - coordinator/go-live/encoder/publish visibility"
echo "  - retry and drift visibility"
echo "  - 5-second refresh"
echo "  - read-only operator foundation"
echo "  - Milestone 23.1 regression tests"
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
echo "  Milestone 23.2 - Operator Actions / Safe Control Surface"
