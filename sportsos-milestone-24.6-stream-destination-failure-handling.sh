#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-24.6-destination-failure-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/streamDestinationFailurePolicy.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/stream-destination-failure-policy-24.6.test.ts"
DOC="docs/BROADCAST-RESILIENCE.md"

for required in \
  ".git" \
  "apps/api/src/services/streamDestinationProfile.ts" \
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
export type StreamDestinationFailureClass =
  | "NONE"
  | "TRANSIENT_NETWORK"
  | "AUTHENTICATION"
  | "CONFIGURATION"
  | "REMOTE_REJECTED"
  | "RATE_LIMITED"
  | "TIMEOUT"
  | "UNKNOWN";

export type StreamDestinationFailureAction =
  | "NONE"
  | "RETRY_ALLOWED"
  | "RETRY_WITH_BACKOFF"
  | "OPERATOR_REVIEW";

export type StreamDestinationFailureInput = {
  ok: boolean;
  statusCode?: number | null;
  errorCode?: string | null;
  message?: string | null;
};

export type StreamDestinationFailureDecision = {
  failureClass:
    StreamDestinationFailureClass;
  action:
    StreamDestinationFailureAction;
  retryable:
    boolean;
  reason:
    string;
};

export function classifyStreamDestinationFailure(
  input: StreamDestinationFailureInput,
): StreamDestinationFailureDecision {
  if (input.ok) {
    return {
      failureClass:
        "NONE",
      action:
        "NONE",
      retryable:
        false,
      reason:
        "Stream destination is healthy.",
    };
  }

  const status =
    input.statusCode ??
    null;

  const code =
    (input.errorCode ??
      "")
      .trim()
      .toUpperCase();

  const message =
    (input.message ??
      "")
      .trim()
      .toLowerCase();

  if (
    status === 401 ||
    status === 403 ||
    message.includes(
      "unauthorized",
    ) ||
    message.includes(
      "forbidden",
    ) ||
    message.includes(
      "authentication",
    )
  ) {
    return {
      failureClass:
        "AUTHENTICATION",
      action:
        "OPERATOR_REVIEW",
      retryable:
        false,
      reason:
        "Destination authentication or authorization failed.",
    };
  }

  if (
    status === 429 ||
    message.includes(
      "rate limit",
    )
  ) {
    return {
      failureClass:
        "RATE_LIMITED",
      action:
        "RETRY_WITH_BACKOFF",
      retryable:
        true,
      reason:
        "Destination is rate limiting publish traffic.",
    };
  }

  if (
    status !== null &&
    status >= 500 &&
    status <= 599
  ) {
    return {
      failureClass:
        "REMOTE_REJECTED",
      action:
        "RETRY_WITH_BACKOFF",
      retryable:
        true,
      reason:
        "Destination service returned a server-side failure.",
    };
  }

  if (
    status !== null &&
    status >= 400 &&
    status <= 499
  ) {
    return {
      failureClass:
        "CONFIGURATION",
      action:
        "OPERATOR_REVIEW",
      retryable:
        false,
      reason:
        "Destination rejected the request due to configuration or request data.",
    };
  }

  if (
    code ===
      "ETIMEDOUT" ||
    code ===
      "UND_ERR_CONNECT_TIMEOUT" ||
    message.includes(
      "timeout",
    ) ||
    message.includes(
      "timed out",
    )
  ) {
    return {
      failureClass:
        "TIMEOUT",
      action:
        "RETRY_WITH_BACKOFF",
      retryable:
        true,
      reason:
        "Destination connection timed out.",
    };
  }

  if (
    [
      "ECONNRESET",
      "ECONNREFUSED",
      "ENETUNREACH",
      "EHOSTUNREACH",
      "EAI_AGAIN",
    ].includes(
      code,
    ) ||
    message.includes(
      "connection reset",
    ) ||
    message.includes(
      "connection refused",
    ) ||
    message.includes(
      "network",
    )
  ) {
    return {
      failureClass:
        "TRANSIENT_NETWORK",
      action:
        "RETRY_ALLOWED",
      retryable:
        true,
      reason:
        "Transient network failure detected.",
    };
  }

  return {
    failureClass:
      "UNKNOWN",
    action:
      "OPERATOR_REVIEW",
    retryable:
      false,
    reason:
      "Destination failure could not be classified safely.",
  };
}
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const importLine=`import {
  classifyStreamDestinationFailure,
} from "../services/streamDestinationFailurePolicy.js";`;

