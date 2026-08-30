#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-26.10-security-closeout-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

TEST="packages/core/test/production-security-acceptance-26.10.test.ts"
REPORT="docs/MILESTONE-26-PRODUCTION-SECURITY-ACCEPTANCE.md"
DOC="docs/PRODUCTION-SECURITY-HARDENING.md"

for required in \
  ".git" \
  "apps/api/src/plugins/securityHeaders.ts" \
  "apps/api/src/services/credentialRotationReadiness.ts" \
  "apps/api/src/services/secretEnvironmentValidation.ts" \
  "apps/api/src/services/secretSourceHardening.ts" \
  "apps/api/src/services/sessionInvalidationReadiness.ts" \
  "apps/api/src/services/securityTelemetry.ts" \
  "apps/dashboard/app/broadcast/security/page.tsx" \
  "scripts/rotate-jwt-secret.sh" \
  "scripts/rotate-mysql-password.sh" \
  "scripts/rotate-minio-credentials.sh" \
  "scripts/secret-source-audit.sh" \
  "scripts/security-regression-check.sh" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$TEST" "$REPORT" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")" "$(dirname "$REPORT")"

node <<'NODE'
const fs = require("fs");

const checks = [
  ["26.1 credential rotation readiness", "apps/api/src/services/credentialRotationReadiness.ts", "evaluateCredentialRotationReadiness"],
  ["26.2 JWT rotation", "scripts/rotate-jwt-secret.sh", "JWT rotation preflight PASSED"],
  ["26.3 MySQL rotation", "scripts/rotate-mysql-password.sh", "MySQL self-service rotation preflight PASSED"],
  ["26.4 MinIO rotation", "scripts/rotate-minio-credentials.sh", "MinIO credential rotation preflight PASSED"],
  ["26.5 secret source audit", "scripts/secret-source-audit.sh", "Secret source audit PASSED"],
  ["26.6 session invalidation", "apps/api/src/services/sessionInvalidationReadiness.ts", "jwt-secret-rotation"],
  ["26.7 security headers", "apps/api/src/plugins/securityHeaders.ts", "x-frame-options"],
  ["26.8 security telemetry", "apps/api/src/services/securityTelemetry.ts", "evaluateSecurityTelemetry"],
  ["26.9 security regression", "scripts/security-regression-check.sh", "Security regression check PASSED"],
];

for (const [name, file, needle] of checks) {
  const source = fs.readFileSync(file, "utf8");

  if (!source.includes(needle)) {
    throw new Error(`Milestone 26 prerequisite missing: ${name}`);
  }
}

const headers = fs.readFileSync(
  "apps/api/src/plugins/securityHeaders.ts",
  "utf8",
);

