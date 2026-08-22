import fs from "node:fs";
import path from "node:path";

export type ScoreboardReadinessMetric = {
  deviceId: string;
  readyTransitions: number;
  degradedTransitions: number;
  currentState:
    | "READY"
    | "NOT_READY";
  firstObservedAt: string;
  lastChangedAt: string;
  lastObservedAt: string;
  readyMs: number;
  notReadyMs: number;
};

type Store = {
  version: 1;
  metrics:
    ScoreboardReadinessMetric[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(process.cwd(), "data");

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-readiness-metrics.json",
  );

let store = loadStore();

function loadStore(): Store {
  try {
    const parsed =
      JSON.parse(
        fs.readFileSync(
          STORE_FILE,
          "utf8",
        ),
      ) as Store;

    if (
      parsed.version !== 1 ||
      !Array.isArray(
        parsed.metrics,
      )
    ) {
      throw new Error(
        "Invalid readiness metrics store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      metrics: [],
    };
  }
}

function persistStore(): void {
  fs.mkdirSync(
    DATA_DIR,
    { recursive: true },
  );

  const temp =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    temp,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );

  fs.renameSync(
    temp,
    STORE_FILE,
  );
}

function nowIso(): string {
  return new Date().toISOString();
}

export function recordScoreboardReadinessObservation(
  deviceId: string,
  state:
    | "READY"
    | "NOT_READY",
  transitioned: boolean,
): ScoreboardReadinessMetric {
  const now =
    Date.now();

  const nowText =
    new Date(
      now,
    ).toISOString();

  const existing =
    store.metrics.find(
      (item) =>
        item.deviceId ===
        deviceId,
    );

  if (!existing) {
    const created:
      ScoreboardReadinessMetric = {
        deviceId,
        readyTransitions:
          state ===
            "READY"
            ? 1
            : 0,
        degradedTransitions:
          state ===
            "NOT_READY"
            ? 1
            : 0,
        currentState:
          state,
        firstObservedAt:
          nowText,
        lastChangedAt:
          nowText,
        lastObservedAt:
          nowText,
        readyMs:
          0,
        notReadyMs:
          0,
      };

    store.metrics.push(
      created,
    );

    persistStore();

    return created;
  }

  const lastObservedMs =
    Date.parse(
      existing.lastObservedAt,
    );

  const delta =
    Number.isFinite(
      lastObservedMs,
    )
      ? Math.max(
          0,
          now -
            lastObservedMs,
        )
      : 0;

  if (
    existing.currentState ===
      "READY"
  ) {
    existing.readyMs +=
      delta;
  } else {
    existing.notReadyMs +=
      delta;
  }

  existing.lastObservedAt =
    nowText;

  if (
    transitioned &&
    existing.currentState !==
      state
  ) {
    existing.currentState =
      state;

    existing.lastChangedAt =
      nowText;

    if (
      state ===
      "READY"
    ) {
      existing.readyTransitions +=
        1;
    } else {
      existing.degradedTransitions +=
        1;
    }
  }

  persistStore();

  return {
    ...existing,
  };
}

export function listScoreboardReadinessMetrics():
  ScoreboardReadinessMetric[] {
  return [...store.metrics]
    .sort(
      (a, b) =>
        a.deviceId.localeCompare(
          b.deviceId,
        ),
    );
}

export function readinessAvailabilityPercent(
  metric:
    ScoreboardReadinessMetric,
): number {
  const total =
    metric.readyMs +
    metric.notReadyMs;

  if (total <= 0) {
    return metric.currentState ===
      "READY"
      ? 100
      : 0;
  }

  return Math.round(
    (
      metric.readyMs /
      total
    ) *
      10000,
  ) /
    100;
}
