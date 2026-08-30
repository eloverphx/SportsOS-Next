#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-22.5-coordinator-audit-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

AUDIT="apps/api/src/services/broadcastCoordinatorAudit.ts"
SERVICE="apps/api/src/services/broadcastSessionCoordinator.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/broadcast-coordinator-audit-22.5.test.ts"
DOC="docs/BROADCAST-COORDINATOR.md"

for required in ".git" "$SERVICE" "$ROUTE" "$DOC"; do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$AUDIT" "$SERVICE" "$ROUTE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$AUDIT")" "$(dirname "$TEST")"

cat > "$AUDIT" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type BroadcastCoordinatorAuditType =
  | "INTENT_CHANGED"
  | "PREPARE_REQUESTED"
  | "PREPARE_BLOCKED"
  | "START_REQUESTED"
  | "START_COMPLETED"
  | "START_BLOCKED"
  | "STOP_REQUESTED"
  | "STOP_COMPLETED"
  | "DRIFT_DETECTED"
  | "RECONCILE_REQUESTED"
  | "RECONCILE_COMPLETED"
  | "RECONCILE_REFUSED";

export type BroadcastCoordinatorAuditEvent = {
  id: string;
  gameId: string;
  type: BroadcastCoordinatorAuditType;
  timestamp: string;
  correlationId: string | null;
  detail: string | null;
};

