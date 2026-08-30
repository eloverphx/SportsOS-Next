#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-23.7-operator-focus-mode-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

PAGE="apps/dashboard/app/broadcast/operations/page.tsx"
FOCUS="apps/dashboard/app/broadcast/operations/[gameId]/page.tsx"
TEST="packages/core/test/broadcast-operator-focus-mode-23.7.test.ts"
DOC="docs/BROADCAST-OPERATIONS-CONSOLE.md"

for required in ".git" "$PAGE" "$DOC"; do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$PAGE" "$FOCUS" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$FOCUS")" "$(dirname "$TEST")"

node <<'NODE'
const fs=require("fs");
const f="apps/dashboard/app/broadcast/operations/page.tsx";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("Open Focus Mode")) {
  const marker=`                  <span className="rounded border border-slate-700 px-3 py-1 text-xs font-semibold">
                    {item.severity}
                  </span>`;

  if(!s.includes(marker)) throw Error("23.6 attention severity badge missing.");

  s=s.replace(
    marker,
`${marker}

                  <a
                    href={\`/broadcast/operations/\${encodeURIComponent(item.gameId)}\`}
                    className="rounded-lg border border-slate-700 px-3 py-2 text-xs"
                  >
                    Open Focus Mode
                  </a>`
  );
}

fs.writeFileSync(f,s);
NODE

cat > "$FOCUS" <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";

import {
  useParams,
} from "next/navigation";

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

