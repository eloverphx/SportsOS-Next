import fs from "node:fs";
import path from "node:path";

export type GameStartPreflightOverride = {
  overrideId: string;
  gameId: string;
  deviceId: string;
  reason: string;
  actorUserId: string | null;
  actorRoles: string[];
  createdAt: string;
  expiresAt: string;
  revokedAt: string | null;
};

type Store = {
  version: 1;
  overrides:
    GameStartPreflightOverride[];
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
    "game-start-preflight-overrides.json",
  );

const DEFAULT_OVERRIDE_TTL_MS =
  Number.parseInt(
    process.env.SPORTSOS_GAME_START_OVERRIDE_TTL_MS ??
      "600000",
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
        parsed.overrides,
      )
    ) {
      throw new Error(
        "Invalid game-start override store.",
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

function configuredTtlMs(): number {
  return (
    Number.isFinite(
      DEFAULT_OVERRIDE_TTL_MS,
    ) &&
    DEFAULT_OVERRIDE_TTL_MS > 0
      ? DEFAULT_OVERRIDE_TTL_MS
      : 600000
  );
}

export function createGameStartPreflightOverride(input: {
  gameId: string;
  deviceId: string;
  reason: string;
  actorUserId: string | null;
  actorRoles: string[];
}): GameStartPreflightOverride {
  const reason =
    input.reason.trim();

  if (!reason) {
    throw new Error(
      "Emergency override reason is required.",
    );
  }

  const now =
    Date.now();

  const override:
    GameStartPreflightOverride = {
      overrideId:
        `preflight-override-${input.gameId}-${input.deviceId}-${now}`,
      gameId:
        input.gameId,
      deviceId:
        input.deviceId,
      reason,
      actorUserId:
        input.actorUserId,
      actorRoles:
        [...input.actorRoles],
      createdAt:
        new Date(
          now,
        ).toISOString(),
      expiresAt:
        new Date(
          now +
            configuredTtlMs(),
        ).toISOString(),
      revokedAt:
        null,
    };

  store.overrides.push(
    override,
  );

  persistStore();

  return {
    ...override,
    actorRoles:
      [...override.actorRoles],
  };
}

export function getActiveGameStartPreflightOverride(
  gameId: string,
  deviceId: string,
): GameStartPreflightOverride | null {
  const now =
    Date.now();

  const active =
    [...store.overrides]
      .reverse()
      .find(
        (item) =>
          item.gameId ===
            gameId &&
          item.deviceId ===
            deviceId &&
          item.revokedAt ===
            null &&
          Date.parse(
            item.expiresAt,
          ) >
            now,
      );

  return active
    ? {
        ...active,
        actorRoles:
          [...active.actorRoles],
      }
    : null;
}

export function revokeGameStartPreflightOverride(
  overrideId: string,
): boolean {
  const override =
    store.overrides.find(
      (item) =>
        item.overrideId ===
        overrideId,
    );

  if (
    !override ||
    override.revokedAt
  ) {
    return false;
  }

  override.revokedAt =
    new Date().toISOString();

  persistStore();

  return true;
}

export function listGameStartPreflightOverrides(
  gameId?: string,
): GameStartPreflightOverride[] {
  return [...store.overrides]
    .filter(
      (item) =>
        !gameId ||
        item.gameId ===
          gameId,
    )
    .sort(
      (a, b) =>
        b.createdAt.localeCompare(
          a.createdAt,
        ),
    )
    .map(
      (item) => ({
        ...item,
        actorRoles:
          [...item.actorRoles],
      }),
    );
}
