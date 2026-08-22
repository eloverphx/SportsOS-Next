import type {
  FastifyInstance,
} from "fastify";
import { recordScoreboardReadinessObservation } from "./scoreboardReadinessMetrics.js";

import {
  recordScoreboardControlAudit,
} from "./scoreboardControlAudit.js";

import {
  evaluateScoreboardControlReadiness,
} from "./scoreboardControlReadiness.js";

type Assignment = {
  gameId: string;
  deviceId: string;
};

type MonitorState =
  | "READY"
  | "NOT_READY";

type PendingState = {
  state: MonitorState;
  firstObservedAtMs: number;
};

const DEFAULT_STABILITY_WINDOW_MS =
  Number.parseInt(
    process.env.SPORTSOS_READINESS_STABILITY_WINDOW_MS ??
      "20000",
    10,
  );

const previousState =
  new Map<string, MonitorState>();

const pendingState =
  new Map<string, PendingState>();

let interval:
  NodeJS.Timeout | null =
    null;

function stabilityWindowMs(): number {
  return (
    Number.isFinite(
      DEFAULT_STABILITY_WINDOW_MS,
    ) &&
    DEFAULT_STABILITY_WINDOW_MS >= 0
      ? DEFAULT_STABILITY_WINDOW_MS
      : 20000
  );
}

function stateKey(
  assignment: Assignment,
): string {
  return [
    assignment.gameId,
    assignment.deviceId,
  ].join(":");
}

async function loadAssignments(
  app: FastifyInstance,
): Promise<Assignment[]> {
  const response =
    await app.inject({
      method: "GET",
      url:
        "/scoreboard-devices/assignments",
    });

  if (
    response.statusCode < 200 ||
    response.statusCode >= 300
  ) {
    return [];
  }

  try {
    const payload =
      response.json() as {
        data?: {
          assignments?: Assignment[];
        };
        assignments?: Assignment[];
      };

    return (
      payload.data?.assignments ??
      payload.assignments ??
      []
    );
  } catch {
    return [];
  }
}

export async function checkScoreboardReadinessIncidents(
  app: FastifyInstance,
): Promise<void> {
  const assignments =
    await loadAssignments(
      app,
    );

  const liveKeys =
    new Set<string>();

  const nowMs =
    Date.now();

  const requiredStableMs =
    stabilityWindowMs();

  for (
    const assignment of
    assignments
  ) {
    const key =
      stateKey(
        assignment,
      );

    liveKeys.add(
      key,
    );

    const readiness =
      await evaluateScoreboardControlReadiness(
        assignment.deviceId,
      );

    const observedState:
      MonitorState =
        readiness.ready
          ? "READY"
          : "NOT_READY";

    const committedState =
      previousState.get(
        key,
      );

    /*
     * First observation establishes baseline only.
     * This avoids generating a false outage/recovery incident at API startup.
     */
    if (!committedState) {
      previousState.set(
        key,
        observedState,
      );

      recordScoreboardReadinessObservation(
        assignment.deviceId,
        observedState,
        false,
      );

      pendingState.delete(
        key,
      );

      continue;
    }

    if (
      observedState ===
      committedState
    ) {
      recordScoreboardReadinessObservation(
        assignment.deviceId,
        observedState,
        false,
      );

      pendingState.delete(
        key,
      );

      continue;
    }

    const pending =
      pendingState.get(
        key,
      );

    if (
      !pending ||
      pending.state !==
        observedState
    ) {
      pendingState.set(
        key,
        {
          state:
            observedState,
          firstObservedAtMs:
            nowMs,
        },
      );

      continue;
    }

    const stableForMs =
      nowMs -
      pending.firstObservedAtMs;

    if (
      stableForMs <
      requiredStableMs
    ) {
      continue;
    }

    if (
      observedState ===
      "NOT_READY"
    ) {
      recordScoreboardControlAudit({
        auditId:
          `readiness-${assignment.deviceId}-${Date.now()}`,
        deviceId:
          assignment.deviceId,
        gameId:
          assignment.gameId,
        inputId:
          `readiness-monitor:${assignment.deviceId}`,
        inputType:
          "DEVICE_READINESS_DEGRADED",
        sequence:
          0,
        disposition:
          "REJECTED",
        command:
          null,
        execution:
          null,
        reconciliation:
          null,
        error:
          readiness.reason ??
          "Assigned scoreboard device is not ready.",
        createdAt:
          new Date().toISOString(),
      });
    } else {
      recordScoreboardControlAudit({
        auditId:
          `readiness-restored-${assignment.deviceId}-${Date.now()}`,
        deviceId:
          assignment.deviceId,
        gameId:
          assignment.gameId,
        inputId:
          `readiness-monitor:${assignment.deviceId}`,
        inputType:
          "DEVICE_READINESS_RESTORED",
        sequence:
          0,
        disposition:
          "ACCEPTED",
        command:
          null,
        execution:
          null,
        reconciliation:
          null,
        error:
          null,
        createdAt:
          new Date().toISOString(),
      });
    }

    previousState.set(
      key,
      observedState,
    );

    recordScoreboardReadinessObservation(
      assignment.deviceId,
      observedState,
      true,
    );

    pendingState.delete(
      key,
    );
  }

  for (
    const key of
    previousState.keys()
  ) {
    if (
      !liveKeys.has(
        key,
      )
    ) {
      previousState.delete(
        key,
      );

      pendingState.delete(
        key,
      );
    }
  }
}

export function startScoreboardReadinessIncidentMonitor(
  app: FastifyInstance,
): () => void {
  if (interval) {
    return () => {};
  }

  const monitorEveryMs =
    Number.parseInt(
      process.env.SPORTSOS_READINESS_MONITOR_INTERVAL_MS ??
        "10000",
      10,
    );

  const cadence =
    Number.isFinite(
      monitorEveryMs,
    ) &&
    monitorEveryMs >=
      5000
      ? monitorEveryMs
      : 10000;

  const run =
    () => {
      void checkScoreboardReadinessIncidents(
        app,
      ).catch(
        (error) => {
          app.log.error(
            {
              error,
            },
            "scoreboard readiness incident monitor failed",
          );
        },
      );
    };

  const initialRun =
    setTimeout(
      run,
      0,
    );

  initialRun.unref?.();

  interval =
    setInterval(
      run,
      cadence,
    );

  interval.unref?.();

  return () => {
    if (interval) {
      clearInterval(
        interval,
      );

      interval =
        null;
    }
  };
}
