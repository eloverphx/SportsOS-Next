#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-24.7-retry-budget-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/broadcastResilienceRetryBudget.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/broadcast-resilience-retry-budget-24.7.test.ts"
DOC="docs/BROADCAST-RESILIENCE.md"

for required in \
  ".git" \
  "apps/api/src/services/streamDestinationFailurePolicy.ts" \
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
import {
  type StreamDestinationFailureDecision,
} from "./streamDestinationFailurePolicy.js";

export type ResilienceRetryBudgetState =
  | "AVAILABLE"
  | "SCHEDULED"
  | "EXHAUSTED"
  | "REFUSED";

export type ResilienceRetryBudgetInput = {
  attempts: number;
  maxAttempts?: number;
  baseDelayMs?: number;
  maxDelayMs?: number;
  failure:
    StreamDestinationFailureDecision;
  nowMs?: number;
};

export type ResilienceRetryBudgetDecision = {
  state:
    ResilienceRetryBudgetState;
  retryAllowed:
    boolean;
  attempts:
    number;
  maxAttempts:
    number;
  delayMs:
    number | null;
  nextRetryAt:
    string | null;
  reason:
    string;
};

const DEFAULT_MAX_ATTEMPTS =
  5;

const DEFAULT_BASE_DELAY_MS =
  5_000;

const DEFAULT_MAX_DELAY_MS =
  120_000;

export function evaluateResilienceRetryBudget(
  input: ResilienceRetryBudgetInput,
): ResilienceRetryBudgetDecision {
  const attempts =
    Math.max(
      0,
      Math.floor(
        input.attempts,
      ),
    );

  const maxAttempts =
    Math.max(
      1,
      Math.min(
        Math.floor(
          input.maxAttempts ??
          DEFAULT_MAX_ATTEMPTS,
        ),
        20,
      ),
    );

  const baseDelayMs =
    Math.max(
      1_000,
      Math.min(
        Math.floor(
          input.baseDelayMs ??
          DEFAULT_BASE_DELAY_MS,
        ),
        60_000,
      ),
    );

  const maxDelayMs =
    Math.max(
      baseDelayMs,
      Math.min(
        Math.floor(
          input.maxDelayMs ??
          DEFAULT_MAX_DELAY_MS,
        ),
        600_000,
      ),
    );

  const nowMs =
    input.nowMs ??
    Date.now();

  if (
    !input.failure.retryable ||
    input.failure.action ===
      "OPERATOR_REVIEW"
  ) {
    return {
      state:
        "REFUSED",
      retryAllowed:
        false,
      attempts,
      maxAttempts,
      delayMs:
        null,
      nextRetryAt:
        null,
      reason:
        "Failure classification requires operator review.",
    };
  }

  if (
    attempts >=
    maxAttempts
  ) {
    return {
      state:
        "EXHAUSTED",
      retryAllowed:
        false,
      attempts,
      maxAttempts,
      delayMs:
        null,
      nextRetryAt:
        null,
      reason:
        "Resilience retry budget is exhausted.",
    };
  }

  const exponent =
    Math.max(
      0,
      attempts,
    );

  const delayMs =
    Math.min(
      maxDelayMs,
      baseDelayMs *
        2 ** exponent,
    );

  return {
    state:
      "SCHEDULED",
    retryAllowed:
      true,
    attempts,
    maxAttempts,
    delayMs,
    nextRetryAt:
      new Date(
        nowMs +
        delayMs,
      ).toISOString(),
    reason:
      input.failure.action ===
        "RETRY_WITH_BACKOFF"
        ? "Retry scheduled with exponential backoff."
        : "Retry scheduled within resilience retry budget.",
  };
}
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const importLine=`import {
  evaluateResilienceRetryBudget,
} from "../services/broadcastResilienceRetryBudget.js";`;