if (!headers.includes('"x-frame-options"')) {
  throw new Error("X-Frame-Options hardening missing.");
}
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 26.10 production security acceptance", () => {
  const headers =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/plugins/securityHeaders.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const telemetry =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/securityTelemetry.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const audit =
    fs.readFileSync(
      new URL(
        "../../../scripts/secret-source-audit.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const regression =
    fs.readFileSync(
      new URL(
        "../../../scripts/security-regression-check.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const jwt =
    fs.readFileSync(
      new URL(
        "../../../scripts/rotate-jwt-secret.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const mysql =
    fs.readFileSync(
      new URL(
        "../../../scripts/rotate-mysql-password.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const minio =
    fs.readFileSync(
      new URL(
        "../../../scripts/rotate-minio-credentials.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("retains transport/security header baseline",()=> {
    expect(headers).toContain(
      "x-content-type-options",
    );

    expect(headers).toContain(
      "x-frame-options",
    );

    expect(headers).toContain(
      "strict-transport-security",
    );

    expect(headers).toContain(
      "permissions-policy",
    );
  });

  it("retains consolidated operator security telemetry",()=> {
    expect(telemetry).toContain(
      "evaluateSecurityTelemetry",
    );

    expect(telemetry).toContain(
      "blockers",
    );
  });

  it("retains secret-source hardening",()=> {
    expect(audit).toContain(
      ".env permissions = 600",
    );

    expect(audit).toContain(
      ".env untracked",
    );
  });

  it("retains security regression runtime checks",()=> {
    expect(regression).toContain(
      "x-content-type-options:nosniff",
    );

    expect(regression).toContain(
      "x-frame-options:DENY",
    );

    expect(regression).toContain(
      "security telemetry rejects POST",
    );
  });

  it("retains safe credential rotation workflows",()=> {
    expect(jwt).toContain(
      "SPORTSOS_APPLY_ROTATION",
    );

    expect(mysql).toContain(
      "SPORTSOS_APPLY_ROTATION",
    );

    expect(minio).toContain(
      "SPORTSOS_APPLY_ROTATION",
    );
  });

  it("does not print generated credential values",()=> {
    expect(jwt).not.toContain(
      'echo "$NEW_SECRET"',
    );

    expect(mysql).not.toContain(
      'echo "$NEW_PASSWORD"',
    );

    expect(minio).not.toContain(
      'echo "$NEW_SECRET"',
    );
  });
});
EOF

cat > "$REPORT" <<'EOF'
# SportsOS Milestone 26 — Production Security Acceptance

Milestone 26 establishes the first production security-hardening baseline for SportsOS.

## Accepted capabilities

- credential rotation readiness
- JWT secret rotation workflow
- MySQL application credential rotation workflow
- MinIO credential rotation workflow
- `.env` permission and source hardening
- session / token invalidation readiness
- API security headers / transport baseline
- consolidated security telemetry
- security regression / attack-surface tests

## Production security gate

The security surface is considered fully production-ready only when:

```text
GET /broadcast-coordinator/security-telemetry
```

returns:

```text
ready: true
blockers: []
```

and:

```bash
bash scripts/secret-source-audit.sh
bash scripts/security-regression-check.sh
bash scripts/release-smoke-test.sh
npm run test:e2e:docker
```

all pass.

## Known credential-quality gate

If the current environment still uses legacy weak credentials, these checks remain blockers:

```text
jwt:quality
mysql-password:quality
minio-password:quality
```

These are security-policy failures, not runtime-health failures.

They must be resolved before declaring full production security acceptance.

## Security invariants

- `.env` must remain mode `600`
- `.env` must remain ignored and untracked
- local backup directories must remain ignored and untracked
- credential rotation helpers default to preflight only
- generated secrets are not printed
- security/deployment dashboards remain read-only
- security telemetry remains read-only
- API security headers remain globally enforced
- session invalidation strategy remains explicit and testable
EOF

cat >> "$DOC" <<'EOF'

## Milestone 26.10 — Production security acceptance / closeout

Milestone 26 acceptance is documented in:

```text
docs/MILESTONE-26-PRODUCTION-SECURITY-ACCEPTANCE.md
```

Final acceptance commands:

```bash
npm run typecheck && npm test
docker compose up -d --build api dashboard
bash scripts/secret-source-audit.sh
bash scripts/security-regression-check.sh
bash scripts/release-readiness-diagnostics.sh
bash scripts/release-smoke-test.sh
npm run test:e2e:docker
```

Full production security acceptance requires the security telemetry endpoint to report no blockers.

Legacy credential-quality failures remain explicit release blockers until the associated credentials are rotated successfully.
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 26.10 installed"
echo "============================================================"
echo "Added:"
echo "  - Milestone 26 security acceptance suite"
echo "  - security closeout document"
echo "  - rotation workflow acceptance guards"
echo "  - security header acceptance guards"
echo "  - secret source acceptance guards"
echo "  - regression/telemetry acceptance guards"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Final acceptance run:"
echo "  npm run typecheck && npm test"
echo "  docker compose up -d --build api dashboard"
echo "  bash scripts/secret-source-audit.sh"
echo "  bash scripts/security-regression-check.sh"
echo "  bash scripts/release-readiness-diagnostics.sh"
echo "  bash scripts/release-smoke-test.sh"
echo "  npm run test:e2e:docker"
echo
echo "Inspect security gate:"
echo "  curl -fsS http://127.0.0.1:4001/broadcast-coordinator/security-telemetry"
echo
echo "If everything is green:"
echo '  git add -A'
echo '  git commit -m "feat(security): complete milestone 26 production hardening"'
echo '  git tag -a sportsos-m26-complete -m "SportsOS Milestone 26 complete"'
echo
echo "Next after closeout:"
echo "  Milestone 27 - Production Deployment / External HTTPS Readiness"
