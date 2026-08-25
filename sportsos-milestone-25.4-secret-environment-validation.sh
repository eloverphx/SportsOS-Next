#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-25.4-secret-env-validation-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/secretEnvironmentValidation.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/secret-environment-validation-25.4.test.ts"
DOC="docs/BROADCAST-RELEASE-READINESS.md"

for required in \
  ".git" \
  "apps/api/src/services/broadcastReleaseReadiness.ts" \
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
export type SecretEnvironmentCheck = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

export type SecretEnvironmentValidationResult = {
  ready: boolean;
  checks: SecretEnvironmentCheck[];
};

function isHttpUrl(
  value: string | undefined,
): boolean {
  if (!value) {
    return false;
  }

  try {
    const url =
      new URL(
        value,
      );

    return (
      url.protocol ===
        "http:" ||
      url.protocol ===
        "https:"
    );
  } catch {
    return false;
  }
}

function isStrongEnoughSecret(
  value: string | undefined,
  minLength: number,
): boolean {
  if (!value) {
    return false;
  }

  const trimmed =
    value.trim();

  if (
    trimmed.length <
    minLength
  ) {
    return false;
  }

  const lowered =
    trimmed.toLowerCase();

  const forbidden = [
    "password",
    "changeme",
    "change-me",
    "secret",
    "default",
    "replace-with",
  ];

  return !forbidden.some(
    (token) =>
      lowered.includes(
        token,
      ),
  );
}

