#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-26.6-session-invalidation-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/sessionInvalidationReadiness.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/session-token-invalidation-26.6.test.ts"
DOC="docs/PRODUCTION-SECURITY-HARDENING.md"

for required in \
  ".git" \
  "apps/api/src/services/secretEnvironmentValidation.ts" \
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
export type SessionInvalidationCheck = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

export type SessionInvalidationReadinessResult = {
  ready: boolean;
  strategy: "jwt-secret-rotation";
  impact: {
    activeJwtTokensInvalidated: boolean;
    usersMustSignInAgain: boolean;
    serverSessionStoreRequired: boolean;
  };
  checks: SessionInvalidationCheck[];
};

export function evaluateSessionInvalidationReadiness(
  env: Record<string, string | undefined>,
): SessionInvalidationReadinessResult {
  const checks: SessionInvalidationCheck[] = [];

  const jwt =
    env.JWT_SECRET?.trim() ??
    "";

  checks.push({
    id:
      "jwt:configured",
    ok:
      jwt.length > 0,
    required:
      true,
    message:
      jwt
        ? "JWT secret is configured."
        : "JWT secret is missing.",
  });

  checks.push({
    id:
      "jwt:minimum-length",
    ok:
      jwt.length >=
      32,
    required:
      true,
    message:
      "JWT secret must be at least 32 characters before session invalidation by rotation is considered production-ready.",
  });

  checks.push({
    id:
      "runtime:production",
    ok:
      env.NODE_ENV ===
      "production",
    required:
      true,
    message:
      env.NODE_ENV === "production"
        ? "Runtime is production."
        : "Runtime must be production.",
  });

  return {
    ready:
      checks
        .filter(
          (check) =>
            check.required,
        )
        .every(
          (check) =>
            check.ok,
        ),
    strategy:
      "jwt-secret-rotation",
    impact: {
      activeJwtTokensInvalidated:
        true,
      usersMustSignInAgain:
        true,
      serverSessionStoreRequired:
        false,
    },
    checks,
  };
}
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const importLine=`import {
  evaluateSessionInvalidationReadiness,
} from "../services/sessionInvalidationReadiness.js";`;

if(!s.includes("evaluateSessionInvalidationReadiness")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/session-invalidation-readiness"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/secret-source-hardening",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("26.5 secret-source-hardening route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/session-invalidation-readiness",
    async () => {
      return {
        success: true,
        data:
          evaluateSessionInvalidationReadiness(
            process.env,
          ),
      };
    },
  );

`;

  s=s.slice(0,i)+route+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 26.6 — Session / token invalidation readiness

SportsOS now exposes session invalidation readiness:

```text
GET /broadcast-coordinator/session-invalidation-readiness
```

Current strategy:

```text
jwt-secret-rotation
```

Expected impact:

```text
active JWT tokens become invalid
users must sign in again
no server-side session store is required for invalidation
```

Production readiness requires:

- `JWT_SECRET` configured
- JWT secret length at least 32 characters
- `NODE_ENV=production`

Milestone 26.6 is read-only and does not invalidate sessions by itself.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";

import {
  evaluateSessionInvalidationReadiness,
} from "../../../apps/api/src/services/sessionInvalidationReadiness";

describe("Milestone 26.6 session / token invalidation readiness", () => {
  it("passes with strong production JWT configuration",()=> {
    const result=
      evaluateSessionInvalidationReadiness({
        NODE_ENV:
          "production",
        JWT_SECRET:
          "abcdefghijklmnopqrstuvwxyz0123456789-strong",
      });

    expect(
      result.ready,
    ).toBe(
      true,
    );

    expect(
      result.strategy,
    ).toBe(
      "jwt-secret-rotation",
    );
  });

  it("documents expected invalidation impact",()=> {
    const result=
      evaluateSessionInvalidationReadiness({
        NODE_ENV:
          "production",
        JWT_SECRET:
          "abcdefghijklmnopqrstuvwxyz0123456789-strong",
      });

    expect(
      result.impact.activeJwtTokensInvalidated,
    ).toBe(
      true,
    );

    expect(
      result.impact.usersMustSignInAgain,
    ).toBe(
      true,
    );

    expect(
      result.impact.serverSessionStoreRequired,
    ).toBe(
      false,
    );
  });

  it("fails short JWT secret",()=> {
    expect(
      evaluateSessionInvalidationReadiness({
        NODE_ENV:
          "production",
        JWT_SECRET:
          "too-short",
      }).ready,
    ).toBe(
      false,
    );
  });

  it("fails non-production runtime",()=> {
    expect(
      evaluateSessionInvalidationReadiness({
        NODE_ENV:
          "development",
        JWT_SECRET:
          "abcdefghijklmnopqrstuvwxyz0123456789-strong",
      }).ready,
    ).toBe(
      false,
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 26.6 installed"
echo "============================================================"
echo "Added:"
echo "  - session/token invalidation readiness evaluator"
echo "  - JWT rotation invalidation strategy"
echo "  - user sign-in impact documentation"
echo "  - production readiness checks"
echo "  - read-only readiness API"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  curl -fsS http://127.0.0.1:4001/broadcast-coordinator/session-invalidation-readiness"
echo
echo "Next after green:"
echo "  Milestone 26.7 - Security Headers / Transport Hardening"
