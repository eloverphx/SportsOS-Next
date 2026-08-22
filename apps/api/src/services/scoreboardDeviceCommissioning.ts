import fs from "node:fs";
import path from "node:path";

export type CommissioningStepId =
  | "FLASHED"
  | "PROVISIONED"
  | "ENROLLED"
  | "VERIFIED"
  | "ASSIGNED"
  | "CONNECTIVITY"
  | "READINESS"
  | "FIRMWARE"
  | "GAME_READY";

export type CommissioningStep = {
  id: CommissioningStepId;
  complete: boolean;
  completedAt: string | null;
  note: string | null;
};

export type ScoreboardDeviceCommissioning = {
  deviceId: string;
  createdAt: string;
  updatedAt: string;
  status:
    | "IN_PROGRESS"
    | "BLOCKED"
    | "GAME_READY";
  steps: CommissioningStep[];
};

type Store = {
  version: 1;
  devices: ScoreboardDeviceCommissioning[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(process.cwd(), "data");

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-device-commissioning.json",
  );

const STEP_ORDER: CommissioningStepId[] = [
  "FLASHED",
  "PROVISIONED",
  "ENROLLED",
  "VERIFIED",
  "ASSIGNED",
  "CONNECTIVITY",
  "READINESS",
  "FIRMWARE",
  "GAME_READY",
];

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
        parsed.devices,
      )
    ) {
      throw new Error(
        "Invalid commissioning store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      devices: [],
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

function emptySteps():
  CommissioningStep[] {
  return STEP_ORDER.map(
    (id) => ({
      id,
      complete: false,
      completedAt: null,
      note: null,
    }),
  );
}

function deriveStatus(
  record:
    ScoreboardDeviceCommissioning,
): ScoreboardDeviceCommissioning["status"] {
  const gameReady =
    record.steps.find(
      (step) =>
        step.id ===
        "GAME_READY",
    );

  if (
    gameReady?.complete
  ) {
    return "GAME_READY";
  }

  const readiness =
    record.steps.find(
      (step) =>
        step.id ===
        "READINESS",
    );

  if (
    readiness &&
    readiness.note?.startsWith(
      "BLOCKED:",
    )
  ) {
    return "BLOCKED";
  }

  return "IN_PROGRESS";
}

export function beginScoreboardCommissioning(
  deviceId: string,
): ScoreboardDeviceCommissioning {
  const normalized =
    deviceId.trim();

  if (!normalized) {
    throw new Error(
      "Device ID is required.",
    );
  }

  const existing =
    store.devices.find(
      (item) =>
        item.deviceId ===
        normalized,
    );

  if (existing) {
    return existing;
  }

  const now =
    new Date().toISOString();

  const record:
    ScoreboardDeviceCommissioning = {
      deviceId:
        normalized,
      createdAt:
        now,
      updatedAt:
        now,
      status:
        "IN_PROGRESS",
      steps:
        emptySteps(),
    };

  store.devices.push(
    record,
  );

  persistStore();

  return record;
}

export function updateScoreboardCommissioningStep(input: {
  deviceId: string;
  step: CommissioningStepId;
  complete: boolean;
  note?: string | null;
}): ScoreboardDeviceCommissioning {
  const record =
    beginScoreboardCommissioning(
      input.deviceId,
    );

  const step =
    record.steps.find(
      (item) =>
        item.id ===
        input.step,
    );

  if (!step) {
    throw new Error(
      "Unknown commissioning step.",
    );
  }

  if (
    input.step ===
      "GAME_READY" &&
    input.complete
  ) {
    const prerequisites =
      record.steps.filter(
        (item) =>
          item.id !==
          "GAME_READY",
      );

    if (
      prerequisites.some(
        (item) =>
          !item.complete,
      )
    ) {
      throw new Error(
        "All commissioning prerequisites must pass before GAME_READY.",
      );
    }
  }

  step.complete =
    input.complete;

  step.completedAt =
    input.complete
      ? new Date().toISOString()
      : null;

  step.note =
    input.note?.trim() ||
    null;

  record.updatedAt =
    new Date().toISOString();

  record.status =
    deriveStatus(
      record,
    );

  persistStore();

  return record;
}

export function getScoreboardCommissioning(
  deviceId: string,
): ScoreboardDeviceCommissioning | null {
  return (
    store.devices.find(
      (item) =>
        item.deviceId ===
        deviceId,
    ) ??
    null
  );
}

export function listScoreboardCommissioning():
  ScoreboardDeviceCommissioning[] {
  return [...store.devices]
    .sort(
      (a, b) =>
        b.updatedAt.localeCompare(
          a.updatedAt,
        ),
    );
}