if(!s.includes("evaluateResilienceRetryBudget")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/:gameId/resilience-retry-budget"')) {
  const marker='  app.post(\n    "/broadcast-coordinator/:gameId/destination-failure/classify",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("24.6 destination failure route missing.");

  const route=`  app.post(
    "/broadcast-coordinator/:gameId/resilience-retry-budget",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          attempts?: number;
          maxAttempts?: number;
          baseDelayMs?: number;
          maxDelayMs?: number;
          failure?: {
            failureClass?: string;
            action?: string;
            retryable?: boolean;
            reason?: string;
          };
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      if (!body.failure) {
        return reply.code(400).send({
          success: false,
          error:
            "Failure classification is required.",
        });
      }

      const decision =
        evaluateResilienceRetryBudget({
          attempts:
            body.attempts ??
            0,
          maxAttempts:
            body.maxAttempts,
          baseDelayMs:
            body.baseDelayMs,
          maxDelayMs:
            body.maxDelayMs,
          failure: {
            failureClass:
              (body.failure.failureClass ??
                "UNKNOWN") as any,
            action:
              (body.failure.action ??
                "OPERATOR_REVIEW") as any,
            retryable:
              body.failure.retryable ===
              true,
            reason:
              body.failure.reason ??
              "Unspecified failure.",
          },
        });

      return {
        success: true,
        data: {
          gameId,
          decision,
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

## Milestone 24.7 — Resilience retry budgets / backoff policy

SportsOS now has a bounded resilience retry-budget policy for stream destination recovery.

Defaults:

```text
max attempts: 5
base delay:   5 seconds
max delay:    120 seconds
```

Hard bounds:

```text
max attempts: 1..20
base delay:   1..60 seconds
max delay:    up to 10 minutes
```

Backoff formula:

```text
delay = min(maxDelay, baseDelay * 2^attempts)
```

Retry-budget states:

```text
AVAILABLE
SCHEDULED
EXHAUSTED
REFUSED
```

Non-retryable or `OPERATOR_REVIEW` failures are refused immediately.

API:

```text
POST /broadcast-coordinator/:gameId/resilience-retry-budget
```

Milestone 24.7 calculates retry eligibility and timing only. It does not create a timer loop or execute retries automatically.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  evaluateResilienceRetryBudget,
} from "../../../apps/api/src/services/broadcastResilienceRetryBudget";

describe("Milestone 24.7 resilience retry budgets / backoff policy", () => {
  const retryableFailure = {
    failureClass:
      "TRANSIENT_NETWORK" as const,
    action:
      "RETRY_ALLOWED" as const,
    retryable:
      true,
    reason:
      "Transient network failure detected.",
  };

  it("schedules retry within budget",()=> {
    const now=100_000;

    const result=
      evaluateResilienceRetryBudget({
        attempts:
          0,
        failure:
          retryableFailure,
        nowMs:
          now,
      });

    expect(
      result.state,
    ).toBe(
      "SCHEDULED",
    );

    expect(
      result.delayMs,
    ).toBe(
      5_000,
    );
  });

  it("uses exponential backoff",()=> {
    const result=
      evaluateResilienceRetryBudget({
        attempts:
          3,
        failure:
          retryableFailure,
      });

    expect(
      result.delayMs,
    ).toBe(
      40_000,
    );
  });

  it("caps delay",()=> {
    const result=
      evaluateResilienceRetryBudget({
        attempts:
          10,
        maxAttempts:
          20,
        failure:
          retryableFailure,
      });

    expect(
      result.delayMs,
    ).toBe(
      120_000,
    );
  });

  it("exhausts budget",()=> {
    const result=
      evaluateResilienceRetryBudget({
        attempts:
          5,
        failure:
          retryableFailure,
      });

    expect(
      result.state,
    ).toBe(
      "EXHAUSTED",
    );

    expect(
      result.retryAllowed,
    ).toBe(
      false,
    );
  });

  it("refuses operator-review failures",()=> {
    const result=
      evaluateResilienceRetryBudget({
        attempts:
          0,
        failure: {
          failureClass:
            "AUTHENTICATION",
          action:
            "OPERATOR_REVIEW",
          retryable:
            false,
          reason:
            "Authentication failed.",
        },
      });

    expect(
      result.state,
    ).toBe(
      "REFUSED",
    );
  });

  it("bounds configuration",()=> {
    const result=
      evaluateResilienceRetryBudget({
        attempts:
          0,
        maxAttempts:
          99,
        baseDelayMs:
          1,
        maxDelayMs:
          999_999,
        failure:
          retryableFailure,
      });

    expect(
      result.maxAttempts,
    ).toBe(
      20,
    );

    expect(
      result.delayMs,
    ).toBe(
      1_000,
    );
  });

  it("provides retry-budget API",()=> {
    const route=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/:gameId/resilience-retry-budget"',
    );

    expect(route).toContain(
      "evaluateResilienceRetryBudget",
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 24.7 installed"
echo "============================================================"
echo "Added:"
echo "  - bounded resilience retry budgets"
echo "  - exponential backoff"
echo "  - max-delay cap"
echo "  - retry exhaustion"
echo "  - operator-review refusal"
echo "  - retry-budget API"
echo "  - no automatic timer/retry loop"
echo "  - Milestone 24.7 regression tests"
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
echo "  Milestone 24.8 - Resilience Telemetry / Operator Visibility"
