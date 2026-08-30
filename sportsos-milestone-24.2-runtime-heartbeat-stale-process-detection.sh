#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-24.2-runtime-heartbeat-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/broadcastRuntimeHeartbeat.ts"
RUNTIME="apps/api/src/services/encoderRuntime.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/broadcast-runtime-heartbeat-24.2.test.ts"
DOC="docs/BROADCAST-RESILIENCE.md"

for required in \
  ".git" \
  "apps/api/src/services/broadcastRecoveryPolicy.ts" \
  "$RUNTIME" \
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
export type BroadcastRuntimeHeartbeatState =
  | "HEALTHY"
  | "STALE"
  | "MISSING"
  | "STOPPED"
  | "FAILED"
  | "UNKNOWN";

export type BroadcastRuntimeHeartbeatInput = {
  runtimeStatus: string;
  lastActivityAt: string | null;
  nowMs?: number;
  staleAfterMs?: number;
};

export type BroadcastRuntimeHeartbeat = {
  state:
    BroadcastRuntimeHeartbeatState;
  stale:
    boolean;
  ageMs:
    number | null;
  staleAfterMs:
    number;
  reason:
    string;
};

const DEFAULT_STALE_AFTER_MS =
  20_000;

export function evaluateBroadcastRuntimeHeartbeat(
  input: BroadcastRuntimeHeartbeatInput,
): BroadcastRuntimeHeartbeat {
  const staleAfterMs =
    Math.max(
      1_000,
      Math.min(
        input.staleAfterMs ??
        DEFAULT_STALE_AFTER_MS,
        300_000,
      ),
    );

  const nowMs =
    input.nowMs ??
    Date.now();

  const status =
    input.runtimeStatus
      .trim()
      .toUpperCase();

  if (
    status ===
      "STOPPED" ||
    status ===
      "IDLE"
  ) {
    return {
      state:
        "STOPPED",
      stale:
        false,
      ageMs:
        null,
      staleAfterMs,
      reason:
        "Encoder runtime is stopped.",
    };
  }

  if (
    status ===
      "ERROR" ||
    status ===
      "FAILED"
  ) {
    return {
      state:
        "FAILED",
      stale:
        false,
      ageMs:
        null,
      staleAfterMs,
      reason:
        "Encoder runtime reports a failure state.",
    };
  }

  if (
    !input.lastActivityAt
  ) {
    return {
      state:
        "MISSING",
      stale:
        true,
      ageMs:
        null,
      staleAfterMs,
      reason:
        "No encoder runtime heartbeat/activity timestamp is available.",
    };
  }

  const activityMs =
    Date.parse(
      input.lastActivityAt,
    );

  if (
    !Number.isFinite(
      activityMs,
    )
  ) {
    return {
      state:
        "UNKNOWN",
      stale:
        true,
      ageMs:
        null,
      staleAfterMs,
      reason:
        "Encoder runtime heartbeat timestamp is invalid.",
    };
  }

  const ageMs =
    Math.max(
      0,
      nowMs -
        activityMs,
    );

  if (
    ageMs >
    staleAfterMs
  ) {
    return {
      state:
        "STALE",
      stale:
        true,
      ageMs,
      staleAfterMs,
      reason:
        `Encoder runtime activity is stale by ${ageMs} ms.`,
    };
  }

  return {
    state:
      "HEALTHY",
    stale:
      false,
    ageMs,
    staleAfterMs,
    reason:
      "Encoder runtime activity is fresh.",
  };
}
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const importLine=`import {
  evaluateBroadcastRuntimeHeartbeat,
} from "../services/broadcastRuntimeHeartbeat.js";`;

