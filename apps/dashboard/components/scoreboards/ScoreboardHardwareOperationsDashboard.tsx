"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";
import {
  type ScoreboardDeviceRuntime,
  type ScoreboardDevicesResponse,
} from "../../lib/scoreboard-devices";
import {
  buildScoreboardHardwareOperationsSummary,
  type ScoreboardAssignment,
} from "../../lib/scoreboard-hardware-operations";
import {
  ScoreboardDeviceOperations,
} from "./ScoreboardDeviceOperations";

const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_URL ??
  "";

type AssignmentsResponse = {
  success: boolean;
  data?: {
    assignments: ScoreboardAssignment[];
  };
};

async function loadDevices(): Promise<
  ScoreboardDeviceRuntime[]
> {
  const response = await fetch(
    `${API_BASE_URL}/scoreboard-devices`,
    {
      credentials: "include",
      cache: "no-store",
    },
  );

  if (!response.ok) {
    throw new Error(
      `Device request failed (${response.status}).`,
    );
  }

  const payload =
    (await response.json()) as ScoreboardDevicesResponse;

  return payload.data?.devices ?? [];
}

async function loadAssignments(): Promise<
  ScoreboardAssignment[]
> {
  const response = await fetch(
    `${API_BASE_URL}/scoreboard-devices/assignments`,
    {
      credentials: "include",
      cache: "no-store",
    },
  );

  if (!response.ok) {
    throw new Error(
      `Assignment request failed (${response.status}).`,
    );
  }

  const payload =
    (await response.json()) as AssignmentsResponse;

  return payload.data?.assignments ?? [];
}

