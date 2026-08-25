#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-24.5-restart-crash-persistence-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/broadcastRecoverySnapshotStore.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/broadcast-recovery-snapshot-store-24.5.test.ts"
DOC="docs/BROADCAST-RESILIENCE.md"

for required in \
  ".git" \
  "apps/api/src/services/broadcastResilienceSupervisor.ts" \
  "$ROUTE" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$ROUTE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
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
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const importLine=`import {
  getBroadcastRecoverySnapshot,
  listBroadcastRecoverySnapshots,
  saveBroadcastRecoverySnapshot,
} from "../services/broadcastRecoverySnapshotStore.js";`;

if(!s.includes("saveBroadcastRecoverySnapshot")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/:gameId/recovery-snapshot"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/:gameId/resilience-supervisor",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("24.3 resilience supervisor route missing.");

  const routes=`  app.get(
    "/broadcast-coordinator/recovery-snapshots",
    async () => {
      return {
        success: true,
        data: {
          snapshots:
            listBroadcastRecoverySnapshots(),
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId/recovery-snapshot",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data: {
          snapshot:
            getBroadcastRecoverySnapshot(
              gameId,
            ),
        },
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/recovery-snapshot/capture",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const snapshot =
        getBroadcastCoordinatorSnapshot(
          gameId,
        );

      const lastActivityAt =
        snapshot.runtime.telemetry.lastProgressAt ??
        null;

      const stateAgeMs =
        lastActivityAt
          ? Math.max(
              0,
              Date.now() -
                Date.parse(
                  lastActivityAt,
                ),
            )
          : 0;

      const decision =
        evaluateBroadcastResilienceSupervisor({
          coordinatorIntent:
            snapshot.coordinator.intent,
          runtimeStatus:
            snapshot.runtime.session.status,
          lastActivityAt,
          stateAgeMs,
        });

      const captured =
        saveBroadcastRecoverySnapshot({
          gameId,
          capturedAt:
            new Date().toISOString(),
          coordinatorIntent:
            snapshot.coordinator.intent,
          runtimeStatus:
            snapshot.runtime.session.status,
          lastActivityAt,
          recoveryAction:
            decision.recovery.action,
          heartbeatState:
            decision.heartbeat.state,
        });

      return {
        success: true,
        data: {
          snapshot:
            captured,
        },
      };
    },
  );

`;

  s=s.slice(0,i)+routes+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 24.5 — Restart / crash recovery persistence

SportsOS now persists a compact recovery snapshot for each broadcast.

Store:

```text
broadcast-recovery-snapshots.json
```

Each snapshot contains:

```text
gameId
capturedAt
coordinatorIntent
runtimeStatus
lastActivityAt
recoveryAction
heartbeatState
```

APIs:

```text
GET  /broadcast-coordinator/recovery-snapshots
GET  /broadcast-coordinator/:gameId/recovery-snapshot
POST /broadcast-coordinator/:gameId/recovery-snapshot/capture
```

The snapshot store is bounded to 500 broadcasts.

This persistence is diagnostic and recovery-context only. Loading a saved recovery snapshot does not automatically start, stop, reconcile, or mutate a broadcast.

Milestone 24.5 establishes the state needed to recognize crash/restart mismatches in later supervisor work.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 24.5 restart / crash recovery persistence", () => {
  const service=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastRecoverySnapshotStore.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("persists recovery snapshots in shared data storage",()=> {
    expect(service).toContain("SPORTSOS_DATA_DIR");
    expect(service).toContain("broadcast-recovery-snapshots.json");
    expect(service).toContain("500");
  });

  it("stores coordinator/runtime/recovery context",()=> {
    expect(service).toContain("coordinatorIntent");
    expect(service).toContain("runtimeStatus");
    expect(service).toContain("recoveryAction");
    expect(service).toContain("heartbeatState");
  });

  it("provides capture and read APIs",()=> {
    expect(route).toContain('"/broadcast-coordinator/recovery-snapshots"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/recovery-snapshot"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/recovery-snapshot/capture"');
  });

  it("uses current resilience decision when capturing",()=> {
    expect(route).toContain("evaluateBroadcastResilienceSupervisor");
    expect(route).toContain("saveBroadcastRecoverySnapshot");
  });

  it("does not directly control encoder runtime",()=> {
    expect(service).not.toContain("startEncoderRuntime");
    expect(service).not.toContain("stopEncoderRuntime");
    expect(route).not.toContain("startEncoderRuntime(");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 24.5 installed"
echo "============================================================"
echo "Added:"
echo "  - persistent recovery snapshot store"
echo "  - per-broadcast recovery context"
echo "  - bounded 500-snapshot retention"
echo "  - capture/read/list APIs"
echo "  - no automatic recovery execution"
echo "  - Milestone 24.5 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  docker compose ps"
echo "  curl -fsS http://127.0.0.1:4001/health"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 24.6 - Stream Destination Failure Handling"
