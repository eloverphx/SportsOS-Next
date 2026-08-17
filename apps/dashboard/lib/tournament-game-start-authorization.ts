export const SPORTSOS_GAME_START_AUTH_STORAGE_PREFIX =
  "sportsos:tournament-game-operations:start-authorization";

export type GameStartAuthorizationMode =
  | "normal"
  | "testing-override";

export type GameStartAuthorizationRecord = {
  gameId: string;
  authorizedAt: string;
  authorizedBy: string;
  mode: GameStartAuthorizationMode;
  actualReadyAtAuthorization: boolean;
  effectiveReadyAtAuthorization: boolean;
  overrideReason: string | null;
};

export type GameStartAuthorizationInput = {
  gameId: string;
  authorizedBy: string;
  actualReady: boolean;
  effectiveReady: boolean;
  testingOverrideEnabled: boolean;
  overrideReason?: string;
  now?: Date;
};

function storageKey(gameId: string): string {
  return `${SPORTSOS_GAME_START_AUTH_STORAGE_PREFIX}:${gameId}`;
}

export function normalizeAuthorizationText(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}

export function canAuthorizeGameStart(
  input: Omit<GameStartAuthorizationInput, "gameId" | "now">,
): boolean {
  const authorizedBy = normalizeAuthorizationText(input.authorizedBy);

  if (!authorizedBy || !input.effectiveReady) {
    return false;
  }

  if (input.actualReady) {
    return true;
  }

  return (
    input.testingOverrideEnabled &&
    normalizeAuthorizationText(input.overrideReason ?? "").length >= 5
  );
}

export function createGameStartAuthorization(
  input: GameStartAuthorizationInput,
): GameStartAuthorizationRecord {
  if (!canAuthorizeGameStart(input)) {
    throw new Error("Game start authorization requirements are not satisfied.");
  }

  const mode: GameStartAuthorizationMode =
    input.actualReady ? "normal" : "testing-override";

  return {
    gameId: input.gameId,
    authorizedAt: (input.now ?? new Date()).toISOString(),
    authorizedBy: normalizeAuthorizationText(input.authorizedBy),
    mode,
    actualReadyAtAuthorization: input.actualReady,
    effectiveReadyAtAuthorization: input.effectiveReady,
    overrideReason:
      mode === "testing-override"
        ? normalizeAuthorizationText(input.overrideReason ?? "")
        : null,
  };
}

export function writeGameStartAuthorization(
  storage: Pick<Storage, "setItem">,
  record: GameStartAuthorizationRecord,
): void {
  storage.setItem(storageKey(record.gameId), JSON.stringify(record));
}

export function readGameStartAuthorization(
  storage: Pick<Storage, "getItem">,
  gameId: string,
): GameStartAuthorizationRecord | null {
  const raw = storage.getItem(storageKey(gameId));

  if (!raw) {
    return null;
  }

  try {
    const parsed = JSON.parse(raw) as Partial<GameStartAuthorizationRecord>;

    if (
      parsed.gameId !== gameId ||
      typeof parsed.authorizedAt !== "string" ||
      typeof parsed.authorizedBy !== "string" ||
      (parsed.mode !== "normal" &&
        parsed.mode !== "testing-override") ||
      typeof parsed.actualReadyAtAuthorization !== "boolean" ||
      typeof parsed.effectiveReadyAtAuthorization !== "boolean"
    ) {
      return null;
    }

    return {
      gameId,
      authorizedAt: parsed.authorizedAt,
      authorizedBy: normalizeAuthorizationText(parsed.authorizedBy),
      mode: parsed.mode,
      actualReadyAtAuthorization:
        parsed.actualReadyAtAuthorization,
      effectiveReadyAtAuthorization:
        parsed.effectiveReadyAtAuthorization,
      overrideReason:
        parsed.mode === "testing-override"
          ? normalizeAuthorizationText(parsed.overrideReason ?? "")
          : null,
    };
  } catch {
    return null;
  }
}

export function clearGameStartAuthorization(
  storage: Pick<Storage, "removeItem">,
  gameId: string,
): void {
  storage.removeItem(storageKey(gameId));
}
