import fs from "node:fs";
import path from "node:path";

export type BroadcastRecoverySnapshot = {
  gameId: string;
  capturedAt: string;
  coordinatorIntent: string;
  runtimeStatus: string;
  lastActivityAt: string | null;
  recoveryAction: string;
  heartbeatState: string;
};

type Store = {
  version: 1;
  snapshots: BroadcastRecoverySnapshot[];
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
    "broadcast-recovery-snapshots.json",
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
        parsed.snapshots,
      )
    ) {
      throw new Error(
        "Invalid broadcast recovery snapshot store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      snapshots: [],
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

  const tempFile =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    tempFile,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );

  fs.renameSync(
    tempFile,
    STORE_FILE,
  );
}

export function saveBroadcastRecoverySnapshot(
  snapshot: BroadcastRecoverySnapshot,
): BroadcastRecoverySnapshot {
  store.snapshots =
    store.snapshots.filter(
      (item) =>
        item.gameId !==
        snapshot.gameId,
    );

  store.snapshots.push({
    ...snapshot,
  });

  if (
    store.snapshots.length >
    500
  ) {
    store.snapshots =
      store.snapshots.slice(
        -500,
      );
  }

  persistStore();

  return {
    ...snapshot,
  };
}

export function getBroadcastRecoverySnapshot(
  gameId: string,
): BroadcastRecoverySnapshot | null {
  const item =
    [...store.snapshots]
      .reverse()
      .find(
        (snapshot) =>
          snapshot.gameId ===
          gameId,
      );

  return item
    ? {
        ...item,
      }
    : null;
}

export function listBroadcastRecoverySnapshots(): BroadcastRecoverySnapshot[] {
  return store.snapshots
    .slice()
    .sort(
      (a, b) =>
        Date.parse(
          b.capturedAt,
        ) -
        Date.parse(
          a.capturedAt,
        ),
    )
    .map(
      (snapshot) => ({
        ...snapshot,
      }),
    );
}