if(!s.includes("classifyStreamDestinationFailure")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/:gameId/destination-failure/classify"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/:gameId/resilience-supervisor",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("24.3 resilience supervisor route missing.");

  const route=`  app.post(
    "/broadcast-coordinator/:gameId/destination-failure/classify",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          ok?: boolean;
          statusCode?: number | null;
          errorCode?: string | null;
          message?: string | null;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const decision =
        classifyStreamDestinationFailure({
          ok:
            body.ok ===
            true,
          statusCode:
            body.statusCode ??
            null,
          errorCode:
            body.errorCode ??
            null,
          message:
            body.message ??
            null,
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

## Milestone 24.6 — Stream destination failure handling

SportsOS now classifies stream destination failures before they enter recovery or retry logic.

Failure classes:

```text
NONE
TRANSIENT_NETWORK
AUTHENTICATION
CONFIGURATION
REMOTE_REJECTED
RATE_LIMITED
TIMEOUT
UNKNOWN
```

Recommended actions:

```text
NONE
RETRY_ALLOWED
RETRY_WITH_BACKOFF
OPERATOR_REVIEW
```

Classification examples:

```text
401 / 403                -> AUTHENTICATION -> OPERATOR_REVIEW
429                      -> RATE_LIMITED -> RETRY_WITH_BACKOFF
5xx                      -> REMOTE_REJECTED -> RETRY_WITH_BACKOFF
other 4xx                -> CONFIGURATION -> OPERATOR_REVIEW
ETIMEDOUT                 -> TIMEOUT -> RETRY_WITH_BACKOFF
ECONNRESET / ECONNREFUSED -> TRANSIENT_NETWORK -> RETRY_ALLOWED
unknown failure           -> UNKNOWN -> OPERATOR_REVIEW
```

API:

```text
POST /broadcast-coordinator/:gameId/destination-failure/classify
```

Milestone 24.6 performs classification only. It does not directly restart the encoder, retry a publish target, modify credentials, or bypass the existing retry budget.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  classifyStreamDestinationFailure,
} from "../../../apps/api/src/services/streamDestinationFailurePolicy";

describe("Milestone 24.6 stream destination failure handling", () => {
  it("classifies healthy destination",()=> {
    expect(
      classifyStreamDestinationFailure({
        ok:
          true,
      }).failureClass,
    ).toBe(
      "NONE",
    );
  });

  it("classifies auth failures as operator review",()=> {
    const result=
      classifyStreamDestinationFailure({
        ok:
          false,
        statusCode:
          401,
      });

    expect(
      result.failureClass,
    ).toBe(
      "AUTHENTICATION",
    );

    expect(
      result.retryable,
    ).toBe(
      false,
    );
  });

  it("classifies rate limiting with backoff",()=> {
    const result=
      classifyStreamDestinationFailure({
        ok:
          false,
        statusCode:
          429,
      });

    expect(
      result.failureClass,
    ).toBe(
      "RATE_LIMITED",
    );

    expect(
      result.action,
    ).toBe(
      "RETRY_WITH_BACKOFF",
    );
  });

  it("classifies server failures as retryable",()=> {
    expect(
      classifyStreamDestinationFailure({
        ok:
          false,
        statusCode:
          503,
      }).retryable,
    ).toBe(
      true,
    );
  });

  it("classifies transient network failures",()=> {
    const result=
      classifyStreamDestinationFailure({
        ok:
          false,
        errorCode:
          "ECONNRESET",
      });

    expect(
      result.failureClass,
    ).toBe(
      "TRANSIENT_NETWORK",
    );

    expect(
      result.action,
    ).toBe(
      "RETRY_ALLOWED",
    );
  });

  it("classifies timeout separately",()=> {
    expect(
      classifyStreamDestinationFailure({
        ok:
          false,
        errorCode:
          "ETIMEDOUT",
      }).failureClass,
    ).toBe(
      "TIMEOUT",
    );
  });

  it("uses operator review for unknown failures",()=> {
    const result=
      classifyStreamDestinationFailure({
        ok:
          false,
        message:
          "something unusual",
      });

    expect(
      result.failureClass,
    ).toBe(
      "UNKNOWN",
    );

    expect(
      result.action,
    ).toBe(
      "OPERATOR_REVIEW",
    );
  });

  it("provides destination failure classification API",()=> {
    const route=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/:gameId/destination-failure/classify"',
    );

    expect(route).toContain(
      "classifyStreamDestinationFailure",
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 24.6 installed"
echo "============================================================"
echo "Added:"
echo "  - stream destination failure classifier"
echo "  - auth/config/network/timeout/rate-limit classification"
echo "  - retryability recommendations"
echo "  - safe operator-review fallback"
echo "  - destination-failure classification API"
echo "  - no direct retry or encoder action"
echo "  - Milestone 24.6 regression tests"
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
echo "  Milestone 24.7 - Resilience Retry Budgets / Backoff Policy"
