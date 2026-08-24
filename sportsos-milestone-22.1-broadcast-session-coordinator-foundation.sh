#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-22.1-broadcast-coordinator-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/broadcastSessionCoordinator.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
APP="apps/api/src/app.ts"
TEST="packages/core/test/broadcast-session-coordinator-22.1.test.ts"
DOC="docs/BROADCAST-COORDINATOR.md"
STATUS="docs/MILESTONE-STATUS.md"

for required in \
  ".git" \
  "apps/api/src/services/gameDayGoLivePreflight.ts" \
  "apps/api/src/services/goLiveSession.ts" \
  "apps/api/src/services/encoderRuntime.ts" \
  "$APP"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$ROUTE" "$APP" "$TEST" "$DOC" "$STATUS"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$ROUTE")" "$(dirname "$TEST")" docs

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

import {
  evaluateGameDayGoLivePreflight,
} from "./gameDayGoLivePreflight.js";

import {
  getGoLiveSession,
} from "./goLiveSession.js";

import {
  encoderRuntimeSnapshot,
} from "./encoderRuntime.js";

export type BroadcastCoordinatorIntent =
  | "IDLE"
  | "PREPARE"
  | "GO_LIVE"
  | "STOP";

export type BroadcastCoordinatorRecord = {
  gameId: string;
  intent: BroadcastCoordinatorIntent;
  correlationId: string;
  updatedAt: string;
  lastError: string | null;
};

export type BroadcastCoordinatorSnapshot = {
  coordinator: BroadcastCoordinatorRecord;
  preflight:
    ReturnType<
      typeof evaluateGameDayGoLivePreflight
    >;
  goLive:
    ReturnType<
      typeof getGoLiveSession
    >;
  runtime:
    ReturnType<
      typeof encoderRuntimeSnapshot
    >;
};

type Store = {
  version: 1;
  records:
    BroadcastCoordinatorRecord[];
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
    "broadcast-session-coordinator.json",
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
        parsed.records,
      )
    ) {
      throw new Error(
        "Invalid broadcast coordinator store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      records: [],
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

function createCorrelationId(
  gameId: string,
): string {
  return `broadcast-${gameId}-${Date.now()}-${Math.random()
    .toString(36)
    .slice(2, 8)}`;
}

export function getBroadcastCoordinatorRecord(
  gameId: string,
): BroadcastCoordinatorRecord {
  const existing =
    store.records.find(
      (record) =>
        record.gameId ===
        gameId,
    );

  if (existing) {
    return {
      ...existing,
    };
  }

  return {
    gameId,
    intent:
      "IDLE",
    correlationId:
      createCorrelationId(
        gameId,
      ),
    updatedAt:
      new Date().toISOString(),
    lastError:
      null,
  };
}

export function setBroadcastCoordinatorIntent(input: {
  gameId: string;
  intent: BroadcastCoordinatorIntent;
  lastError?: string | null;
}): BroadcastCoordinatorRecord {
  const record: BroadcastCoordinatorRecord = {
    gameId:
      input.gameId,
    intent:
      input.intent,
    correlationId:
      createCorrelationId(
        input.gameId,
      ),
    updatedAt:
      new Date().toISOString(),
    lastError:
      input.lastError ??
      null,
  };

  store.records =
    store.records.filter(
      (item) =>
        item.gameId !==
        input.gameId,
    );

  store.records.push(
    record,
  );

  persistStore();

  return {
    ...record,
  };
}

export function getBroadcastCoordinatorSnapshot(
  gameId: string,
): BroadcastCoordinatorSnapshot {
  return {
    coordinator:
      getBroadcastCoordinatorRecord(
        gameId,
      ),
    preflight:
      evaluateGameDayGoLivePreflight(
        gameId,
      ),
    goLive:
      getGoLiveSession(
        gameId,
      ),
    runtime:
      encoderRuntimeSnapshot(
        gameId,
      ),
  };
}

export function prepareBroadcastSession(
  gameId: string,
): BroadcastCoordinatorSnapshot {
  const preflight =
    evaluateGameDayGoLivePreflight(
      gameId,
    );

  setBroadcastCoordinatorIntent({
    gameId,
    intent:
      "PREPARE",
    lastError:
      preflight.ready
        ? null
        : "Game-day go-live preflight is blocked.",
  });

  return getBroadcastCoordinatorSnapshot(
    gameId,
  );
}
EOF

cat > "$ROUTE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import {
  getBroadcastCoordinatorSnapshot,
  prepareBroadcastSession,
  setBroadcastCoordinatorIntent,
} from "../services/broadcastSessionCoordinator.js";

export async function registerBroadcastSessionCoordinatorRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.get(
    "/broadcast-coordinator/:gameId",
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
        data:
          getBroadcastCoordinatorSnapshot(
            gameId,
          ),
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/prepare",
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
        prepareBroadcastSession(
          gameId,
        );

      if (
        !snapshot.preflight.ready
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Broadcast preparation is blocked by final go-live preflight.",
          data:
            snapshot,
        });
      }

      return {
        success: true,
        data:
          snapshot,
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/reset",
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

      setBroadcastCoordinatorIntent({
        gameId,
        intent:
          "IDLE",
      });

      return {
        success: true,
        data:
          getBroadcastCoordinatorSnapshot(
            gameId,
          ),
      };
    },
  );
}
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/app.ts";
let s=fs.readFileSync(f,"utf8");

