#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-26.9-security-regression-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

TEST_API="apps/api/test/security-regression-26.9.test.ts"
TEST_CORE="packages/core/test/security-attack-surface-26.9.test.ts"
SCRIPT="scripts/security-regression-check.sh"
DOC="docs/PRODUCTION-SECURITY-HARDENING.md"

for required in \
  ".git" \
  "apps/api/src/plugins/securityHeaders.ts" \
  "apps/api/src/services/secretEnvironmentValidation.ts" \
  "apps/api/src/services/secretSourceHardening.ts" \
  "apps/api/src/services/sessionInvalidationReadiness.ts" \
  "apps/api/src/services/securityTelemetry.ts" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$TEST_API" "$TEST_CORE" "$SCRIPT" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST_API")" "$(dirname "$TEST_CORE")" "$(dirname "$SCRIPT")"

cat > "$TEST_API" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";

import {
  buildApp,
} from "../src/app";

describe("Milestone 26.9 API security regression", () => {
  it("returns baseline security headers on health response", async () => {
    const app =
      await buildApp();

    const response =
      await app.inject({
        method:
          "GET",
        url:
          "/health",
      });

    expect(
      response.headers[
        "x-content-type-options"
      ],
    ).toBe(
      "nosniff",
    );

    expect(
      response.headers[
        "x-frame-options"
      ],
    ).toBe(
      "DENY",
    );

    expect(
      response.headers[
        "referrer-policy"
      ],
    ).toBe(
      "no-referrer",
    );

    expect(
      response.headers[
        "permissions-policy"
      ],
    ).toBe(
      "camera=(), microphone=(), geolocation=()",
    );

    await app.close();
  });

  it("does not expose powered-by style framework header", async () => {
    const app =
      await buildApp();

    const response =
      await app.inject({
        method:
          "GET",
        url:
          "/health",
      });

    expect(
      response.headers[
        "x-powered-by"
      ],
    ).toBeUndefined();

    await app.close();
  });

  it("keeps security telemetry read-only", async () => {
    const app =
      await buildApp();

    const post =
      await app.inject({
        method:
          "POST",
        url:
          "/broadcast-coordinator/security-telemetry",
      });

    expect(
      [
        404,
        405,
      ],
    ).toContain(
      post.statusCode,
    );

    await app.close();
  });
});
EOF

cat > "$TEST_CORE" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  validateSecretEnvironment,
} from "../../../apps/api/src/services/secretEnvironmentValidation";

import {
  evaluateSessionInvalidationReadiness,
} from "../../../apps/api/src/services/sessionInvalidationReadiness";

describe("Milestone 26.9 security attack-surface regression", () => {
  it("rejects weak production credentials",()=> {
    const result =
      validateSecretEnvironment({
        NODE_ENV:
          "production",
        JWT_SECRET:
          "short",
        MYSQL_PASSWORD:
          "short",
        MINIO_SECRET_KEY:
          "short",
        DASHBOARD_ORIGIN:
          "http://localhost:4000",
        PUBLIC_API_URL:
          "http://localhost:4001",
        MYSQL_USER:
          "sportsos",
        MINIO_ACCESS_KEY:
          "sportsos",
      });

    expect(
      result.ready,
    ).toBe(
      false,
    );
  });

  it("requires production runtime for token invalidation readiness",()=> {
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

  it("keeps security dashboard read-only",()=> {
    const page =
      fs.readFileSync(
        new URL(
          "../../../apps/dashboard/app/broadcast/security/page.tsx",
          import.meta.url,
        ),
        "utf8",
      );

    expect(page).not.toContain(
      'method: "POST"',
    );

    expect(page).not.toContain(
      'method: "PUT"',
    );

    expect(page).not.toContain(
      'method: "DELETE"',
    );
  });

  it("keeps deployment dashboard read-only",()=> {
    const page =
      fs.readFileSync(
        new URL(
          "../../../apps/dashboard/app/broadcast/deployment/page.tsx",
          import.meta.url,
        ),
        "utf8",
      );

    expect(page).not.toContain(
      'method: "POST"',
    );

    expect(page).not.toContain(
      'method: "DELETE"',
    );
  });

  it("does not track .env in repository",()=> {
    const gitignore =
      fs.readFileSync(
        new URL(
          "../../../.gitignore",
          import.meta.url,
        ),
        "utf8",
      );

    expect(
      gitignore.includes(
        ".env",
      ),
    ).toBe(
      true,
    );
  });
});
EOF

cat > "$SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
API_URL="${SPORTSOS_API_URL:-http://127.0.0.1:4001}"

cd "$ROOT"

echo "============================================================"
echo " SportsOS Security Regression Check"
echo "============================================================"

failures=0

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1"
  failures=$((failures + 1))
}

headers="$(
  node - "$API_URL" <<'NODE'
const base = process.argv[2];

fetch(`${base}/health`)
  .then((response) => {
    for (
      const [
        key,
        value,
      ]
      of response.headers
    ) {
      console.log(
        `${key}:${value}`,
      );
    }

    process.exit(
      response.ok
        ? 0
        : 1,
    );
  })
  .catch(() => process.exit(1));
NODE
)"

for expected in \
  "x-content-type-options:nosniff" \
  "x-frame-options:DENY" \
  "referrer-policy:no-referrer" \
  "permissions-policy:camera=(), microphone=(), geolocation=()"
do
  if grep -Fqi "$expected" <<< "$headers"; then
    pass "$expected"
  else
    fail "$expected"
  fi
done

status="$(
  node - "$API_URL" <<'NODE'
const base = process.argv[2];

fetch(
  `${base}/broadcast-coordinator/security-telemetry`,
  {
    method:
      "POST",
  },
)
  .then(
    (response) =>
      console.log(
        response.status,
      ),
  )
  .catch(() => {
    console.log(
      "000",
    );
  });
NODE
)"

if [[ "$status" == "404" || "$status" == "405" ]]; then
  pass "security telemetry rejects POST"
else
  fail "security telemetry POST returned ${status}"
fi

if git check-ignore -q .env; then
  pass ".env ignored"
else
  fail ".env not ignored"
fi

if [[ -z "$(git ls-files --error-unmatch .env 2>/dev/null || true)" ]]; then
  pass ".env untracked"
else
  fail ".env tracked"
fi

echo
echo "============================================================"

if (( failures > 0 )); then
  echo "Security regression check FAILED: ${failures} check(s) failed."
  exit 1
fi

echo "Security regression check PASSED."
EOF

chmod +x "$SCRIPT"

cat >> "$DOC" <<'EOF'

## Milestone 26.9 — Security regression / attack-surface tests

SportsOS now includes security-specific regression coverage.

Automated checks cover:

- baseline API security headers
- no `X-Powered-By` API framework disclosure
- security telemetry remains read-only
- weak production credentials remain rejected
- session invalidation requires production runtime
- security/deployment dashboards expose no write actions
- `.env` remains ignored and untracked

Host regression command:

```text
scripts/security-regression-check.sh
```

Run:

```bash
bash scripts/security-regression-check.sh
```

This milestone adds defensive validation only and does not perform intrusive network scanning or destructive security testing.
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 26.9 installed"
echo "============================================================"
echo "Added:"
echo "  - API security regression tests"
echo "  - attack-surface regression tests"
echo "  - security header runtime check"
echo "  - read-only endpoint enforcement check"
echo "  - env tracking regression check"
echo "  - host security regression script"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  bash scripts/security-regression-check.sh"
echo "  bash scripts/release-smoke-test.sh"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 26.10 - Production Security Acceptance / Closeout"
