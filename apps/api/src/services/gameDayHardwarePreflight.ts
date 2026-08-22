import fs from "node:fs";
import path from "node:path";

import {
  getScoreboardCommissioning,
} from "./scoreboardDeviceCommissioning.js";

import {
  evaluateScoreboardControlReadiness,
} from "./scoreboardControlReadiness.js";

import {
  listScoreboardReliabilityClassifications,
} from "./scoreboardReadinessReliability.js";

import {
  latestCommissioningSelfTest,
} from "./scoreboardCommissioningSelfTest.js";

export type GameDayPreflightCheck = {
  id:
    | "COMMISSIONING"
    | "HEARTBEAT"
    | "RELIABILITY"
    | "SELF_TEST";
  passed: boolean;
  detail: string;
};

export type GameDayHardwarePreflight = {
  preflightId: string;
  gameId: string;
  deviceId: string;
  assignmentFingerprint: string;
  status:
    | "PASS"
    | "FAIL";
  checks: GameDayPreflightCheck[];
  startedAt: string;
  completedAt: string;
};

type Store = {
  version: 1;
  preflights:
    GameDayHardwarePreflight[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(
    process.cwd(),
    "data",
  );

const STORE_FILE =
  path.join(
    DATA_DIR,
    "game-day-hardware-preflights.json",
  );

const PREFLIGHT_FRESHNESS_WINDOW_MS =
  Number.parseInt(
    process.env.SPORTSOS_GAME_DAY_PREFLIGHT_FRESHNESS_MS ??
      "900000",
    10,
  );

let store =
  loadStore();

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
        parsed.preflights,
      )
    ) {
      throw new Error(
        "Invalid game-day preflight store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      preflights: [],
    };
  }
}

function persistStore(): void {
  fs.mkdirSync(
    DATA_DIR,
    {
      recursive: true,
    },
  );

  const temporary =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    temporary,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );

  fs.renameSync(
    temporary,
    STORE_FILE,
  );
}

export async function runGameDayHardwarePreflight(input: {
  gameId: string;
  deviceId: string;
}): Promise<GameDayHardwarePreflight> {
  const startedAt =
    new Date().toISOString();

  const commissioning =
    getScoreboardCommissioning(
      input.deviceId,
    );

  const readiness =
    await evaluateScoreboardControlReadiness(
      input.deviceId,
    );

  const reliability =
    listScoreboardReliabilityClassifications()
      .find(
        (item) =>
          item.deviceId ===
          input.deviceId,
      );

  const selfTest =
    latestCommissioningSelfTest(
      input.deviceId,
    );

  const checks:
    GameDayPreflightCheck[] = [
      {
        id:
          "COMMISSIONING",
        passed:
          commissioning?.status ===
          "GAME_READY",
        detail:
          commissioning?.status ===
            "GAME_READY"
            ? "Device commissioning status is GAME_READY."
            : `Commissioning status is ${commissioning?.status ?? "MISSING"}.`,
      },
      {
        id:
          "HEARTBEAT",
        passed:
          readiness.ready,
        detail:
          readiness.ready
            ? `Heartbeat age ${readiness.heartbeatAgeMs ?? 0}ms is within the ${readiness.thresholdMs}ms threshold.`
            : readiness.reason ??
              "Device heartbeat readiness failed.",
      },
      {
        id:
          "RELIABILITY",
        passed:
          Boolean(
            reliability &&
            (
              reliability.risk ===
                "HEALTHY" ||
              reliability.risk ===
                "WATCH"
            ),
          ),
        detail:
          reliability
            ? `Reliability classification is ${reliability.risk}.`
            : "Reliability classification is unavailable.",
      },
      {
        id:
          "SELF_TEST",
        passed:
          selfTest?.status ===
          "PASS",
        detail:
          selfTest?.status ===
            "PASS"
            ? `Latest ${selfTest.source} self-test passed at ${selfTest.completedAt}.`
            : selfTest
              ? `Latest ${selfTest.source} self-test status is ${selfTest.status}.`
              : "No commissioning self-test result is available.",
      },
    ];

  const completedAt =
    new Date().toISOString();

  const result:
    GameDayHardwarePreflight = {
      preflightId:
        `preflight-${input.gameId}-${input.deviceId}-${Date.now()}`,
      gameId:
        input.gameId,
      deviceId:
        input.deviceId,
      assignmentFingerprint:
        `${input.gameId}::${input.deviceId}`,
      status:
        checks.every(
          (check) =>
            check.passed,
        )
          ? "PASS"
          : "FAIL",
      checks,
      startedAt,
      completedAt,
    };

  store.preflights.push(
    result,
  );

  if (
    store.preflights.length >
    2000
  ) {
    store.preflights =
      store.preflights.slice(
        -2000,
      );
  }

  persistStore();

  return result;
}

