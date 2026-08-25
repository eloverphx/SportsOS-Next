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

type ResilienceStatus = {
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

type HandoffSummary = {
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

type OperatorNote = {
  id: string;
  gameId: string;
  operator: string;
  note: string;
  createdAt: string;
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

  const [
    operatorNotes,
    setOperatorNotes,
  ] =
    useState<OperatorNote[]>(
      [],
    );

  const [
    handoffOperator,
    setHandoffOperator,
  ] =
    useState("");

  const [
    handoffNote,
    setHandoffNote,
  ] =
    useState("");

  const [
    handoffSummary,
    setHandoffSummary,
  ] =
    useState<HandoffSummary | null>(
      null,
    );

  const [
    recoveryOperator,
    setRecoveryOperator,
  ] =
    useState("");

  const [
    approveDestructiveRecovery,
    setApproveDestructiveRecovery,
  ] =
    useState(false);

  const [
    resilienceStatus,
    setResilienceStatus,
  ] =
    useState<ResilienceStatus | null>(
      null,
    );

  const load =
    useCallback(
      async () => {
        const [
          snapshotResponse,
          healthResponse,
          retryResponse,
          timelineResponse,
          notesResponse,
          resilienceResponse,
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
            fetch(
              `${API_BASE}/broadcast-coordinator/${encodeURIComponent(gameId)}/operator-notes`,
              {
                cache:
                  "no-store",
              },
            ),
            fetch(
              `${API_BASE}/broadcast-coordinator/${encodeURIComponent(gameId)}/resilience-status`,
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

        const notesJson =
          await notesResponse.json();

        const resilienceJson =
          await resilienceResponse.json();

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

        setOperatorNotes(
          notesJson?.data?.notes ??
          [],
        );

        setResilienceStatus(
          resilienceJson?.data ??
          null,
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

  const executeRecovery =
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
              `${API_BASE}/broadcast-coordinator/${encodeURIComponent(gameId)}/recovery/execute`,
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

  const loadHandoffSummary =
    useCallback(
      async () => {
        setBusy(
          true,
        );

        try {
          const response =
            await fetch(
              `${API_BASE}/broadcast-coordinator/${encodeURIComponent(gameId)}/handoff-summary`,
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

  const saveOperatorNote =
    useCallback(
      async () => {
        if (
          !handoffOperator.trim() ||
          !handoffNote.trim()
        ) {
          setMessage(
            "Operator name and note are required.",
          );
          return;
        }

        setBusy(
          true,
        );

        try {
          const response =
            await fetch(
              `${API_BASE}/broadcast-coordinator/${encodeURIComponent(gameId)}/operator-notes`,
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
                      handoffOperator.trim(),
                    note:
                      handoffNote.trim(),
                  }),
              },
            );

          const json =
            await response.json();

          if (!response.ok) {
            throw new Error(
              json?.error ??
              "Unable to save operator note.",
            );
          }

          setHandoffNote(
            "",
          );

          setMessage(
            "Operator note saved.",
          );

          await load();
        } catch (error) {
          setMessage(
            error instanceof Error
              ? error.message
              : "Unable to save operator note.",
          );
        } finally {
          setBusy(
            false,
          );
        }
      },
      [
        gameId,
        handoffNote,
        handoffOperator,
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
                            key={`${event.timestamp}-${event.type}-${index}`}
                            className="text-xs text-slate-400"
                          >
                            {event.timestamp} · {event.source} · {event.type}
                            {event.detail
                              ? ` — ${event.detail}`
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

          <section className="mt-4 rounded-xl border border-slate-800 p-5">
            <div className="text-sm font-semibold">
              Shift Handoff Notes
            </div>

            <p className="mt-1 text-xs text-slate-500">
              Operational context only. Notes do not affect broadcast state or automation.
            </p>

            <div className="mt-3 grid gap-3 md:grid-cols-2">
              <input
                value={handoffOperator}
                onChange={(event) =>
                  setHandoffOperator(
                    event.target.value,
                  )
                }
                placeholder="Operator name"
                className="rounded-lg border border-slate-800 bg-transparent px-3 py-2 text-xs"
              />

              <button
                type="button"
                disabled={
                  busy ||
                  !handoffOperator.trim() ||
                  !handoffNote.trim()
                }
                onClick={() =>
                  void saveOperatorNote()
                }
                className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
              >
                Save Handoff Note
              </button>
            </div>

            <textarea
              value={handoffNote}
              onChange={(event) =>
                setHandoffNote(
                  event.target.value,
                )
              }
              placeholder="Current issue, workaround, expected next action, or handoff context…"
              rows={4}
              className="mt-3 w-full rounded-lg border border-slate-800 bg-transparent px-3 py-2 text-xs"
            />

            <div className="mt-4 space-y-2">
              {operatorNotes.length === 0 ? (
                <div className="text-xs text-slate-500">
                  No handoff notes recorded.
                </div>
              ) : (
                operatorNotes.map(
                  (note) => (
                    <div
                      key={note.id}
                      className="rounded border border-slate-800 p-3"
                    >
                      <div className="flex flex-wrap justify-between gap-2">
                        <div className="text-xs font-semibold">
                          {note.operator}
                        </div>

                        <div className="text-xs text-slate-500">
                          {note.createdAt}
                        </div>
                      </div>

                      <div className="mt-2 whitespace-pre-wrap text-xs text-slate-400">
                        {note.note}
                      </div>
                    </div>
                  ),
                )
              )}
            </div>
          </section>

          <section className="mt-4 rounded-xl border border-slate-800 p-5">
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

          <section className="mt-4 rounded-xl border border-amber-900/40 p-5">
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