type Store = {
  version: 1;
  events: BroadcastCoordinatorAuditEvent[];
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
    "broadcast-coordinator-audit.json",
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
        parsed.events,
      )
    ) {
      throw new Error(
        "Invalid coordinator audit store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      events: [],
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

  fs.writeFileSync(
    STORE_FILE,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );
}

export function recordBroadcastCoordinatorAudit(input: {
  gameId: string;
  type: BroadcastCoordinatorAuditType;
  correlationId?: string | null;
  detail?: string | null;
}): BroadcastCoordinatorAuditEvent {
  const event: BroadcastCoordinatorAuditEvent = {
    id:
      `broadcast-coordinator-audit-${input.gameId}-${Date.now()}-${Math.random()
        .toString(36)
        .slice(2, 8)}`,
    gameId:
      input.gameId,
    type:
      input.type,
    timestamp:
      new Date().toISOString(),
    correlationId:
      input.correlationId ??
      null,
    detail:
      input.detail ??
      null,
  };

  store.events.push(
    event,
  );

  if (
    store.events.length >
    2500
  ) {
    store.events =
      store.events.slice(
        -2500,
      );
  }

  persistStore();

  return {
    ...event,
  };
}

export function listBroadcastCoordinatorAudit(
  gameId: string,
  limit = 100,
): BroadcastCoordinatorAuditEvent[] {
  const safeLimit =
    Math.max(
      1,
      Math.min(
        Math.floor(
          limit,
        ),
        250,
      ),
    );

  return store.events
    .filter(
      (event) =>
        event.gameId ===
        gameId,
    )
    .slice(
      -safeLimit,
    )
    .reverse()
    .map(
      (event) => ({
        ...event,
      }),
    );
}
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/services/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const auditImport=`import {
  recordBroadcastCoordinatorAudit,
} from "./broadcastCoordinatorAudit.js";`;

if(!s.includes("recordBroadcastCoordinatorAudit")) {
  const idx=s.indexOf("\n\n", s.indexOf("import "));
  if(idx<0) throw Error("Unable to locate coordinator imports.");
  s=s.slice(0,idx+2)+auditImport+"\n\n"+s.slice(idx+2);
}

if(!s.includes('"INTENT_CHANGED"')) {
  const marker=`  persistStore();

  return {
    ...record,
  };`;

  if(!s.includes(marker)) throw Error("Coordinator intent persistence block missing.");

  s=s.replace(
    marker,
`  persistStore();

  recordBroadcastCoordinatorAudit({
    gameId:
      input.gameId,
    type:
      "INTENT_CHANGED",
    correlationId:
      record.correlationId,
    detail:
      \`Intent changed to \${record.intent}.\`,
  });

  return {
    ...record,
  };`
  );
}

if(!s.includes('"PREPARE_REQUESTED"')) {
  const marker=`export function prepareBroadcastSession(
  gameId: string,
): BroadcastCoordinatorSnapshot {`;

  if(!s.includes(marker)) throw Error("prepareBroadcastSession missing.");

  s=s.replace(
    marker,
`${marker}
  const coordinator =
    getBroadcastCoordinatorRecord(
      gameId,
    );

  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "PREPARE_REQUESTED",
    correlationId:
      coordinator.correlationId,
  });
`
  );

  const blocked=`  setBroadcastCoordinatorIntent({
    gameId,
    intent:
      "PREPARE",
    lastError:
      preflight.ready
        ? null
        : "Game-day go-live preflight is blocked.",
  });`;

  if(s.includes(blocked)) {
    s=s.replace(
      blocked,
`${blocked}

  if (!preflight.ready) {
    recordBroadcastCoordinatorAudit({
      gameId,
      type:
        "PREPARE_BLOCKED",
      correlationId:
        getBroadcastCoordinatorRecord(
          gameId,
        ).correlationId,
      detail:
        "Game-day go-live preflight is blocked.",
    });
  }`
    );
  }
}

if(!s.includes('"START_REQUESTED"')) {
  const marker=`export async function startCoordinatedBroadcast(
  gameId: string,
): Promise<BroadcastCoordinatorSnapshot> {`;

  if(!s.includes(marker)) throw Error("startCoordinatedBroadcast missing.");

  s=s.replace(
    marker,
`${marker}
  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "START_REQUESTED",
    correlationId:
      getBroadcastCoordinatorRecord(
        gameId,
      ).correlationId,
  });
`
  );

  const blocked=`    throw new Error(
      "Final game-day go-live preflight is blocked.",
    );`;

  if(s.includes(blocked)) {
    s=s.replace(
      blocked,
`    recordBroadcastCoordinatorAudit({
      gameId,
      type:
        "START_BLOCKED",
      correlationId:
        getBroadcastCoordinatorRecord(
          gameId,
        ).correlationId,
      detail:
        "Final game-day go-live preflight is blocked.",
    });

${blocked}`
    );
  }

  const marker2=`  return getBroadcastCoordinatorSnapshot(
    gameId,
  );
}

export async function stopCoordinatedBroadcast`;

  if(s.includes(marker2)) {
    s=s.replace(
      marker2,
`  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "START_COMPLETED",
    correlationId:
      getBroadcastCoordinatorRecord(
        gameId,
      ).correlationId,
  });

  return getBroadcastCoordinatorSnapshot(
    gameId,
  );
}

export async function stopCoordinatedBroadcast`
    );
  }
}

if(!s.includes('"STOP_REQUESTED"')) {
  const marker=`export async function stopCoordinatedBroadcast(
  gameId: string,
): Promise<BroadcastCoordinatorSnapshot> {`;

  if(!s.includes(marker)) throw Error("stopCoordinatedBroadcast missing.");

  s=s.replace(
    marker,
`${marker}
  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "STOP_REQUESTED",
    correlationId:
      getBroadcastCoordinatorRecord(
        gameId,
      ).correlationId,
  });
`
  );

  const marker2=`  return getBroadcastCoordinatorSnapshot(
    gameId,
  );
}

export type BroadcastCoordinatorHealth`;

  if(s.includes(marker2)) {
    s=s.replace(
      marker2,
`  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "STOP_COMPLETED",
    correlationId:
      getBroadcastCoordinatorRecord(
        gameId,
      ).correlationId,
  });

  return getBroadcastCoordinatorSnapshot(
    gameId,
  );
}

export type BroadcastCoordinatorHealth`
    );
  }
}

if(!s.includes('"DRIFT_DETECTED"')) {
  const marker=`  return {
    gameId,
    healthy:
      issues.length ===
      0,`;

  if(!s.includes(marker)) throw Error("Coordinator health return block missing.");

  s=s.replace(
    marker,
`  if (issues.length > 0) {
    recordBroadcastCoordinatorAudit({
      gameId,
      type:
        "DRIFT_DETECTED",
      correlationId:
        snapshot.coordinator.correlationId,
      detail:
        issues
          .map(
            (issue) =>
              \`\${issue.id}: \${issue.message}\`,
          )
          .join(" | "),
    });
  }

${marker}`
  );
}

if(!s.includes('"RECONCILE_REQUESTED"')) {
  const marker=`export async function reconcileBroadcastCoordinator(
  gameId: string,
): Promise<BroadcastCoordinatorReconciliation> {`;

  if(!s.includes(marker)) throw Error("reconcileBroadcastCoordinator missing.");

  s=s.replace(
    marker,
`${marker}
  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "RECONCILE_REQUESTED",
    correlationId:
      getBroadcastCoordinatorRecord(
        gameId,
      ).correlationId,
  });
`
  );

  const refuse=`  return {
    gameId,
    action:
      "REFUSE_AMBIGUOUS",`;

  if(s.includes(refuse)) {
    s=s.replace(
      refuse,
`  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "RECONCILE_REFUSED",
    correlationId:
      getBroadcastCoordinatorRecord(
        gameId,
      ).correlationId,
    detail:
      "Coordinator drift is ambiguous and requires operator review.",
  });

${refuse}`
    );
  }

  s=s.replaceAll(
`    return {
      gameId,
      action:
        "STOP_RUNTIME",`,
`    recordBroadcastCoordinatorAudit({
      gameId,
      type:
        "RECONCILE_COMPLETED",
      correlationId:
        getBroadcastCoordinatorRecord(
          gameId,
        ).correlationId,
      detail:
        "STOP_RUNTIME",
    });

    return {
      gameId,
      action:
        "STOP_RUNTIME",`
  );

  s=s.replaceAll(
`    return {
      gameId,
      action:
        "RESET_INTENT",`,
`    recordBroadcastCoordinatorAudit({
      gameId,
      type:
        "RECONCILE_COMPLETED",
      correlationId:
        getBroadcastCoordinatorRecord(
          gameId,
        ).correlationId,
      detail:
        "RESET_INTENT",
    });

    return {
      gameId,
      action:
        "RESET_INTENT",`
  );
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const importLine=`import {
  listBroadcastCoordinatorAudit,
} from "../services/broadcastCoordinatorAudit.js";`;

if(!s.includes("listBroadcastCoordinatorAudit")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate coordinator route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/:gameId/audit"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/:gameId/health",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("22.3 health route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/:gameId/audit",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const query =
        request.query as {
          limit?: string;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const parsed =
        Number.parseInt(
          query.limit ??
          "100",
          10,
        );

      return {
        success: true,
        data: {
          events:
            listBroadcastCoordinatorAudit(
              gameId,
              Number.isFinite(parsed)
                ? parsed
                : 100,
            ),
        },
      };
    },
  );

`;

  s=s.slice(0,i)+route+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 22.5 — Coordinator audit / reconciliation history

Coordinator automation now has its own persistent audit history, separate from encoder runtime audit, go-live lifecycle audit, and authoritative game events.

Recorded event types include:

```text
INTENT_CHANGED
PREPARE_REQUESTED
PREPARE_BLOCKED
START_REQUESTED
START_COMPLETED
START_BLOCKED
STOP_REQUESTED
STOP_COMPLETED
DRIFT_DETECTED
RECONCILE_REQUESTED
RECONCILE_COMPLETED
RECONCILE_REFUSED
```

Audit entries retain coordinator correlation IDs when available.

API:

```text
GET /broadcast-coordinator/:gameId/audit?limit=100
```

The store keeps the newest 2500 coordinator events globally and limits an individual request to 250 events.
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.5 coordinator audit / reconciliation history", () => {
  const audit=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/broadcastCoordinatorAudit.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const service=fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/broadcastSessionCoordinator.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route=fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("persists bounded coordinator audit history",()=> {
    expect(audit).toContain("broadcast-coordinator-audit.json");
    expect(audit).toContain("2500");
  });

  it("records coordinator orchestration history",()=> {
    for(const event of [
      "INTENT_CHANGED",
      "PREPARE_REQUESTED",
      "START_REQUESTED",
      "START_COMPLETED",
      "STOP_REQUESTED",
      "STOP_COMPLETED",
    ]) {
      expect(service).toContain(`"${event}"`);
    }
  });

  it("records drift and reconciliation decisions",()=> {
    expect(service).toContain('"DRIFT_DETECTED"');
    expect(service).toContain('"RECONCILE_REQUESTED"');
    expect(service).toContain('"RECONCILE_COMPLETED"');
    expect(service).toContain('"RECONCILE_REFUSED"');
  });

  it("retains correlation ids",()=> {
    expect(audit).toContain("correlationId");
  });

  it("provides coordinator audit API",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/audit"');
    expect(route).toContain("listBroadcastCoordinatorAudit");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 22.5 installed"
echo "============================================================"
echo "Added:"
echo "  - persistent coordinator audit store"
echo "  - intent/preparation history"
echo "  - start/stop orchestration history"
echo "  - drift detection history"
echo "  - reconciliation/refusal history"
echo "  - correlation ID retention"
echo "  - coordinator audit API"
echo "  - Milestone 22.5 regression tests"
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
echo "  Milestone 22.6 - Coordinator Retry Policy / Backoff"
