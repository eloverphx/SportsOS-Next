import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export type FirmwareRolloutState =
  | "DRAFT"
  | "ACTIVE"
  | "PAUSED"
  | "COMPLETED"
  | "CANCELLED";

export type FirmwareRollout = {
  rolloutId: string;
  releaseId: string;
  state: FirmwareRolloutState;
  targetDeviceIds: string[];
  createdAt: string;
  updatedAt: string;
};

type RolloutStore = {
  version: 1;
  rollouts: FirmwareRollout[];
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
    "scoreboard-firmware-rollouts.json",
  );

let store =
  loadStore();

function loadStore(): RolloutStore {
  try {
    const parsed =
      JSON.parse(
        fs.readFileSync(
          STORE_FILE,
          "utf8",
        ),
      ) as RolloutStore;

    if (
      parsed.version !== 1 ||
      !Array.isArray(
        parsed.rollouts,
      )
    ) {
      throw new Error(
        "Invalid firmware rollout store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      rollouts: [],
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

export function createFirmwareRollout(input: {
  releaseId: string;
  targetDeviceIds: string[];
}): FirmwareRollout {
  const now =
    new Date().toISOString();

  const rollout: FirmwareRollout = {
    rolloutId:
      crypto.randomUUID(),
    releaseId:
      input.releaseId,
    state:
      "DRAFT",
    targetDeviceIds:
      [...new Set(
        input.targetDeviceIds,
      )],
    createdAt:
      now,
    updatedAt:
      now,
  };

  store.rollouts.push(
    rollout,
  );

  persistStore();

  return rollout;
}

export function listFirmwareRollouts(): FirmwareRollout[] {
  return [...store.rollouts]
    .sort(
      (a, b) =>
        b.updatedAt.localeCompare(
          a.updatedAt,
        ),
    );
}

export function getFirmwareRollout(
  rolloutId: string,
): FirmwareRollout | null {
  return (
    store.rollouts.find(
      (rollout) =>
        rollout.rolloutId ===
        rolloutId,
    ) ?? null
  );
}

export function updateFirmwareRolloutState(
  rolloutId: string,
  nextState: FirmwareRolloutState,
): FirmwareRollout | null {
  const rollout =
    getFirmwareRollout(
      rolloutId,
    );

  if (!rollout) {
    return null;
  }

  rollout.state =
    nextState;

  rollout.updatedAt =
    new Date().toISOString();

  persistStore();

  return rollout;
}

export function findActiveRolloutForDevice(
  deviceId: string,
): FirmwareRollout | null {
  return (
    store.rollouts.find(
      (rollout) =>
        rollout.state ===
          "ACTIVE" &&
        rollout.targetDeviceIds.includes(
          deviceId,
        ),
    ) ?? null
  );
}