export function ScoreboardHardwareOperationsDashboard() {
  const [devices, setDevices] = useState<
    ScoreboardDeviceRuntime[]
  >([]);
  const [assignments, setAssignments] =
    useState<ScoreboardAssignment[]>([]);
  const [gameId, setGameId] = useState("");
  const [deviceId, setDeviceId] =
    useState("");
  const [error, setError] =
    useState<string | null>(null);
  const [busy, setBusy] =
    useState(false);

  const load = useCallback(async () => {
    try {
      const [
        nextDevices,
        nextAssignments,
      ] = await Promise.all([
        loadDevices(),
        loadAssignments(),
      ]);

      setDevices(nextDevices);
      setAssignments(
        nextAssignments,
      );
      setError(null);
    } catch (loadError) {
      setError(
        loadError instanceof Error
          ? loadError.message
          : "Unable to load scoreboard hardware operations.",
      );
    }
  }, []);

  useEffect(() => {
    void load();

    const timer = window.setInterval(
      () => void load(),
      3000,
    );

    return () => {
      window.clearInterval(timer);
    };
  }, [load]);

  const summary = useMemo(
    () =>
      buildScoreboardHardwareOperationsSummary(
        devices,
        assignments,
      ),
    [
      assignments,
      devices,
    ],
  );

  const assign = async () => {
    if (
      !gameId.trim() ||
      !deviceId.trim()
    ) {
      setError(
        "Game ID and device ID are required.",
      );
      return;
    }

    setBusy(true);

    try {
      const response = await fetch(
        `${API_BASE_URL}/scoreboard-devices/assignments/${encodeURIComponent(
          gameId.trim(),
        )}`,
        {
          method: "PUT",
          credentials: "include",
          headers: {
            "Content-Type":
              "application/json",
          },
          body: JSON.stringify({
            deviceId:
              deviceId.trim(),
          }),
        },
      );

      if (!response.ok) {
        throw new Error(
          `Assignment failed (${response.status}).`,
        );
      }

      await load();
      setError(null);
    } catch (assignmentError) {
      setError(
        assignmentError instanceof Error
          ? assignmentError.message
          : "Unable to assign scoreboard.",
      );
    } finally {
      setBusy(false);
    }
  };

  const reconcile = async (
    targetDeviceId: string,
  ) => {
    setBusy(true);

    try {
      const response = await fetch(
        `${API_BASE_URL}/scoreboard-devices/${encodeURIComponent(
          targetDeviceId,
        )}/reconcile`,
        {
          method: "POST",
          credentials: "include",
        },
      );

      if (!response.ok) {
        throw new Error(
          `Reconcile failed (${response.status}).`,
        );
      }

      await load();
      setError(null);
    } catch (reconcileError) {
      setError(
        reconcileError instanceof Error
          ? reconcileError.message
          : "Unable to reconcile scoreboard.",
      );
    } finally {
      setBusy(false);
    }
  };

  return (
    <section
      data-testid="scoreboard-hardware-operations"
      className="space-y-6"
    >
      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
              Hardware stage
            </div>
            <div className="mt-1 text-2xl font-bold text-slate-100">
              {summary.stage}
            </div>
          </div>

          <div className="text-right">
            <div className="text-3xl font-bold text-slate-100">
              {summary.readinessPercent}%
            </div>
            <div className="text-xs text-slate-500">
              readiness
            </div>
          </div>
        </div>

        <div className="mt-4 h-2 overflow-hidden rounded-full bg-slate-900">
          <div
            className="h-full bg-slate-400 transition-all"
            style={{
              width:
                `${summary.readinessPercent}%`,
            }}
          />
        </div>

        <div className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {[
            [
              "Discovered",
              summary.discovered,
            ],
            [
              "Online",
              summary.online,
            ],
            [
              "Assigned",
              summary.assigned,
            ],
            [
              "Active games",
              summary.activeGames,
            ],
          ].map(
            ([label, value]) => (
              <div
                key={String(label)}
                className="rounded-lg border border-slate-800 bg-slate-950 p-3"
              >
                <div className="text-xs uppercase tracking-wide text-slate-500">
                  {String(label)}
                </div>
                <div className="mt-1 text-2xl font-bold text-slate-100">
                  {String(value)}
                </div>
              </div>
            ),
          )}
        </div>

        {summary.alerts.length > 0 ? (
          <div className="mt-4 grid gap-2">
            {summary.alerts.map(
              (alert) => (
                <div
                  key={alert}
                  className="rounded-lg border border-amber-900/50 bg-amber-950/20 px-3 py-2 text-xs text-amber-200"
                >
                  {alert}
                </div>
              ),
            )}
          </div>
        ) : null}
      </div>

      {error ? (
        <div className="rounded-xl border border-red-900/50 bg-red-950/20 px-4 py-3 text-sm text-red-200">
          {error}
        </div>
      ) : null}

      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          Game assignment
        </div>

        <div className="mt-4 grid gap-3 md:grid-cols-[1fr_1fr_auto]">
          <input
            value={gameId}
            onChange={(event) =>
              setGameId(
                event.target.value,
              )
            }
            placeholder="Game ID"
            className="rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-sm text-slate-100"
          />

          <input
            value={deviceId}
            onChange={(event) =>
              setDeviceId(
                event.target.value,
              )
            }
            placeholder="Scoreboard device ID"
            className="rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-sm text-slate-100"
          />

          <button
            type="button"
            disabled={busy}
            onClick={() =>
              void assign()
            }
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-semibold text-slate-200 disabled:opacity-50"
          >
            Assign
          </button>
        </div>
      </div>

      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
        <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          Current assignments
        </div>

        {assignments.length === 0 ? (
          <div className="mt-3 text-sm text-slate-500">
            No games are assigned to scoreboard devices.
          </div>
        ) : (
          <div className="mt-3 grid gap-2">
            {assignments.map(
              (assignment) => (
                <div
                  key={assignment.gameId}
                  className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-slate-800 bg-slate-950 px-3 py-3"
                >
                  <div className="text-sm text-slate-300">
                    <span className="font-mono text-slate-100">
                      {assignment.gameId}
                    </span>
                    {" → "}
                    <span className="font-mono text-slate-100">
                      {assignment.deviceId}
                    </span>
                  </div>

                  <button
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      void reconcile(
                        assignment.deviceId,
                      )
                    }
                    className="rounded-lg border border-slate-700 px-3 py-2 text-xs font-semibold text-slate-200 disabled:opacity-50"
                  >
                    Reconcile Now
                  </button>
                </div>
              ),
            )}
          </div>
        )}
      </div>

      <ScoreboardDeviceOperations />
    </section>
  );
}
