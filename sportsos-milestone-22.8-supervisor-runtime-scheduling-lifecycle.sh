#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-22.8-supervisor-runtime-${STAMP}"
[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || { echo "ERROR: refusing to run outside $EXPECTED"; exit 1; }
cd "$ROOT"

SERVICE="apps/api/src/services/broadcastSessionCoordinatorSupervisor.ts"
COORD="apps/api/src/services/broadcastSessionCoordinator.ts"
APP="apps/api/src/app.ts"
AUDIT="apps/api/src/services/broadcastCoordinatorAudit.ts"
TEST="packages/core/test/broadcast-coordinator-supervisor-runtime-22.8.test.ts"
DOC="docs/BROADCAST-COORDINATOR.md"

for f in .git "$COORD" "$APP" "$AUDIT" "$DOC"; do
  [[ -e "$f" ]] || { echo "ERROR: prerequisite missing: $ROOT/$f"; echo "Repository was not modified."; exit 1; }
done

for f in "$SERVICE" "$APP" "$AUDIT" "$TEST" "$DOC"; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp -a "$f" "$BACKUP/$f"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/services/broadcastCoordinatorAudit.ts";
let s=fs.readFileSync(f,"utf8");
if(!s.includes('"SUPERVISOR_STARTED"')) {
  s=s.replace(
    '  | "SUPERVISOR_ACTION_REFUSED";',
    '  | "SUPERVISOR_ACTION_REFUSED"\n  | "SUPERVISOR_STARTED"\n  | "SUPERVISOR_STOPPED"\n  | "SUPERVISOR_TICK_FAILED";'
  );
}
fs.writeFileSync(f,s);
NODE

cat > "$SERVICE" <<'EOF'
import {
  recordBroadcastCoordinatorAudit,
} from "./broadcastCoordinatorAudit.js";

import {
  runBroadcastCoordinatorSupervisorTick,
} from "./broadcastSessionCoordinator.js";

export type BroadcastCoordinatorSupervisorRuntimeOptions = {
  gameIds: () => string[];
  intervalMs?: number;
  onError?: (
    error: unknown,
    gameId: string,
  ) => void;
};

export function startBroadcastCoordinatorSupervisor(
  options: BroadcastCoordinatorSupervisorRuntimeOptions,
): () => void {
  const intervalMs =
    Math.max(
      1000,
      Math.min(
        options.intervalMs ??
        5000,
        60000,
      ),
    );

  let stopped = false;

  const runTick =
    async (): Promise<void> => {
      if (stopped) {
        return;
      }

      const gameIds =
        Array.from(
          new Set(
            options
              .gameIds()
              .map((gameId) => gameId.trim())
              .filter(Boolean),
          ),
        );

      for (const gameId of gameIds) {
        try {
          await runBroadcastCoordinatorSupervisorTick(
            gameId,
          );
        } catch (error) {
          recordBroadcastCoordinatorAudit({
            gameId,
            type:
              "SUPERVISOR_TICK_FAILED",
            detail:
              error instanceof Error
                ? error.message
                : "Unknown supervisor tick failure.",
          });

          options.onError?.(
            error,
            gameId,
          );
        }
      }
    };

  const timer =
    setInterval(
      () => {
        void runTick();
      },
      intervalMs,
    );

  recordBroadcastCoordinatorAudit({
    gameId:
      "__runtime__",
    type:
      "SUPERVISOR_STARTED",
    detail:
      `intervalMs=${intervalMs}`,
  });

  void runTick();

  return () => {
    if (stopped) {
      return;
    }

    stopped = true;
    clearInterval(timer);

    recordBroadcastCoordinatorAudit({
      gameId:
        "__runtime__",
      type:
        "SUPERVISOR_STOPPED",
      detail:
        `intervalMs=${intervalMs}`,
    });
  };
}
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/app.ts";
let s=fs.readFileSync(f,"utf8");

const importLine='import { startBroadcastCoordinatorSupervisor } from "./services/broadcastSessionCoordinatorSupervisor.js";';

if(!s.includes(importLine)) {
  const marker='import { registerGoLiveSessionRoutes } from "./routes/goLiveSessions.js";';
  if(!s.includes(marker)) throw Error("Go-live route import missing.");
  s=s.replace(marker, marker+"\n"+importLine);
}

if(!s.includes("stopBroadcastCoordinatorSupervisor")) {
  const varMarker='    let stopRealtimeOutboxDispatcher: (() => void) | undefined;';
  if(!s.includes(varMarker)) throw Error("Runtime variable block missing.");
  s=s.replace(
    varMarker,
    varMarker+'\n    let stopBroadcastCoordinatorSupervisor: (() => void) | undefined;'
  );

  const startMarker=`      stopGameRuntimeSupervisor = startGameRuntimeSupervisor({
        onError: (error) =>
          app.log.error({ error }, "Game runtime supervisor failed"),
      });`;

  if(!s.includes(startMarker)) throw Error("Game runtime supervisor startup block missing.");

  s=s.replace(
    startMarker,
`${startMarker}

      stopBroadcastCoordinatorSupervisor =
        startBroadcastCoordinatorSupervisor({
          gameIds: () => [],
          intervalMs:
            5000,
          onError: (
            error,
            gameId,
          ) =>
            app.log.error(
              {
                error,
                gameId,
              },
              "Broadcast coordinator supervisor tick failed",
            ),
        });`
  );

  const closeMarker='      stopRealtimeOutboxDispatcher?.();';
  if(!s.includes(closeMarker)) throw Error("Shutdown block missing.");
  s=s.replace(
    closeMarker,
    closeMarker+'\n      stopBroadcastCoordinatorSupervisor?.();'
  );
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 22.8 — Supervisor runtime scheduling / lifecycle

The bounded coordinator supervisor tick now has an application-runtime scheduler.

Runtime behavior:

```text
default interval: 5000 ms
minimum interval: 1000 ms
maximum interval: 60000 ms
```

The runtime invokes only the existing bounded supervisor tick, isolates failures per game, records startup/shutdown/failure audit events, starts with the API lifecycle, and stops cleanly during API shutdown.

The scheduler accepts a `gameIds()` provider. Milestone 22.8 intentionally wires an empty provider until an authoritative active-broadcast discovery source is added. This establishes lifecycle behavior without accidentally enabling global automation.

The runtime never directly starts FFmpeg.
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.8 coordinator supervisor runtime scheduling", () => {
  const runtime=fs.readFileSync(new URL("../../../apps/api/src/services/broadcastSessionCoordinatorSupervisor.ts",import.meta.url),"utf8");
  const app=fs.readFileSync(new URL("../../../apps/api/src/app.ts",import.meta.url),"utf8");
  const audit=fs.readFileSync(new URL("../../../apps/api/src/services/broadcastCoordinatorAudit.ts",import.meta.url),"utf8");

  it("uses bounded scheduling interval",()=> {
    expect(runtime).toContain("5000");
    expect(runtime).toContain("1000");
    expect(runtime).toContain("60000");
  });

  it("runs the existing bounded supervisor tick",()=> {
    expect(runtime).toContain("runBroadcastCoordinatorSupervisorTick");
  });

  it("isolates per-game failures and supports shutdown",()=> {
    expect(runtime).toContain("catch (error)");
    expect(runtime).toContain("options.onError?.");
    expect(runtime).toContain("clearInterval");
  });

  it("registers API lifecycle startup and shutdown",()=> {
    expect(app).toContain("startBroadcastCoordinatorSupervisor");
    expect(app).toContain("stopBroadcastCoordinatorSupervisor?.()");
  });

  it("records runtime lifecycle audit events",()=> {
    expect(audit).toContain('"SUPERVISOR_STARTED"');
    expect(audit).toContain('"SUPERVISOR_STOPPED"');
    expect(audit).toContain('"SUPERVISOR_TICK_FAILED"');
  });

  it("does not directly start encoder",()=> {
    expect(runtime).not.toContain("startEncoderRuntime");
    expect(runtime).not.toContain("startCoordinatedBroadcast");
  });

  it("uses safe empty discovery until authoritative discovery lands",()=> {
    expect(app).toContain("gameIds: () => []");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 22.8 installed"
echo "============================================================"
echo "Added:"
echo "  - supervisor runtime scheduler"
echo "  - bounded 1s-60s interval"
echo "  - default 5s cadence"
echo "  - per-game failure isolation"
echo "  - clean API startup/shutdown lifecycle"
echo "  - supervisor lifecycle audit events"
echo "  - safe empty active-game provider"
echo "  - no direct FFmpeg start"
echo "  - Milestone 22.8 regression tests"
echo
echo "Backup: $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 22.9 - Authoritative Active Broadcast Discovery"