export function validateSecretEnvironment(
  env:
    Record<string, string | undefined>,
): SecretEnvironmentValidationResult {
  const checks:
    SecretEnvironmentCheck[] =
    [];

  checks.push({
    id:
      "node-env:production",
    ok:
      env.NODE_ENV ===
      "production",
    required:
      true,
    message:
      env.NODE_ENV ===
      "production"
        ? "NODE_ENV is production."
        : "NODE_ENV must be production.",
  });

  checks.push({
    id:
      "jwt:quality",
    ok:
      isStrongEnoughSecret(
        env.JWT_SECRET,
        32,
      ),
    required:
      true,
    message:
      "JWT secret must be at least 32 characters and must not use an obvious placeholder/default value.",
  });

  checks.push({
    id:
      "mysql-password:quality",
    ok:
      isStrongEnoughSecret(
        env.MYSQL_PASSWORD,
        12,
      ),
    required:
      true,
    message:
      "MySQL password must be at least 12 characters and must not use an obvious placeholder/default value.",
  });

  checks.push({
    id:
      "minio-password:quality",
    ok:
      isStrongEnoughSecret(
        env.MINIO_ROOT_PASSWORD,
        12,
      ),
    required:
      true,
    message:
      "MinIO root password must be at least 12 characters and must not use an obvious placeholder/default value.",
  });

  checks.push({
    id:
      "dashboard-url:valid",
    ok:
      isHttpUrl(
        env.SPORTSOS_DASHBOARD_URL,
      ),
    required:
      true,
    message:
      "SPORTSOS_DASHBOARD_URL must be a valid http(s) URL.",
  });

  checks.push({
    id:
      "api-url:valid",
    ok:
      isHttpUrl(
        env.SPORTSOS_API_URL,
      ),
    required:
      true,
    message:
      "SPORTSOS_API_URL must be a valid http(s) URL.",
  });

  checks.push({
    id:
      "mysql-user:not-root",
    ok:
      Boolean(
        env.MYSQL_USER &&
        env.MYSQL_USER.trim() &&
        env.MYSQL_USER.trim() !==
          "root",
      ),
    required:
      true,
    message:
      "SportsOS should use a dedicated MySQL user instead of root.",
  });

  checks.push({
    id:
      "minio-user:configured",
    ok:
      Boolean(
        env.MINIO_ROOT_USER?.trim(),
      ),
    required:
      true,
    message:
      "MINIO_ROOT_USER must be configured.",
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
    checks,
  };
}
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const importLine=`import {
  validateSecretEnvironment,
} from "../services/secretEnvironmentValidation.js";`;

if(!s.includes("validateSecretEnvironment")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/secret-environment-validation"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/data-migration-readiness",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("25.3 data-migration-readiness route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/secret-environment-validation",
    async () => {
      return {
        success: true,
        data:
          validateSecretEnvironment(
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

## Milestone 25.4 — Secret / environment validation

SportsOS now performs stricter production secret and environment validation.

API:

```text
GET /broadcast-coordinator/secret-environment-validation
```

Required checks include:

- `NODE_ENV=production`
- JWT secret minimum length and placeholder rejection
- MySQL password minimum length and placeholder rejection
- MinIO password minimum length and placeholder rejection
- valid SportsOS dashboard URL
- valid SportsOS API URL
- dedicated non-root MySQL user
- configured MinIO user

This endpoint never returns secret values. It only reports pass/fail checks and messages.

The validation is read-only and does not modify environment variables, secrets, containers, or deployment files.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  validateSecretEnvironment,
} from "../../../apps/api/src/services/secretEnvironmentValidation";

describe("Milestone 25.4 secret / environment validation", () => {
  const goodEnv = {
    NODE_ENV:
      "production",
    JWT_SECRET:
      "this-is-a-real-jwt-key-with-32-plus-characters",
    MYSQL_PASSWORD:
      "mysql-prod-credential-123",
    MINIO_ROOT_PASSWORD:
      "minio-prod-credential-123",
    SPORTSOS_DASHBOARD_URL:
      "http://192.168.5.3:4000",
    SPORTSOS_API_URL:
      "http://192.168.5.3:4001",
    MYSQL_USER:
      "sportsos",
    MINIO_ROOT_USER:
      "sportsos",
  };

  it("passes strong production environment",()=> {
    expect(
      validateSecretEnvironment(
        goodEnv,
      ).ready,
    ).toBe(
      true,
    );
  });

  it("rejects development NODE_ENV",()=> {
    expect(
      validateSecretEnvironment({
        ...goodEnv,
        NODE_ENV:
          "development",
      }).ready,
    ).toBe(
      false,
    );
  });

  it("rejects weak or placeholder JWT secret",()=> {
    const result=
      validateSecretEnvironment({
        ...goodEnv,
        JWT_SECRET:
          "replace-with-at-least-32-random-characters",
      });

    expect(
      result.ready,
    ).toBe(
      false,
    );
  });

  it("rejects root mysql user",()=> {
    expect(
      validateSecretEnvironment({
        ...goodEnv,
        MYSQL_USER:
          "root",
      }).ready,
    ).toBe(
      false,
    );
  });

  it("rejects malformed API URL",()=> {
    expect(
      validateSecretEnvironment({
        ...goodEnv,
        SPORTSOS_API_URL:
          "not-a-url",
      }).ready,
    ).toBe(
      false,
    );
  });

  it("does not expose secret values in check messages",()=> {
    const result=
      validateSecretEnvironment(
        goodEnv,
      );

    const serialized=
      JSON.stringify(
        result,
      );

    expect(
      serialized,
    ).not.toContain(
      goodEnv.JWT_SECRET,
    );

    expect(
      serialized,
    ).not.toContain(
      goodEnv.MYSQL_PASSWORD,
    );

    expect(
      serialized,
    ).not.toContain(
      goodEnv.MINIO_ROOT_PASSWORD,
    );
  });

  it("provides secret-environment validation API",()=> {
    const route=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/secret-environment-validation"',
    );

    expect(route).toContain(
      "validateSecretEnvironment",
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 25.4 installed"
echo "============================================================"
echo "Added:"
echo "  - production NODE_ENV validation"
echo "  - JWT secret quality validation"
echo "  - MySQL credential validation"
echo "  - MinIO credential validation"
echo "  - API/dashboard URL validation"
echo "  - non-root MySQL user validation"
echo "  - no secret values returned"
echo "  - secret-environment validation API"
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
echo "  Milestone 25.5 - Health / Smoke-Test Command Bundle"
