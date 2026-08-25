import fs from "node:fs";
import path from "node:path";

export type BroadcastOperatorNote = {
  id: string;
  gameId: string;
  operator: string;
  note: string;
  createdAt: string;
};

type Store = {
  version: 1;
  notes: BroadcastOperatorNote[];
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
    "broadcast-operator-notes.json",
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
        parsed.notes,
      )
    ) {
      throw new Error(
        "Invalid broadcast operator notes store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      notes: [],
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

export function listBroadcastOperatorNotes(
  gameId: string,
  limit = 50,
): BroadcastOperatorNote[] {
  const safeLimit =
    Math.max(
      1,
      Math.min(
        Math.floor(
          limit,
        ),
        200,
      ),
    );

  return store.notes
    .filter(
      (note) =>
        note.gameId ===
        gameId,
    )
    .slice(
      -safeLimit,
    )
    .reverse()
    .map(
      (note) => ({
        ...note,
      }),
    );
}

export function addBroadcastOperatorNote(input: {
  gameId: string;
  operator: string;
  note: string;
}): BroadcastOperatorNote {
  const operator =
    input.operator.trim();

  const note =
    input.note.trim();

  if (!operator) {
    throw new Error(
      "Operator name is required.",
    );
  }

  if (!note) {
    throw new Error(
      "Operator note is required.",
    );
  }

  const item: BroadcastOperatorNote = {
    id:
      `broadcast-note-${input.gameId}-${Date.now()}-${Math.random()
        .toString(36)
        .slice(2, 8)}`,
    gameId:
      input.gameId,
    operator,
    note,
    createdAt:
      new Date().toISOString(),
  };

  store.notes.push(
    item,
  );

  if (
    store.notes.length >
    2500
  ) {
    store.notes =
      store.notes.slice(
        -2500,
      );
  }

  persistStore();

  return {
    ...item,
  };
}
