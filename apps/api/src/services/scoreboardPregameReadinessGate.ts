import fs from "node:fs";
import path from "node:path";

import {
  listScoreboardReliabilityClassifications,
} from "./scoreboardReadinessReliability.js";

export type PregameReadinessGateDecision = {
  allowed: boolean;
  gameId: string;
  deviceId: string | null;
  risk:
    | "HEALTHY"
    | "WATCH"
    | "AT_RISK"
    | "OFFLINE"
    | "UNKNOWN";
  overrideApplied: boolean;
  reason: string | null;
};

export type PregameReadinessOverride = {
  gameId: string;
  deviceId: string;
  reason: string;
  actorUserId: string | null;
  actorRoles: string[];
  createdAt: string;
};

type Store = {
  version: 1;
  overrides: PregameReadinessOverride[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(process.cwd(), "data");

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-pregame-readiness-overrides.json",
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
        parsed.overrides,
      )
    ) {
      throw new Error(
        "Invalid pregame readiness override store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      overrides: [],
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

export function setPregameReadinessOverride(input: {
  gameId: string;
  deviceId: string;
  reason: string;
  actorUserId: string | null;
  actorRoles: string[];
}): PregameReadinessOverride {
  const record:
    PregameReadinessOverride = {
      gameId:
        input.gameId,
      deviceId:
        input.deviceId,
      reason:
        input.reason.trim(),
      actorUserId:
        input.actorUserId,
      actorRoles:
        [...input.actorRoles],
      createdAt:
        new Date().toISOString(),
    };

  store.overrides =
    store.overrides.filter(
      (item) =>
        !(
          item.gameId ===
            input.gameId &&
          item.deviceId ===
            input.deviceId
        ),
    );

  store.overrides.push(
    record,
  );

  persistStore();

  return record;
}

export function clearPregameReadinessOverride(
  gameId: string,
  deviceId: string,
): boolean {
  const before =
    store.overrides.length;

  store.overrides =
    store.overrides.filter(
      (item) =>
        !(
          item.gameId ===
            gameId &&
          item.deviceId ===
            deviceId
        ),
    );

  const changed =
    store.overrides.length !==
    before;

  if (changed) {
    persistStore();
  }

  return changed;
}

export function getPregameReadinessOverride(
  gameId: string,
  deviceId: string,
): PregameReadinessOverride | null {
  return (
    store.overrides.find(
      (item) =>
        item.gameId ===
          gameId &&
        item.deviceId ===
          deviceId,
    ) ??
    null
  );
}

export function evaluatePregameReadinessGate(input: {
  gameId: string;
  deviceId: string | null;
}): PregameReadinessGateDecision {
  if (!input.deviceId) {
    return {
      allowed: false,
      gameId:
        input.gameId,
      deviceId:
        null,
      risk:
        "UNKNOWN",
      overrideApplied:
        false,
      reason:
        "No scoreboard device is assigned to this game.",
    };
  }

  const classification =
    listScoreboardReliabilityClassifications()
      .find(
        (item) =>
          item.deviceId ===
          input.deviceId,
      );

  if (!classification) {
    return {
      allowed: false,
      gameId:
        input.gameId,
      deviceId:
        input.deviceId,
      risk:
        "UNKNOWN",
      overrideApplied:
        false,
      reason:
        "No readiness reliability history is available for the assigned scoreboard.",
    };
  }

  const override =
    getPregameReadinessOverride(
      input.gameId,
      input.deviceId,
    );

  if (
    classification.risk ===
      "HEALTHY" ||
    classification.risk ===
      "WATCH"
  ) {
    return {
      allowed: true,
      gameId:
        input.gameId,
      deviceId:
        input.deviceId,
      risk:
        classification.risk,
      overrideApplied:
        false,
      reason:
        classification.risk ===
          "WATCH"
          ? "Assigned scoreboard is in WATCH state but remains eligible for game start."
          : null,
    };
  }

  if (override) {
    return {
      allowed: true,
      gameId:
        input.gameId,
      deviceId:
        input.deviceId,
      risk:
        classification.risk,
      overrideApplied:
        true,
      reason:
        override.reason,
    };
  }

  return {
    allowed: false,
    gameId:
      input.gameId,
    deviceId:
      input.deviceId,
    risk:
      classification.risk,
    overrideApplied:
      false,
    reason:
      `Pregame scoreboard readiness gate blocked start because device risk is ${classification.risk}.`,
  };
}