if(!s.includes("evaluateBroadcastRuntimeHeartbeat")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/:gameId/runtime-heartbeat"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/:gameId/health",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("Coordinator health route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/:gameId/runtime-heartbeat",
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

      const session =
        snapshot.runtime.session;

      const telemetry =
        snapshot.runtime.telemetry;

      const lastActivityAt =
        telemetry.lastOutputAt ??
        telemetry.lastProgressAt ??
        telemetry.updatedAt ??
        session.updatedAt ??
        null;

      return {
        success: true,
        data: {
          gameId,
          heartbeat:
            evaluateBroadcastRuntimeHeartbeat({
              runtimeStatus:
                session.status,
              lastActivityAt,
            }),
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

## Milestone 24.2 — Runtime heartbeat / stale process detection

SportsOS now has a read-only encoder runtime heartbeat evaluator.

Heartbeat states:

```text
HEALTHY
STALE
MISSING
STOPPED
FAILED
UNKNOWN
```

Default staleness threshold:

```text
20 seconds
```

Configuration is bounded between:

```text
1 second
300 seconds
```

The evaluator uses the freshest runtime activity timestamp available from the existing encoder snapshot:

```text
lastOutputAt
lastProgressAt
telemetry.updatedAt
session.updatedAt
```

API:

```text
GET /broadcast-coordinator/:gameId/runtime-heartbeat
```

Milestone 24.2 is detection only.

A stale, missing, failed, or unknown heartbeat does **not** automatically restart or stop FFmpeg. Later resilience milestones consume this signal through the recovery policy and controlled supervisor.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  evaluateBroadcastRuntimeHeartbeat,
} from "../../../apps/api/src/services/broadcastRuntimeHeartbeat";

describe("Milestone 24.2 runtime heartbeat / stale process detection", () => {
  it("marks fresh runtime activity healthy",()=> {
    const now=100_000;

    expect(
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          new Date(
            now -
            5_000,
          ).toISOString(),
        nowMs:
          now,
      }).state,
    ).toBe(
      "HEALTHY",
    );
  });

  it("marks old runtime activity stale",()=> {
    const now=100_000;

    const result=
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          new Date(
            now -
            30_000,
          ).toISOString(),
        nowMs:
          now,
      });

    expect(
      result.state,
    ).toBe(
      "STALE",
    );

    expect(
      result.stale,
    ).toBe(
      true,
    );
  });

  it("distinguishes missing heartbeat from stopped runtime",()=> {
    expect(
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          null,
      }).state,
    ).toBe(
      "MISSING",
    );

    expect(
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "STOPPED",
        lastActivityAt:
          null,
      }).state,
    ).toBe(
      "STOPPED",
    );
  });

  it("classifies failed runtime",()=> {
    expect(
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "ERROR",
        lastActivityAt:
          null,
      }).state,
    ).toBe(
      "FAILED",
    );
  });

  it("rejects invalid timestamps conservatively",()=> {
    expect(
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          "not-a-date",
      }).state,
    ).toBe(
      "UNKNOWN",
    );
  });

  it("bounds stale threshold",()=> {
    expect(
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          new Date().toISOString(),
        staleAfterMs:
          1,
      }).staleAfterMs,
    ).toBe(
      1_000,
    );

    expect(
      evaluateBroadcastRuntimeHeartbeat({
        runtimeStatus:
          "LIVE",
        lastActivityAt:
          new Date().toISOString(),
        staleAfterMs:
          999_999,
      }).staleAfterMs,
    ).toBe(
      300_000,
    );
  });

  it("provides runtime-heartbeat API",()=> {
    const route=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/:gameId/runtime-heartbeat"',
    );

    expect(route).toContain(
      "evaluateBroadcastRuntimeHeartbeat",
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 24.2 installed"
echo "============================================================"
echo "Added:"
echo "  - encoder runtime heartbeat evaluator"
echo "  - stale/missing/failed/unknown detection"
echo "  - bounded 20s default staleness threshold"
echo "  - runtime-heartbeat API"
echo "  - read-only detection only"
echo "  - no automatic encoder restart/stop"
echo "  - Milestone 24.2 regression tests"
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
echo "  Milestone 24.3 - Coordinator/Runtime Reconciliation Supervisor"
