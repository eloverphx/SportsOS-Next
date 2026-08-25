"use client";

import {
  useCallback,
  useEffect,
  useState,
} from "react";

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

type AttentionItem = OperationsItem & {
  severity:
    | "CRITICAL"
    | "HIGH"
    | "MEDIUM"
    | "LOW";
  score: number;
  reason: string;
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

  const [
    actionGameId,
    setActionGameId,
  ] =
    useState<string | null>(
      null,
    );

  const [
    actionMessage,
    setActionMessage,
  ] =
    useState<string | null>(
      null,
    );

  const [
    pendingStartGameId,
    setPendingStartGameId,
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
    );

  const [
    attentionItems,
    setAttentionItems,
  ] =
    useState<AttentionItem[]>(
      [],
    );

  const loadAttentionQueue =
    useCallback(
      async () => {
        try {
          const response =
            await fetch(
              `${API_BASE}/broadcast-coordinator/attention-queue`,
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

  const loadOperatorTimeline =
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
              `${API_BASE}/broadcast-coordinator/${encodeURIComponent(gameId)}/operator-timeline?limit=50`,
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

  const runGoLiveAction =
    useCallback(
      async (
        gameId: string,
        action:
          | "acknowledge-incident"
          | "retry-health"
          | "emergency-stop",
        body?: Record<string, unknown>,
      ) => {
        setActionGameId(
          gameId,
        );

        setActionMessage(
          null,
        );

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
              `Go-live operator action failed (${response.status}).`,
            );
          }

          setActionMessage(
            `${action} completed for game ${gameId}.`,
          );

          await load();
        } catch (actionError) {
          setActionMessage(
            actionError instanceof Error
              ? actionError.message
              : "Go-live operator action failed.",
          );
        } finally {
          setActionGameId(
            null,
          );
        }
      },
      [],
    );

  const runAction =
    useCallback(
      async (
        gameId: string,
        action:
          | "prepare"
          | "reconcile"
          | "retry/execute"
          | "start"
          | "stop",
      ) => {
        setActionGameId(
          gameId,
        );

        setActionMessage(
          null,
        );

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
              `Operator action failed (${response.status}).`,
            );
          }

          setActionMessage(
            `${action} completed for game ${gameId}.`,
          );

          await load();
        } catch (actionError) {
          setActionMessage(
            actionError instanceof Error
              ? actionError.message
              : "Operator action failed.",
          );
        } finally {
          setActionGameId(
            null,
          );
        }
      },
      [],
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
    void loadAttentionQueue();

    const timer =
      window.setInterval(
        () => {
          void load();
          void loadAttentionQueue();
        },
        5000,
      );

    return () =>
      window.clearInterval(
        timer,
      );
  }, [
    load,
    loadAttentionQueue,
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

      {actionMessage && (
        <div className="mt-4 rounded-lg border border-slate-800 p-4 text-sm text-slate-300">
          {actionMessage}
        </div>
      )}

      <section className="mt-6 rounded-xl border border-slate-800 p-5">
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

                  <a
                    href={`/broadcast/operations/${encodeURIComponent(item.gameId)}`}
                    className="rounded-lg border border-slate-700 px-3 py-2 text-xs"
                  >
                    Open Focus Mode
                  </a>
                </div>
              ),
            )
          )}
        </div>
      </section>

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

                <div className="mt-4 rounded border border-slate-800 p-3">
                  <div className="text-xs font-semibold">
                    Safe Operator Actions
                  </div>
                  <p className="mt-1 text-xs text-slate-500">
                    Actions are routed through the existing broadcast coordinator safety layer.
                  </p>
                  <p className="mt-1 text-xs text-slate-500">
                    Start requires PREPARE + healthy coordinator and a second operator confirmation.
                  </p>

                  <div className="mt-3 flex flex-wrap gap-2">
                    <button
                      type="button"
                      disabled={
                        actionGameId ===
                        item.gameId
                      }
                      onClick={() =>
                        void runAction(
                          item.gameId,
                          "prepare",
                        )
                      }
                      className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
                    >
                      Prepare
                    </button>

                    <button
                      type="button"
                      disabled={
                        actionGameId ===
                        item.gameId
                      }
                      onClick={() =>
                        void runAction(
                          item.gameId,
                          "reconcile",
                        )
                      }
                      className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
                    >
                      Reconcile
                    </button>

                    <button
                      type="button"
                      disabled={
                        actionGameId ===
                        item.gameId ||
                        item.retry.state !==
                          "SCHEDULED"
                      }
                      onClick={() =>
                        void runAction(
                          item.gameId,
                          "retry/execute",
                        )
                      }
                      className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
                    >
                      Execute Retry
                    </button>

                    {pendingStartGameId === item.gameId ? (
                      <>
                        <button
                          type="button"
                          disabled={
                            actionGameId ===
                            item.gameId ||
                            !item.health.healthy ||
                            item.snapshot.coordinator.intent !==
                              "PREPARE"
                          }
                          onClick={async () => {
                            await runAction(
                              item.gameId,
                              "start",
                            );

                            setPendingStartGameId(
                              null,
                            );
                          }}
                          className="rounded-lg border border-emerald-800 px-3 py-2 text-xs font-semibold text-emerald-300 disabled:opacity-50"
                        >
                          Confirm Start Broadcast
                        </button>

                        <button
                          type="button"
                          disabled={
                            actionGameId ===
                            item.gameId
                          }
                          onClick={() =>
                            setPendingStartGameId(
                              null,
                            )
                          }
                          className="rounded-lg border border-slate-800 px-3 py-2 text-xs disabled:opacity-50"
                        >
                          Cancel Start
                        </button>
                      </>
                    ) : (
                      <button
                        type="button"
                        disabled={
                          actionGameId ===
                            item.gameId ||
                          !item.health.healthy ||
                          item.snapshot.coordinator.intent !==
                            "PREPARE"
                        }
                        onClick={() =>
                          setPendingStartGameId(
                            item.gameId,
                          )
                        }
                        className="rounded-lg border border-emerald-900/60 px-3 py-2 text-xs font-semibold disabled:opacity-50"
                      >
                        Start Broadcast
                      </button>
                    )}

                    <button
                      type="button"
                      disabled={
                        actionGameId ===
                        item.gameId
                      }
                      onClick={() =>
                        void runAction(
                          item.gameId,
                          "stop",
                        )
                      }
                      className="rounded-lg border border-slate-800 px-3 py-2 text-xs disabled:opacity-50"
                    >
                      Stop Broadcast
                    </button>
                  </div>
                </div>

                <div className="mt-4 rounded border border-slate-800 p-3">
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

                {(item.snapshot.goLive.status === "DEGRADED" ||
                  item.snapshot.goLive.status === "EMERGENCY_STOPPED" ||
                  item.snapshot.goLive.status === "LIVE") && (
                  <div className="mt-4 rounded border border-red-900/40 bg-red-950/10 p-3">
                    <div className="text-xs font-semibold text-red-300">
                      Incident / Emergency Controls
                    </div>

                    {item.snapshot.goLive.status === "DEGRADED" && (
                      <>
                        <p className="mt-1 text-xs text-slate-500">
                          Acknowledge awareness or retry the existing live-health evaluation.
                        </p>

                        <div className="mt-3 grid gap-3 md:grid-cols-2">
                          <input
                            value={incidentOperator}
                            onChange={(event) =>
                              setIncidentOperator(
                                event.target.value,
                              )
                            }
                            placeholder="Operator name"
                            className="rounded-lg border border-slate-800 bg-transparent px-3 py-2 text-xs"
                          />

                          <div className="flex flex-wrap gap-2">
                            <button
                              type="button"
                              disabled={
                                actionGameId === item.gameId ||
                                !incidentOperator.trim()
                              }
                              onClick={() =>
                                void runGoLiveAction(
                                  item.gameId,
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
                              disabled={
                                actionGameId === item.gameId
                              }
                              onClick={() =>
                                void runGoLiveAction(
                                  item.gameId,
                                  "retry-health",
                                )
                              }
                              className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
                            >
                              Retry Health Check
                            </button>
                          </div>
                        </div>
                      </>
                    )}

                    {item.snapshot.goLive.status !== "EMERGENCY_STOPPED" && (
                      <div className="mt-4 grid gap-3 md:grid-cols-2">
                        <input
                          value={emergencyReason}
                          onChange={(event) =>
                            setEmergencyReason(
                              event.target.value,
                            )
                          }
                          placeholder="Emergency stop reason"
                          className="rounded-lg border border-red-900/50 bg-transparent px-3 py-2 text-xs"
                        />

                        <button
                          type="button"
                          disabled={
                            actionGameId === item.gameId
                          }
                          onClick={() =>
                            void runGoLiveAction(
                              item.gameId,
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
                    )}

                    {item.snapshot.goLive.status === "EMERGENCY_STOPPED" && (
                      <div className="mt-3 text-xs text-red-300">
                        Emergency stop is active
                        {item.snapshot.goLive.emergencyStopReason
                          ? `: ${item.snapshot.goLive.emergencyStopReason}`
                          : "."}
                      </div>
                    )}
                  </div>
                )}

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