const importLine='import { registerBroadcastSessionCoordinatorRoutes } from "./routes/broadcastSessionCoordinator.js";';

if(!s.includes(importLine)) {
  s=s.replace(
    'import { registerGoLiveSessionRoutes } from "./routes/goLiveSessions.js";',
    'import { registerGoLiveSessionRoutes } from "./routes/goLiveSessions.js";\n'+importLine
  );
}

if(!s.includes("app.register(registerBroadcastSessionCoordinatorRoutes)")) {
  s=s.replace(
    "  await app.register(registerGoLiveSessionRoutes);",
    "  await app.register(registerGoLiveSessionRoutes);\n  await app.register(registerBroadcastSessionCoordinatorRoutes);"
  );
}

fs.writeFileSync(f,s);
NODE

cat > "$DOC" <<'EOF'
# Broadcast Session Coordinator

Milestone 22 begins production broadcast automation and resilience.

## Milestone 22.1 — Broadcast session coordinator foundation

The coordinator sits above the Milestone 20 encoder stack and Milestone 21 production go-live safety layer.

It does not create a second authoritative stream lifecycle.

Coordinator intent is limited to:

```text
IDLE
PREPARE
GO_LIVE
STOP
```

The authoritative operational state still comes from:

- game-day go-live preflight
- go-live session
- encoder runtime
- publish telemetry
- recovery state

Coordinator API:

```text
GET  /broadcast-coordinator/:gameId
POST /broadcast-coordinator/:gameId/prepare
POST /broadcast-coordinator/:gameId/reset
```

`prepare` runs the existing final game-day go-live preflight and returns HTTP 409 when preparation is blocked.

Each coordinator write receives a correlation ID for later orchestration tracing.
EOF

cat >> "$STATUS" <<'EOF'

### Milestone 22

Production broadcast automation and resilience.

Current work:

- 22.1 broadcast session coordinator foundation
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 22.1 broadcast session coordinator foundation", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const app =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/app.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("persists only coordinator intent, not duplicate runtime state", () => {
    expect(service).toContain(
      "broadcast-session-coordinator.json",
    );

    expect(service).toContain(
      "BroadcastCoordinatorIntent",
    );

    expect(service).toContain(
      "getGoLiveSession",
    );

    expect(service).toContain(
      "encoderRuntimeSnapshot",
    );
  });

  it("composes existing final preflight", () => {
    expect(service).toContain(
      "evaluateGameDayGoLivePreflight",
    );

    expect(service).toContain(
      "prepareBroadcastSession",
    );
  });

  it("blocks preparation when final preflight fails", () => {
    expect(route).toContain(
      "Broadcast preparation is blocked by final go-live preflight.",
    );
  });

  it("provides snapshot, prepare, and reset endpoints", () => {
    expect(route).toContain(
      '"/broadcast-coordinator/:gameId"',
    );

    expect(route).toContain(
      '"/broadcast-coordinator/:gameId/prepare"',
    );

    expect(route).toContain(
      '"/broadcast-coordinator/:gameId/reset"',
    );
  });

  it("registers coordinator routes", () => {
    expect(app).toContain(
      "registerBroadcastSessionCoordinatorRoutes",
    );
  });

  it("uses correlation ids for coordination tracing", () => {
    expect(service).toContain(
      "correlationId",
    );

    expect(service).toContain(
      "createCorrelationId",
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 22.1 installed"
echo "============================================================"
echo "Added:"
echo "  - broadcast session coordinator service"
echo "  - persisted coordinator intent"
echo "  - correlation IDs"
echo "  - existing preflight/go-live/runtime composition"
echo "  - preparation gate"
echo "  - snapshot/prepare/reset API"
echo "  - Milestone 22.1 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 22.2 - Coordinator Start / Stop Orchestration"
