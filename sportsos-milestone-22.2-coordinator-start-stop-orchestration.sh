#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-22.2-coordinator-start-stop-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/broadcastSessionCoordinator.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
GOLIVE="apps/api/src/services/goLiveSession.ts"
RUNTIME="apps/api/src/services/encoderRuntime.ts"
DEST="apps/api/src/services/streamDestinationProfile.ts"
PREFLIGHT="apps/api/src/services/gameDayGoLivePreflight.ts"
TEST="packages/core/test/broadcast-coordinator-start-stop-22.2.test.ts"
DOC="docs/BROADCAST-COORDINATOR.md"

for required in \
  ".git" \
  "$SERVICE" \
  "$ROUTE" \
  "$GOLIVE" \
  "$RUNTIME" \
  "$DEST" \
  "$PREFLIGHT" \
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

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/services/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("armGoLiveSession")) {
  s=s.replace(
`import {
  getGoLiveSession,
} from "./goLiveSession.js";`,
`import {
  armGoLiveSession,
  completeGoLiveSession,
  getGoLiveSession,
  markGoLiveStarting,
  markGoLiveStopping,
} from "./goLiveSession.js";`
  );
}

if(!s.includes("startEncoderRuntime")) {
  s=s.replace(
`import {
  encoderRuntimeSnapshot,
} from "./encoderRuntime.js";`,
`import {
  encoderRuntimeSnapshot,
  startEncoderRuntime,
  stopEncoderRuntime,
} from "./encoderRuntime.js";`
  );
}

if(!s.includes("getStreamDestinationProfile")) {
  const marker='import {\n  evaluateGameDayGoLivePreflight,\n} from "./gameDayGoLivePreflight.js";';
  s=s.replace(
    marker,
    marker + '\n\nimport {\n  getStreamDestinationProfile,\n} from "./streamDestinationProfile.js";'
  );
}

if(!s.includes("export async function startCoordinatedBroadcast")) {
  s += `

export async function startCoordinatedBroadcast(
  gameId: string,
): Promise<BroadcastCoordinatorSnapshot> {
  const preflight =
    evaluateGameDayGoLivePreflight(
      gameId,
    );

  if (!preflight.ready) {
    setBroadcastCoordinatorIntent({
      gameId,
      intent:
        "GO_LIVE",
      lastError:
        "Final game-day go-live preflight is blocked.",
    });

    throw new Error(
      "Final game-day go-live preflight is blocked.",
    );
  }

  const current =
    getGoLiveSession(
      gameId,
    );

  if (
    current.status !==
      "ARMED"
  ) {
    armGoLiveSession(
      gameId,
    );
  }

  const armed =
    getGoLiveSession(
      gameId,
    );

  if (
    armed.status !==
      "ARMED"
  ) {
    throw new Error(
      "Go-live session could not be armed.",
    );
  }

  const destination =
    getStreamDestinationProfile(
      gameId,
    );

  if (!destination) {
    throw new Error(
      "Stream destination is missing.",
    );
  }

  setBroadcastCoordinatorIntent({
    gameId,
    intent:
      "GO_LIVE",
    lastError:
      null,
  });

  markGoLiveStarting(
    gameId,
  );

  await startEncoderRuntime({
    gameId,
    destination,
  });

  return getBroadcastCoordinatorSnapshot(
    gameId,
  );
}

export async function stopCoordinatedBroadcast(
  gameId: string,
): Promise<BroadcastCoordinatorSnapshot> {
  setBroadcastCoordinatorIntent({
    gameId,
    intent:
      "STOP",
    lastError:
      null,
  });

  markGoLiveStopping(
    gameId,
  );

  await stopEncoderRuntime(
    gameId,
  );

  completeGoLiveSession(
    gameId,
  );

  setBroadcastCoordinatorIntent({
    gameId,
    intent:
      "IDLE",
    lastError:
      null,
  });

  return getBroadcastCoordinatorSnapshot(
    gameId,
  );
}
`;
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("startCoordinatedBroadcast")) {
  s=s.replace(
`  prepareBroadcastSession,
  setBroadcastCoordinatorIntent,`,
`  prepareBroadcastSession,
  setBroadcastCoordinatorIntent,
  startCoordinatedBroadcast,
  stopCoordinatedBroadcast,`
  );
}

if(!s.includes('"/broadcast-coordinator/:gameId/start"')) {
  const marker='  app.post(\n    "/broadcast-coordinator/:gameId/reset",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("Coordinator reset route missing.");

  const routes=`  app.post(
    "/broadcast-coordinator/:gameId/start",
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

      try {
        return {
          success: true,
          data:
            await startCoordinatedBroadcast(
              gameId,
            ),
        };
      } catch (error) {
        return reply.code(409).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Unable to start coordinated broadcast.",
          data:
            getBroadcastCoordinatorSnapshot(
              gameId,
            ),
        });
      }
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/stop",
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
          await stopCoordinatedBroadcast(
            gameId,
          ),
      };
    },
  );

`;

  s=s.slice(0,i)+routes+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 22.2 — Coordinator start / stop orchestration

The coordinator can now issue production start and stop intent while reusing the existing Milestone 21 go-live state and Milestone 20 encoder runtime.

Endpoints:

```text
POST /broadcast-coordinator/:gameId/start
POST /broadcast-coordinator/:gameId/stop
```

Start behavior:

- requires final game-day go-live preflight to pass
- ensures the existing go-live session is ARMED
- uses the existing stream destination profile
- transitions the existing go-live session to STARTING
- starts the existing encoder runtime
- records coordinator `GO_LIVE` intent

Stop behavior:

- records coordinator `STOP` intent
- transitions the existing go-live session to STOPPING
- stops the existing encoder runtime
- completes the existing go-live session
- returns coordinator intent to IDLE

The coordinator does not bypass go-live safety or create duplicate runtime state.
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.2 coordinator start / stop orchestration", () => {
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

  it("reuses final game-day preflight",()=> {
    expect(service).toContain("evaluateGameDayGoLivePreflight");
    expect(service).toContain("Final game-day go-live preflight is blocked.");
  });

  it("reuses existing go-live and encoder services",()=> {
    expect(service).toContain("armGoLiveSession");
    expect(service).toContain("markGoLiveStarting");
    expect(service).toContain("startEncoderRuntime");
    expect(service).toContain("stopEncoderRuntime");
    expect(service).toContain("completeGoLiveSession");
  });

  it("provides start and stop orchestration APIs",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/start"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/stop"');
  });

  it("tracks GO_LIVE and STOP coordinator intents",()=> {
    expect(service).toContain('intent:\n      "GO_LIVE"');
    expect(service).toContain('intent:\n      "STOP"');
  });

  it("does not define another encoder lifecycle",()=> {
    expect(service).not.toContain("BroadcastEncoderStatus");
    expect(service).not.toContain("CoordinatorEncoderState");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 22.2 installed"
echo "============================================================"
echo "Added:"
echo "  - coordinator start orchestration"
echo "  - coordinator stop orchestration"
echo "  - final-preflight enforcement"
echo "  - existing go-live state reuse"
echo "  - existing encoder runtime reuse"
echo "  - GO_LIVE / STOP correlation intent"
echo "  - Milestone 22.2 regression tests"
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
echo "  Milestone 22.3 - Coordinator Health / Drift Detection"
