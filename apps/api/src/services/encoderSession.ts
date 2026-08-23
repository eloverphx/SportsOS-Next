import fs from "node:fs";
import path from "node:path";

export type EncoderSessionStatus =
  | "STOPPED"
  | "STARTING"
  | "LIVE"
  | "STOPPING"
  | "ERROR";

export type EncoderSession = {
  gameId: string;
  status: EncoderSessionStatus;
  startedAt: string | null;
  stoppedAt: string | null;
  lastTransitionAt: string;
  lastError: string | null;
};

type Store = {
  version: 1;
  sessions:
    EncoderSession[];
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
    "encoder-sessions.json",
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
        parsed.sessions,
      )
    ) {
      throw new Error(
        "Invalid encoder-session store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      sessions: [],
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

function replaceSession(
  session: EncoderSession,
): EncoderSession {
  store.sessions =
    store.sessions.filter(
      (item) =>
        item.gameId !==
        session.gameId,
    );

  store.sessions.push(
    session,
  );

  persistStore();

  return {
    ...session,
  };
}

export function getEncoderSession(
  gameId: string,
): EncoderSession {
  const existing =
    store.sessions.find(
      (item) =>
        item.gameId ===
        gameId,
    );

  if (existing) {
    return {
      ...existing,
    };
  }

  const now =
    new Date().toISOString();

  return {
    gameId,
    status:
      "STOPPED",
    startedAt:
      null,
    stoppedAt:
      now,
    lastTransitionAt:
      now,
    lastError:
      null,
  };
}

export function beginEncoderStart(
  gameId: string,
): EncoderSession {
  const current =
    getEncoderSession(
      gameId,
    );

  if (
    current.status ===
      "LIVE" ||
    current.status ===
      "STARTING"
  ) {
    return current;
  }

  const now =
    new Date().toISOString();

  return replaceSession({
    ...current,
    status:
      "STARTING",
    startedAt:
      null,
    stoppedAt:
      current.stoppedAt,
    lastTransitionAt:
      now,
    lastError:
      null,
  });
}

export function markEncoderLive(
  gameId: string,
): EncoderSession {
  const current =
    getEncoderSession(
      gameId,
    );

  const now =
    new Date().toISOString();

  return replaceSession({
    ...current,
    status:
      "LIVE",
    startedAt:
      current.startedAt ??
      now,
    stoppedAt:
      null,
    lastTransitionAt:
      now,
    lastError:
      null,
  });
}

export function beginEncoderStop(
  gameId: string,
): EncoderSession {
  const current =
    getEncoderSession(
      gameId,
    );

  if (
    current.status ===
      "STOPPED" ||
    current.status ===
      "STOPPING"
  ) {
    return current;
  }

  return replaceSession({
    ...current,
    status:
      "STOPPING",
    lastTransitionAt:
      new Date().toISOString(),
    lastError:
      null,
  });
}

export function markEncoderStopped(
  gameId: string,
): EncoderSession {
  const current =
    getEncoderSession(
      gameId,
    );

  const now =
    new Date().toISOString();

  return replaceSession({
    ...current,
    status:
      "STOPPED",
    stoppedAt:
      now,
    lastTransitionAt:
      now,
    lastError:
      null,
  });
}

export function markEncoderError(
  gameId: string,
  message: string,
): EncoderSession {
  const current =
    getEncoderSession(
      gameId,
    );

  return replaceSession({
    ...current,
    status:
      "ERROR",
    lastTransitionAt:
      new Date().toISOString(),
    lastError:
      message.trim() ||
      "Encoder session error.",
  });
}
