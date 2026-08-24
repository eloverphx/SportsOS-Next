#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-22.6-coordinator-retry-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/broadcastSessionCoordinator.ts"
AUDIT="apps/api/src/services/broadcastCoordinatorAudit.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/broadcast-coordinator-retry-backoff-22.6.test.ts"
DOC="docs/BROADCAST-COORDINATOR.md"

for required in ".git" "$SERVICE" "$AUDIT" "$ROUTE" "$DOC"; do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$AUDIT" "$ROUTE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/services/broadcastCoordinatorAudit.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes('"RETRY_SCHEDULED"')) {
  s=s.replace(
`  | "RECONCILE_REFUSED";`,
`  | "RECONCILE_REFUSED"
  | "RETRY_SCHEDULED"
  | "RETRY_ATTEMPTED"
  | "RETRY_EXHAUSTED";`
  );
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/services/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("export type BroadcastCoordinatorRetryState")) {
  s += `

export type BroadcastCoordinatorRetryState =
  | "IDLE"
  | "SCHEDULED"
  | "RETRYING"
  | "EXHAUSTED";

export type BroadcastCoordinatorRetry = {
  gameId: string;
  state: BroadcastCoordinatorRetryState;
  attempts: number;
  maxAttempts: number;
  backoffSeconds: number;
  nextRetryAt: string | null;
  lastError: string | null;
};

const coordinatorRetry =
  new Map<
    string,
    BroadcastCoordinatorRetry
  >();

export function getBroadcastCoordinatorRetry(
  gameId: string,
): BroadcastCoordinatorRetry {
  return (
    coordinatorRetry.get(
      gameId,
    ) ?? {
      gameId,
      state:
        "IDLE",
      attempts:
        0,
      maxAttempts:
        3,
      backoffSeconds:
        10,
      nextRetryAt:
        null,
      lastError:
        null,
    }
  );
}

export function configureBroadcastCoordinatorRetry(input: {
  gameId: string;
  maxAttempts?: number;
  backoffSeconds?: number;
}): BroadcastCoordinatorRetry {
  const current =
    getBroadcastCoordinatorRetry(
      input.gameId,
    );

  const next: BroadcastCoordinatorRetry = {
    ...current,
    maxAttempts:
      Number.isFinite(
        input.maxAttempts,
      )
        ? Math.max(
            0,
            Math.min(
              10,
              Math.floor(
                Number(
                  input.maxAttempts,
                ),
              ),
            ),
          )
        : current.maxAttempts,
    backoffSeconds:
      Number.isFinite(
        input.backoffSeconds,
      )
        ? Math.max(
            1,
            Math.min(
              300,
              Math.floor(
                Number(
                  input.backoffSeconds,
                ),
              ),
            ),
          )
        : current.backoffSeconds,
  };

  coordinatorRetry.set(
    input.gameId,
    next,
  );

  return next;
}

export function scheduleBroadcastCoordinatorRetry(
  gameId: string,
  error: string,
): BroadcastCoordinatorRetry {
  const current =
    getBroadcastCoordinatorRetry(
      gameId,
    );

  if (
    current.attempts >=
    current.maxAttempts
  ) {
    const exhausted: BroadcastCoordinatorRetry = {
      ...current,
      state:
        "EXHAUSTED",
      nextRetryAt:
        null,
      lastError:
        error,
    };

    coordinatorRetry.set(
      gameId,
      exhausted,
    );

    recordBroadcastCoordinatorAudit({
      gameId,
      type:
        "RETRY_EXHAUSTED",
      correlationId:
        getBroadcastCoordinatorRecord(
          gameId,
        ).correlationId,
      detail:
        error,
    });

    return exhausted;
  }

  const nextAttempt =
    current.attempts +
    1;

  const nextRetryAt =
    new Date(
      Date.now() +
        current.backoffSeconds *
          1000 *
          nextAttempt,
    ).toISOString();

  const scheduled: BroadcastCoordinatorRetry = {
    ...current,
    state:
      "SCHEDULED",
    attempts:
      nextAttempt,
    nextRetryAt,
    lastError:
      error,
  };

  coordinatorRetry.set(
    gameId,
    scheduled,
  );

  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "RETRY_SCHEDULED",
    correlationId:
      getBroadcastCoordinatorRecord(
        gameId,
      ).correlationId,
    detail:
      \`Attempt \${nextAttempt}/\${scheduled.maxAttempts} at \${nextRetryAt}: \${error}\`,
  });

  return scheduled;
}

export async function executeBroadcastCoordinatorRetry(
  gameId: string,
): Promise<{
  retry:
    BroadcastCoordinatorRetry;
  snapshot:
    BroadcastCoordinatorSnapshot;
}> {
  const current =
    getBroadcastCoordinatorRetry(
      gameId,
    );

  if (
    current.state !==
    "SCHEDULED"
  ) {
    throw new Error(
      "Coordinator retry is not scheduled.",
    );
  }

  if (
    current.nextRetryAt &&
    Date.now() <
      Date.parse(
        current.nextRetryAt,
      )
  ) {
    throw new Error(
      "Coordinator retry backoff has not elapsed.",
    );
  }

  const retrying: BroadcastCoordinatorRetry = {
    ...current,
    state:
      "RETRYING",
  };

  coordinatorRetry.set(
    gameId,
    retrying,
  );

  recordBroadcastCoordinatorAudit({
    gameId,
    type:
      "RETRY_ATTEMPTED",
    correlationId:
      getBroadcastCoordinatorRecord(
        gameId,
      ).correlationId,
    detail:
      \`Attempt \${retrying.attempts}/\${retrying.maxAttempts}\`,
  });

  const preflight =
    evaluateGameDayGoLivePreflight(
      gameId,
    );

  if (!preflight.ready) {
    const retry =
      scheduleBroadcastCoordinatorRetry(
        gameId,
        "Final game-day go-live preflight is still blocked.",
      );

    return {
      retry,
      snapshot:
        getBroadcastCoordinatorSnapshot(
          gameId,
        ),
    };
  }

  const idle: BroadcastCoordinatorRetry = {
    ...retrying,
    state:
      "IDLE",
    attempts:
      0,
    nextRetryAt:
      null,
    lastError:
      null,
  };

  coordinatorRetry.set(
    gameId,
    idle,
  );

  return {
    retry:
      idle,
    snapshot:
      prepareBroadcastSession(
        gameId,
      ),
  };
}
`;
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("configureBroadcastCoordinatorRetry")) {
  s=s.replace(
`  evaluateBroadcastCoordinatorHealth,
  getBroadcastCoordinatorSnapshot,`,
`  configureBroadcastCoordinatorRetry,
  evaluateBroadcastCoordinatorHealth,
  executeBroadcastCoordinatorRetry,
  getBroadcastCoordinatorRetry,
  getBroadcastCoordinatorSnapshot,
  scheduleBroadcastCoordinatorRetry,`
  );
}