type CoordinatorSnapshot = {
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

type CoordinatorHealth = {
  healthy: boolean;
  issues: Array<{
    id: string;
    message: string;
  }>;
};

type CoordinatorRetry = {
  state: string;
  attempts: number;
  maxAttempts: number;
  nextRetryAt: string | null;
  lastError: string | null;
};

type OperatorTimelineEvent = {
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

export default function BroadcastFocusPage() {
  const params =
    useParams<{
      gameId: string;
    }>();

  const gameId =
    useMemo(
      () =>
        decodeURIComponent(
          params.gameId,
        ),
      [
        params.gameId,
      ],
    );

  const [
    snapshot,
    setSnapshot,
  ] =
    useState<CoordinatorSnapshot | null>(
      null,
    );

  const [
    health,
    setHealth,
  ] =
    useState<CoordinatorHealth | null>(
      null,
    );

  const [
    retry,
    setRetry,
  ] =
    useState<CoordinatorRetry | null>(
      null,
    );

  const [
    timeline,
    setTimeline,
  ] =
    useState<OperatorTimelineEvent[]>(
      [],
    );

  const [
    busy,
    setBusy,
  ] =
    useState(false);

  const [
    message,
    setMessage,
  ] =
    useState<string | null>(
      null,
    );

  const [
    incidentOperator,
    setIncidentOperator,
  ] =
    useState("");

  const [
    emergencyReason,
    setEmergencyReason,
  ] =
    useState("");

  const load =
    useCallback(
      async () => {
        const [
          snapshotResponse,
          healthResponse,
          retryResponse,
          timelineResponse,
        ] =
          await Promise.all([
            fetch(
              `${API_BASE}/broadcast-coordinator/${encodeURIComponent(gameId)}`,
              {
                cache:
                  "no-store",
              },
            ),
            fetch(
              `${API_BASE}/broadcast-coordinator/${encodeURIComponent(gameId)}/health`,
              {
                cache:
                  "no-store",
              },
            ),
            fetch(
              `${API_BASE}/broadcast-coordinator/${encodeURIComponent(gameId)}/retry`,
              {
                cache:
                  "no-store",
              },
            ),
            fetch(
              `${API_BASE}/broadcast-coordinator/${encodeURIComponent(gameId)}/operator-timeline?limit=50`,
              {
                cache:
                  "no-store",
              },
            ),
          ]);

        const snapshotJson =
          await snapshotResponse.json();

        const healthJson =
          await healthResponse.json();

        const retryJson =
          await retryResponse.json();

        const timelineJson =
          await timelineResponse.json();

        if (!snapshotResponse.ok) {
          throw new Error(
            snapshotJson?.error ??
            "Unable to load broadcast.",
          );
        }

        setSnapshot(
          snapshotJson?.data ??
          null,
        );

        setHealth(
          healthJson?.data?.health ??
          null,
        );

        setRetry(
          retryJson?.data?.retry ??
          null,
        );

        setTimeline(
          timelineJson?.data?.events ??
          [],
        );
      },
      [
        gameId,
      ],
    );

  const runCoordinatorAction =
    useCallback(
      async (
        action:
          | "prepare"
          | "reconcile"
          | "retry/execute"
          | "start"
          | "stop",
      ) => {
        setBusy(true);

        try {
          const response =
            await fetch(
              `${API_BASE}/broadcast-coordinator/${encodeURIComponent(gameId)}/${action}`,
              {
                method:
                  "POST",
              },
            );

          const json =
            await response.json();

          if (!response.ok) {
            throw new Error(
              json?.error ??
              "Coordinator action failed.",
            );
          }

          setMessage(
            `${action} completed.`,
          );

          await load();
        } catch (error) {
          setMessage(
            error instanceof Error
              ? error.message
              : "Coordinator action failed.",
          );
        } finally {
          setBusy(false);
        }
      },
      [
        gameId,
        load,
      ],
    );

  const runGoLiveAction =
    useCallback(
      async (
        action:
          | "acknowledge-incident"
          | "retry-health"
          | "emergency-stop",
        body?: Record<string, unknown>,
      ) => {
        setBusy(true);

        try {
          const response =
            await fetch(
              `${API_BASE}/go-live-sessions/${encodeURIComponent(gameId)}/${action}`,
              {
                method:
                  "POST",
                headers: {
                  "Content-Type":
                    "application/json",
                },
                body:
                  JSON.stringify(
                    body ??
                    {},
                  ),
              },
            );

          const json =
            await response.json();

          if (!response.ok) {
            throw new Error(
              json?.error ??
              "Go-live action failed.",
            );
          }

          setMessage(
            `${action} completed.`,
          );

          await load();
        } catch (error) {
          setMessage(
            error instanceof Error
              ? error.message
              : "Go-live action failed.",
          );
        } finally {
          setBusy(false);
        }
      },
      [
        gameId,
        load,
      ],
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
    <main className="mx-auto max-w-6xl p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <a
            href="/broadcast/operations"
            className="text-xs text-slate-500"
          >
            ← Broadcast Operations
          </a>

          <h1 className="mt-2 text-2xl font-bold">
            Broadcast Focus — Game {gameId}
          </h1>

          <p className="mt-1 text-sm text-slate-500">
            Single-broadcast operator workspace.
          </p>
        </div>

        <button
          type="button"
          disabled={busy}
          onClick={() =>
            void load()
          }
          className="rounded-lg border border-slate-700 px-4 py-2 text-sm disabled:opacity-50"
        >
          Refresh
        </button>
      </div>

      {message && (
        <div className="mt-4 rounded-lg border border-slate-800 p-4 text-sm">
          {message}
        </div>
      )}

      {!snapshot ? (
        <div className="mt-6 rounded-xl border border-slate-800 p-6 text-sm text-slate-500">
          Loading broadcast state…
        </div>
      ) : (
        <>
          <section className="mt-6 grid gap-3 md:grid-cols-5">
            <div className="rounded-xl border border-slate-800 p-4">
              <div className="text-xs text-slate-500">Coordinator</div>
              <div className="mt-1 font-semibold">{snapshot.coordinator.intent}</div>
            </div>

            <div className="rounded-xl border border-slate-800 p-4">
              <div className="text-xs text-slate-500">Go-Live</div>
              <div className="mt-1 font-semibold">{snapshot.goLive.status}</div>
            </div>

            <div className="rounded-xl border border-slate-800 p-4">
              <div className="text-xs text-slate-500">Encoder</div>
              <div className="mt-1 font-semibold">{snapshot.runtime.session.status}</div>
            </div>

            <div className="rounded-xl border border-slate-800 p-4">
              <div className="text-xs text-slate-500">Publish Health</div>
              <div className="mt-1 font-semibold">{snapshot.runtime.telemetry.health}</div>
            </div>

            <div className="rounded-xl border border-slate-800 p-4">
              <div className="text-xs text-slate-500">Retry</div>
              <div className="mt-1 font-semibold">{retry?.state ?? "UNKNOWN"}</div>
            </div>
          </section>

          <section className="mt-4 rounded-xl border border-slate-800 p-5">
            <div className="text-sm font-semibold">Safe Operator Actions</div>

            <div className="mt-3 flex flex-wrap gap-2">
              <button
                type="button"
                disabled={busy}
                onClick={() => void runCoordinatorAction("prepare")}
                className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
              >
                Prepare
              </button>

              <button
                type="button"
                disabled={
                  busy ||
                  !health?.healthy ||
                  snapshot.coordinator.intent !==
                    "PREPARE"
                }
                onClick={() => void runCoordinatorAction("start")}
                className="rounded-lg border border-emerald-800 px-3 py-2 text-xs disabled:opacity-50"
              >
                Start
              </button>

              <button
                type="button"
                disabled={busy}
                onClick={() => void runCoordinatorAction("reconcile")}
                className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
              >
                Reconcile
              </button>

              <button
                type="button"
                disabled={
                  busy ||
                  retry?.state !==
                    "SCHEDULED"
                }
                onClick={() => void runCoordinatorAction("retry/execute")}
                className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
              >
                Execute Retry
              </button>

              <button
                type="button"
                disabled={busy}
                onClick={() => void runCoordinatorAction("stop")}
                className="rounded-lg border border-slate-800 px-3 py-2 text-xs disabled:opacity-50"
              >
                Stop
              </button>
            </div>
          </section>

          {health && !health.healthy && (
            <section className="mt-4 rounded-xl border border-amber-900/40 p-5">
              <div className="text-sm font-semibold">Attention Required</div>

              <div className="mt-3 space-y-2">
                {health.issues.map(
                  (issue) => (
                    <div
                      key={issue.id}
                      className="rounded border border-slate-800 p-3 text-xs"
                    >
                      {issue.id}: {issue.message}
                    </div>
                  ),
                )}
              </div>
            </section>
          )}

          {snapshot.goLive.status === "DEGRADED" && (
            <section className="mt-4 rounded-xl border border-red-900/40 p-5">
              <div className="text-sm font-semibold text-red-300">
                Incident Controls
              </div>

              <div className="mt-3 grid gap-3 md:grid-cols-2">
                <input
                  value={incidentOperator}
                  onChange={(event) =>
                    setIncidentOperator(event.target.value)
                  }
                  placeholder="Operator name"
                  className="rounded-lg border border-slate-800 bg-transparent px-3 py-2 text-xs"
                />

                <div className="flex flex-wrap gap-2">
                  <button
                    type="button"
                    disabled={
                      busy ||
                      !incidentOperator.trim()
                    }
                    onClick={() =>
                      void runGoLiveAction(
                        "acknowledge-incident",
                        {
                          operator:
                            incidentOperator.trim(),
                        },
                      )
                    }
                    className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
                  >
                    Acknowledge Incident
                  </button>

                  <button
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      void runGoLiveAction(
                        "retry-health",
                      )
                    }
                    className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
                  >
                    Retry Health
                  </button>
                </div>
              </div>
            </section>
          )}

          {snapshot.goLive.status !== "EMERGENCY_STOPPED" && (
            <section className="mt-4 rounded-xl border border-red-900/40 p-5">
              <div className="text-sm font-semibold text-red-300">
                Emergency Stop
              </div>

              <div className="mt-3 grid gap-3 md:grid-cols-2">
                <input
                  value={emergencyReason}
                  onChange={(event) =>
                    setEmergencyReason(event.target.value)
                  }
                  placeholder="Emergency stop reason"
                  className="rounded-lg border border-red-900/50 bg-transparent px-3 py-2 text-xs"
                />

                <button
                  type="button"
                  disabled={busy}
                  onClick={() =>
                    void runGoLiveAction(
                      "emergency-stop",
                      {
                        reason:
                          emergencyReason.trim() ||
                          null,
                      },
                    )
                  }
                  className="rounded-lg border border-red-800 px-3 py-2 text-xs font-semibold text-red-300 disabled:opacity-50"
                >
                  Emergency Stop Broadcast
                </button>
              </div>
            </section>
          )}

          <section className="mt-4 rounded-xl border border-slate-800 p-5">
            <div className="text-sm font-semibold">Operator Timeline</div>

            <div className="mt-3 space-y-2">
              {timeline.length === 0 ? (
                <div className="text-xs text-slate-500">
                  No operator history recorded.
                </div>
              ) : (
                timeline.map(
                  (event) => (
                    <div
                      key={event.id}
                      className="rounded border border-slate-800 p-3"
                    >
                      <div className="flex flex-wrap justify-between gap-2">
                        <div className="text-xs font-semibold">
                          {event.type} · {event.source}
                        </div>

                        <div className="text-xs text-slate-500">
                          {event.timestamp}
                        </div>
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
                    </div>
                  ),
                )
              )}
            </div>
          </section>
        </>
      )}
    </main>
  );
}
EOF

cat >> "$DOC" <<'EOF'

## Milestone 23.7 — Operator focus mode / single broadcast workspace

The operations console now links each attention item to:

```text
/broadcast/operations/:gameId
```

Focus Mode consolidates one broadcast's coordinator intent, go-live state, encoder state, publish health, retry state, coordinator health issues, safe coordinator actions, degraded incident controls, emergency stop, and operator timeline.

Focus Mode consumes the existing coordinator and go-live APIs only.

It does not create new lifecycle, incident, audit, retry, or encoder state.

The workspace refreshes every 5 seconds.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.7 operator focus mode / single broadcast workspace", () => {
  const operations =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const focus =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/[gameId]/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("links attention queue into focus mode",()=> {
    expect(operations).toContain("Open Focus Mode");
    expect(operations).toContain("/broadcast/operations/");
  });

  it("provides single-broadcast workspace",()=> {
    expect(focus).toContain("Broadcast Focus");
    expect(focus).toContain("Single-broadcast operator workspace");
  });

  it("shows core operational state",()=> {
    expect(focus).toContain("Coordinator");
    expect(focus).toContain("Go-Live");
    expect(focus).toContain("Encoder");
    expect(focus).toContain("Publish Health");
    expect(focus).toContain("Retry");
  });

  it("provides existing safe control surfaces",()=> {
    expect(focus).toContain("Safe Operator Actions");
    expect(focus).toContain("Acknowledge Incident");
    expect(focus).toContain("Emergency Stop Broadcast");
  });

  it("shows operator timeline",()=> {
    expect(focus).toContain("Operator Timeline");
    expect(focus).toContain("operator-timeline");
  });

  it("does not directly control encoder runtime",()=> {
    expect(focus).not.toContain("startEncoderRuntime");
    expect(focus).not.toContain("stopEncoderRuntime");
  });

  it("refreshes every five seconds",()=> {
    expect(focus).toContain("5000");
    expect(focus).toContain("setInterval");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 23.7 installed"
echo "============================================================"
echo "Added:"
echo "  - attention queue Focus Mode links"
echo "  - /broadcast/operations/:gameId workspace"
echo "  - single-broadcast status view"
echo "  - safe coordinator actions"
echo "  - incident and emergency controls"
echo "  - operator timeline"
echo "  - 5-second refresh"
echo "  - no duplicate backend state"
echo "  - Milestone 23.7 regression tests"
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
echo "  Milestone 23.8 - Operator Notes / Shift Handoff Context"
