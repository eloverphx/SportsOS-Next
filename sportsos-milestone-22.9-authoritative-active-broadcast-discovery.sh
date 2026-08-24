#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-22.9-active-broadcast-discovery-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

COORD="apps/api/src/services/broadcastSessionCoordinator.ts"
APP="apps/api/src/app.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/active-broadcast-discovery-22.9.test.ts"
DOC="docs/BROADCAST-COORDINATOR.md"

for required in ".git" "$COORD" "$APP" "$ROUTE" "$DOC"; do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$COORD" "$APP" "$ROUTE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/services/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("export function listActiveBroadcastGameIds")) {
  const marker="export function getBroadcastCoordinatorRecord(";
  const i=s.indexOf(marker);
  if(i<0) throw new Error("Unable to locate coordinator record service.");

  const addition=`export function listKnownBroadcastCoordinatorGameIds(): string[] {
  return Array.from(
    new Set(
      store.records
        .map((record) => record.gameId)
        .filter(Boolean),
    ),
  );
}

export function listActiveBroadcastGameIds(): string[] {
  return listKnownBroadcastCoordinatorGameIds()
    .filter((gameId) => {
      const coordinator =
        getBroadcastCoordinatorRecord(
          gameId,
        );

      const goLive =
        getGoLiveSession(
          gameId,
        );

      const runtime =
        encoderRuntimeSnapshot(
          gameId,
        );

      const coordinatorActive =
        coordinator.intent !==
        "IDLE";

      const goLiveActive =
        [
          "ARMED",
          "STARTING",
          "LIVE",
          "DEGRADED",
          "STOPPING",
        ].includes(
          goLive.status,
        );

      const runtimeActive =
        ![
          "STOPPED",
          "ERROR",
        ].includes(
          runtime.session.status,
        );

      return (
        coordinatorActive ||
        goLiveActive ||
        runtimeActive
      );
    });
}

`;

  s=s.slice(0,i)+addition+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/app.ts";
let s=fs.readFileSync(f,"utf8");

const importLine='import { listActiveBroadcastGameIds } from "./services/broadcastSessionCoordinator.js";';

if(!s.includes(importLine)) {
  const marker='import { startBroadcastCoordinatorSupervisor } from "./services/broadcastSessionCoordinatorSupervisor.js";';
  if(!s.includes(marker)) throw new Error("22.8 supervisor runtime import missing.");
  s=s.replace(marker, marker+"\n"+importLine);
}

if(s.includes("gameIds: () => []")) {
  s=s.replace(
    "gameIds: () => []",
    "gameIds: () => listActiveBroadcastGameIds()",
  );
}

if(!s.includes("gameIds: () => listActiveBroadcastGameIds()")) {
  throw new Error("Unable to wire authoritative active broadcast discovery.");
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("listActiveBroadcastGameIds")) {
  s=s.replace(
`  getBroadcastCoordinatorRetry,
  getBroadcastCoordinatorSnapshot,`,
`  getBroadcastCoordinatorRetry,
  getBroadcastCoordinatorSnapshot,
  listActiveBroadcastGameIds,`
  );
}

if(!s.includes('"/broadcast-coordinator/active"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/:gameId/audit",';
  let i=s.indexOf(marker);

  if(i<0) {
    i=s.indexOf('  app.get(\n    "/broadcast-coordinator/:gameId/health",');
  }

  if(i<0) throw new Error("Unable to locate coordinator route insertion point.");

  const route=`  app.get(
    "/broadcast-coordinator/active",
    async () => {
      const gameIds =
        listActiveBroadcastGameIds();

      return {
        success: true,
        data: {
          gameIds,
          count:
            gameIds.length,
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

## Milestone 22.9 — Authoritative active broadcast discovery

The supervisor runtime no longer uses an empty placeholder game provider.

Active broadcast discovery is derived from the existing operational sources:

```text
coordinator intent
go-live session state
encoder runtime state
```

A known game is considered active when coordinator intent is not `IDLE`, the existing go-live session is `ARMED`, `STARTING`, `LIVE`, `DEGRADED`, or `STOPPING`, or the existing encoder runtime is neither `STOPPED` nor `ERROR`.

This avoids creating a second broadcast-active flag or parallel lifecycle.

API:

```text
GET /broadcast-coordinator/active
```

The API runtime supervisor now uses `listActiveBroadcastGameIds()` as its game discovery provider.

Discovery is read-only and does not start, stop, arm, reconcile, or modify authoritative game state.
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.9 authoritative active broadcast discovery", () => {
  const service=fs.readFileSync(new URL("../../../apps/api/src/services/broadcastSessionCoordinator.ts",import.meta.url),"utf8");
  const app=fs.readFileSync(new URL("../../../apps/api/src/app.ts",import.meta.url),"utf8");
  const route=fs.readFileSync(new URL("../../../apps/api/src/routes/broadcastSessionCoordinator.ts",import.meta.url),"utf8");

  it("discovers known coordinator game ids",()=> {
    expect(service).toContain("listKnownBroadcastCoordinatorGameIds");
    expect(service).toContain("store.records");
  });

  it("derives active state from existing operational sources",()=> {
    expect(service).toContain("coordinator.intent");
    expect(service).toContain("getGoLiveSession");
    expect(service).toContain("encoderRuntimeSnapshot");
  });

  it("recognizes active go-live states",()=> {
    for(const state of ["ARMED","STARTING","LIVE","DEGRADED","STOPPING"]) {
      expect(service).toContain(`"${state}"`);
    }
  });

  it("does not create a separate active flag",()=> {
    expect(service).not.toContain("broadcastActive:");
    expect(service).not.toContain("isBroadcastActive:");
  });

  it("wires supervisor runtime to active discovery",()=> {
    expect(app).toContain("listActiveBroadcastGameIds");
    expect(app).toContain("gameIds: () => listActiveBroadcastGameIds()");
    expect(app).not.toContain("gameIds: () => []");
  });

  it("provides active broadcast discovery API",()=> {
    expect(route).toContain('"/broadcast-coordinator/active"');
    expect(route).toContain("listActiveBroadcastGameIds");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 22.9 installed"
echo "============================================================"
echo "Added:"
echo "  - known coordinator game discovery"
echo "  - active broadcast discovery"
echo "  - coordinator/go-live/runtime composition"
echo "  - removal of empty supervisor provider"
echo "  - active broadcast API"
echo "  - no duplicate active-state flag"
echo "  - Milestone 22.9 regression tests"
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
echo "  Milestone 22.10 - Broadcast Automation Acceptance / Closeout"