if(!s.includes('"/broadcast-coordinator/:gameId/retry"')) {
  const marker='  app.post(\n    "/broadcast-coordinator/:gameId/reconcile",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("22.4 reconcile route missing.");

  const routes=`  app.get(
    "/broadcast-coordinator/:gameId/retry",
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
          retry:
            getBroadcastCoordinatorRetry(
              gameId,
            ),
        },
      };
    },
  );

  app.put(
    "/broadcast-coordinator/:gameId/retry",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          maxAttempts?: number;
          backoffSeconds?: number;
        };

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
          retry:
            configureBroadcastCoordinatorRetry({
              gameId,
              maxAttempts:
                body.maxAttempts,
              backoffSeconds:
                body.backoffSeconds,
            }),
        },
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/retry/schedule",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          error?: string;
        };

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
          retry:
            scheduleBroadcastCoordinatorRetry(
              gameId,
              body.error?.trim() ||
                "Coordinator retry requested.",
            ),
        },
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/retry/execute",
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
            await executeBroadcastCoordinatorRetry(
              gameId,
            ),
        };
      } catch (error) {
        return reply.code(409).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Coordinator retry failed.",
          data: {
            retry:
              getBroadcastCoordinatorRetry(
                gameId,
              ),
          },
        });
      }
    },
  );

`;

  s=s.slice(0,i)+routes+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 22.6 — Coordinator retry policy / backoff

The coordinator now has a bounded retry policy for automation-level preparation failures.

Retry states:

```text
IDLE
SCHEDULED
RETRYING
EXHAUSTED
```

Defaults:

```text
max attempts: 3
base backoff: 10 seconds
```

Configuration limits:

```text
max attempts: 0–10
backoff: 1–300 seconds
```

Retry APIs:

```text
GET  /broadcast-coordinator/:gameId/retry
PUT  /broadcast-coordinator/:gameId/retry
POST /broadcast-coordinator/:gameId/retry/schedule
POST /broadcast-coordinator/:gameId/retry/execute
```

Backoff grows with the attempt number.

A retry never bypasses final game-day go-live preflight. If preflight remains blocked, another bounded retry is scheduled until attempts are exhausted.

Retry execution only returns to broadcast preparation. It does not automatically start FFmpeg.
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 22.6 coordinator retry policy / backoff", () => {
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

  it("defines bounded retry states",()=> {
    for(const state of [
      "IDLE",
      "SCHEDULED",
      "RETRYING",
      "EXHAUSTED",
    ]) {
      expect(service).toContain(`"${state}"`);
    }
  });

  it("supports bounded attempts and backoff",()=> {
    expect(service).toContain("maxAttempts");
    expect(service).toContain("backoffSeconds");
    expect(service).toContain("Math.min");
  });

  it("records retry audit events",()=> {
    expect(audit).toContain('"RETRY_SCHEDULED"');
    expect(audit).toContain('"RETRY_ATTEMPTED"');
    expect(audit).toContain('"RETRY_EXHAUSTED"');
  });

  it("rechecks final preflight before retry success",()=> {
    expect(service).toContain("evaluateGameDayGoLivePreflight");
    expect(service).toContain("Final game-day go-live preflight is still blocked.");
  });

  it("does not auto-start ffmpeg during retry",()=> {
    const start=service.indexOf("export async function executeBroadcastCoordinatorRetry");
    const block=service.slice(start);
    expect(block).not.toContain("startEncoderRuntime(");
  });

  it("provides retry APIs",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/retry"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/retry/schedule"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/retry/execute"');
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 22.6 installed"
echo "============================================================"
echo "Added:"
echo "  - bounded coordinator retry state"
echo "  - configurable attempts/backoff"
echo "  - scheduled retry timing"
echo "  - retry exhaustion"
echo "  - final-preflight recheck"
echo "  - retry audit events"
echo "  - no automatic FFmpeg start"
echo "  - Milestone 22.6 regression tests"
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
echo "  Milestone 22.7 - Coordinator Supervisor / Automatic Retry Tick"