export function latestGameDayHardwarePreflight(
  gameId: string,
  deviceId?: string,
): GameDayHardwarePreflight | null {
  return (
    [...store.preflights]
      .reverse()
      .find(
        (item) =>
          item.gameId ===
            gameId &&
          (
            !deviceId ||
            item.deviceId ===
              deviceId
          ),
      ) ??
    null
  );
}

export function listGameDayHardwarePreflights(
  gameId?: string,
): GameDayHardwarePreflight[] {
  return [...store.preflights]
    .filter(
      (item) =>
        !gameId ||
        item.gameId ===
          gameId,
    )
    .sort(
      (a, b) =>
        b.completedAt.localeCompare(
          a.completedAt,
        ),
    );
}


export type GameDayHardwarePreflightFreshness = {
  fresh: boolean;
  expiresAt: string | null;
  ageMs: number | null;
  freshnessWindowMs: number;
  reason: string | null;
};

export function gameDayHardwarePreflightFreshness(
  preflight:
    GameDayHardwarePreflight | null,
): GameDayHardwarePreflightFreshness {
  const configured =
    Number.isFinite(
      PREFLIGHT_FRESHNESS_WINDOW_MS,
    ) &&
    PREFLIGHT_FRESHNESS_WINDOW_MS > 0
      ? PREFLIGHT_FRESHNESS_WINDOW_MS
      : 900000;

  if (!preflight) {
    return {
      fresh: false,
      expiresAt: null,
      ageMs: null,
      freshnessWindowMs:
        configured,
      reason:
        "No game-day hardware preflight has been run.",
    };
  }

  const completedMs =
    Date.parse(
      preflight.completedAt,
    );

  if (
    !Number.isFinite(
      completedMs,
    )
  ) {
    return {
      fresh: false,
      expiresAt: null,
      ageMs: null,
      freshnessWindowMs:
        configured,
      reason:
        "Latest preflight timestamp is invalid.",
    };
  }

  const ageMs =
    Math.max(
      0,
      Date.now() -
        completedMs,
    );

  const expiresAt =
    new Date(
      completedMs +
        configured,
    ).toISOString();

  if (
    preflight.status !==
      "PASS"
  ) {
    return {
      fresh: false,
      expiresAt,
      ageMs,
      freshnessWindowMs:
        configured,
      reason:
        "Latest game-day hardware preflight did not pass.",
    };
  }

  return {
    fresh:
      ageMs <=
      configured,
    expiresAt,
    ageMs,
    freshnessWindowMs:
      configured,
    reason:
      ageMs <=
        configured
        ? null
        : "Latest passing game-day hardware preflight has expired.",
  };
}


export function matchesCurrentAssignment(
  preflight: GameDayHardwarePreflight | null,
  gameId: string,
  deviceId: string | null,
): boolean {
  if (
    !preflight ||
    !deviceId
  ) {
    return false;
  }

  return (
    preflight.gameId ===
      gameId &&
    preflight.deviceId ===
      deviceId &&
    preflight.assignmentFingerprint ===
      `${gameId}::${deviceId}`
  );
}
