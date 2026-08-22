import fs from "node:fs";
import path from "node:path";

export type EmergencyPhysicalControlLock = {
  active: boolean;
  reason: string | null;
  actorUserId: string | null;
  actorRoles: string[];
  changedAt: string | null;
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(process.cwd(), "data");

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-emergency-control-lock.json",
  );

const DEFAULT_STATE: EmergencyPhysicalControlLock = {
  active: false,
  reason: null,
  actorUserId: null,
  actorRoles: [],
  changedAt: null,
};

let state = load();

function load(): EmergencyPhysicalControlLock {
  try {
    const parsed =
      JSON.parse(
        fs.readFileSync(STORE_FILE, "utf8"),
      ) as EmergencyPhysicalControlLock;

    if (typeof parsed.active !== "boolean") {
      throw new Error("Invalid emergency lock store.");
    }

    return {
      active: parsed.active,
      reason:
        typeof parsed.reason === "string"
          ? parsed.reason
          : null,
      actorUserId:
        typeof parsed.actorUserId === "string"
          ? parsed.actorUserId
          : null,
      actorRoles:
        Array.isArray(parsed.actorRoles)
          ? parsed.actorRoles.filter(
              (role): role is string =>
                typeof role === "string",
            )
          : [],
      changedAt:
        typeof parsed.changedAt === "string"
          ? parsed.changedAt
          : null,
    };
  } catch {
    return { ...DEFAULT_STATE };
  }
}

function persist(): void {
  fs.mkdirSync(DATA_DIR, { recursive: true });

  const temporary =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    temporary,
    JSON.stringify(state, null, 2),
    "utf8",
  );

  fs.renameSync(
    temporary,
    STORE_FILE,
  );
}

export function getEmergencyPhysicalControlLock():
  EmergencyPhysicalControlLock {
  return {
    ...state,
    actorRoles: [...state.actorRoles],
  };
}

export function setEmergencyPhysicalControlLock(input: {
  active: boolean;
  reason?: string | null;
  actorUserId: string | null;
  actorRoles: string[];
}): EmergencyPhysicalControlLock {
  state = {
    active: input.active,
    reason:
      input.reason?.trim() ||
      null,
    actorUserId: input.actorUserId,
    actorRoles: [...input.actorRoles],
    changedAt: new Date().toISOString(),
  };

  persist();

  return getEmergencyPhysicalControlLock();
}
