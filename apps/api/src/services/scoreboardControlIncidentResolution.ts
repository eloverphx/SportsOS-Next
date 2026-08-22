import fs from "node:fs";
import path from "node:path";

export type ScoreboardControlIncidentStatus =
  | "OPEN"
  | "ACKNOWLEDGED"
  | "RESOLVED";

export type ScoreboardControlIncidentResolution = {
  auditId: string;
  status: ScoreboardControlIncidentStatus;
  note: string | null;
  actorUserId: string | null;
  actorRoles: string[];
  updatedAt: string;
};

type Store = {
  version: 1;
  resolutions: ScoreboardControlIncidentResolution[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(process.cwd(), "data");

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-control-incident-resolution.json",
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
        parsed.resolutions,
      )
    ) {
      throw new Error(
        "Invalid scoreboard control incident resolution store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      resolutions: [],
    };
  }
}

function persistStore(): void {
  fs.mkdirSync(
    DATA_DIR,
    { recursive: true },
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

export function getScoreboardControlIncidentResolution(
  auditId: string,
): ScoreboardControlIncidentResolution | null {
  return (
    store.resolutions.find(
      (item) =>
        item.auditId === auditId,
    ) ?? null
  );
}

export function setScoreboardControlIncidentResolution(input: {
  auditId: string;
  status: ScoreboardControlIncidentStatus;
  note?: string | null;
  actorUserId: string | null;
  actorRoles: string[];
}): ScoreboardControlIncidentResolution {
  const resolution: ScoreboardControlIncidentResolution = {
    auditId: input.auditId,
    status: input.status,
    note:
      input.note?.trim() ||
      null,
    actorUserId:
      input.actorUserId,
    actorRoles:
      [...input.actorRoles],
    updatedAt:
      new Date().toISOString(),
  };

  store.resolutions =
    store.resolutions.filter(
      (item) =>
        item.auditId !==
        input.auditId,
    );

  store.resolutions.push(
    resolution,
  );

  persistStore();

  return resolution;
}

export function listScoreboardControlIncidentResolutions():
  ScoreboardControlIncidentResolution[] {
  return [...store.resolutions]
    .sort(
      (a, b) =>
        b.updatedAt.localeCompare(
          a.updatedAt,
        ),
    );
}
