#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-25.10-release-closeout-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

TEST="packages/core/test/deployment-release-readiness-25.10.test.ts"
REPORT="docs/MILESTONE-25-DEPLOYMENT-RELEASE-READINESS-ACCEPTANCE.md"
DOC="docs/BROADCAST-RELEASE-READINESS.md"

for required in \
  ".git" \
  "apps/api/src/services/broadcastReleaseReadiness.ts" \
  "apps/api/src/services/deploymentManifest.ts" \
  "apps/api/src/services/dataMigrationReadiness.ts" \
  "apps/api/src/services/secretEnvironmentValidation.ts" \
  "apps/api/src/services/rollbackRestoreReadiness.ts" \
  "apps/dashboard/app/broadcast/deployment/page.tsx" \
  "scripts/release-smoke-test.sh" \
  "scripts/release-readiness-diagnostics.sh" \
  "scripts/release-rollback-preflight.sh" \
  "scripts/generate-release-artifact.sh" \
  "scripts/staging-production-rehearsal.sh" \
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
const fs=require("fs");

const checks = [
  ["25.1 release readiness", "apps/api/src/services/broadcastReleaseReadiness.ts", "evaluateBroadcastReleaseReadiness"],
  ["25.2 deployment manifest", "apps/api/src/services/deploymentManifest.ts", "createDeploymentManifest"],
  ["25.3 data migration readiness", "apps/api/src/services/dataMigrationReadiness.ts", "evaluateDataMigrationReadiness"],
  ["25.4 secret validation", "apps/api/src/services/secretEnvironmentValidation.ts", "validateSecretEnvironment"],
  ["25.5 smoke test", "scripts/release-smoke-test.sh", "SportsOS Release Smoke Test"],
  ["25.6 rollback readiness", "apps/api/src/services/rollbackRestoreReadiness.ts", "evaluateRollbackRestoreReadiness"],
  ["25.6 rollback preflight", "scripts/release-rollback-preflight.sh", "Rollback preflight"],
  ["25.7 release artifact", "scripts/generate-release-artifact.sh", "SportsOS Release Artifact"],
  ["25.8 deployment dashboard", "apps/dashboard/app/broadcast/deployment/page.tsx", "Deployment Preflight"],
  ["25.9 rehearsal", "scripts/staging-production-rehearsal.sh", "Staging -> Production Acceptance Rehearsal"],
];

for (const [name, file, needle] of checks) {
  const source = fs.readFileSync(file, "utf8");
  if (!source.includes(needle)) {
    throw new Error(`Milestone 25 prerequisite missing: ${name}`);
  }
}

const rehearsal = fs.readFileSync("scripts/staging-production-rehearsal.sh","utf8");
if (rehearsal.includes("bash -lc")) {
  throw new Error("25.9 login-shell regression remains; replace bash -lc with bash -c before closeout.");
}
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 25.10 deployment / release readiness acceptance", () => {
  const readiness =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastReleaseReadiness.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const secrets =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/secretEnvironmentValidation.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const smoke =
    fs.readFileSync(
      new URL(
        "../../../scripts/release-smoke-test.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const rollback =
    fs.readFileSync(
      new URL(
        "../../../scripts/release-rollback-preflight.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const artifact =
    fs.readFileSync(
      new URL(
        "../../../scripts/generate-release-artifact.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const rehearsal =
    fs.readFileSync(
      new URL(
        "../../../scripts/staging-production-rehearsal.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const dashboard =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/deployment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("retains runtime release readiness",()=> {
    expect(readiness).toContain("runtime:node-env");
    expect(readiness).toContain("runtime:data-dir");
    expect(readiness).toContain("runtime:dashboard-origin");
    expect(readiness).toContain("runtime:public-api-url");
  });

  it("retains strict production secret quality gates",()=> {
    expect(secrets).toContain("jwt:quality");
    expect(secrets).toContain("mysql-password:quality");
    expect(secrets).toContain("minio-password:quality");
  });

  it("retains release smoke test",()=> {
    expect(smoke).toContain("API /health");
    expect(smoke).toContain("Dashboard reachable");
    expect(smoke).toContain("Release readiness");
    expect(smoke).toContain("Data migration readiness");
  });

  it("retains rollback and restore preflight",()=> {
    expect(rollback).toContain("git rev-parse --verify HEAD");
    expect(rollback).toContain("Backup directory writable");
    expect(rollback).toContain("does not perform a rollback");
  });

  it("retains release artifact generation",()=> {
    expect(artifact).toContain("SportsOS Release Artifact");
    expect(artifact).toContain("git log -15");
  });

  it("retains deployment preflight dashboard",()=> {
    expect(dashboard).toContain("Deployment Preflight");
    expect(dashboard).toContain("Deployment Gate");
    expect(dashboard).toContain("READY");
    expect(dashboard).toContain("BLOCKED");
  });

  it("retains full staging-to-production rehearsal",()=> {
    expect(rehearsal).toContain("npm run typecheck && npm test");
    expect(rehearsal).toContain("docker compose up -d --build api dashboard");
    expect(rehearsal).toContain("release-smoke-test.sh");
    expect(rehearsal).toContain("npm run test:e2e:docker");
    expect(rehearsal).toContain("generate-release-artifact.sh");
  });

  it("does not regress into login-shell cwd bug",()=> {
    expect(rehearsal).not.toContain("bash -lc");
    expect(rehearsal).toContain("bash -c");
  });

  it("keeps staging-only secret override narrowly scoped",()=> {
    expect(rehearsal).toContain("SPORTSOS_ALLOW_SECRET_GATE_FAILURE");
    expect(rehearsal).toContain("jwt:quality");
    expect(rehearsal).toContain("mysql-password:quality");
    expect(rehearsal).toContain("minio-password:quality");
  });
});
EOF

cat > "$REPORT" <<'EOF'
# SportsOS Milestone 25 — Deployment / Release Readiness Acceptance

Milestone 25 completes the first deployment and release-readiness pass for SportsOS.

## Accepted capabilities

- runtime release-readiness validation
- deployment manifest / version metadata
- database and persistent-data migration readiness
- strict secret / environment validation
- reusable release smoke-test bundle
- rollback / restore readiness and host preflight
- reproducible release artifact / changelog generation
- deployment preflight dashboard
- staging-to-production acceptance rehearsal

## Current staging exception

The staging environment may temporarily use:

```text
SPORTSOS_ALLOW_SECRET_GATE_FAILURE=1
```

only when the remaining release blockers are exactly:

```text
jwt:quality
mysql-password:quality
minio-password:quality
```

This exception is for rehearsal only.

It does not make the deployment production-ready.

## Production rule

A production deployment must run the rehearsal without the secret-gate override:

```bash
bash scripts/staging-production-rehearsal.sh
```

All readiness checks must pass.

## Final production acceptance gate

```text
npm run typecheck
npm test
docker compose up -d --build api dashboard
bash scripts/release-readiness-diagnostics.sh
bash scripts/release-smoke-test.sh
bash scripts/release-rollback-preflight.sh
npm run test:e2e:docker
bash scripts/generate-release-artifact.sh
```

## Safety invariants

- readiness APIs are read-only
- deployment dashboard is read-only
- rollback preflight does not perform rollback
- release artifact generation does not alter application state
- staging secret override is narrowly scoped and prohibited for production acceptance
EOF

cat >> "$DOC" <<'EOF'

## Milestone 25.10 — Deployment / release readiness closeout

Milestone 25 acceptance is documented in:

```text
docs/MILESTONE-25-DEPLOYMENT-RELEASE-READINESS-ACCEPTANCE.md
```

Milestone 25 is complete when typecheck, unit tests, deployment build/start, readiness diagnostics, smoke testing, rollback preflight, Docker E2E, and release artifact generation have all been exercised successfully.

The current staging-only secret-quality exception does not count as full production acceptance. Production remains blocked until JWT, MySQL, and MinIO secrets satisfy the production validation gate.
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 25.10 installed"
echo "============================================================"
echo "Added:"
echo "  - Milestone 25 prerequisite validation"
echo "  - release readiness acceptance suite"
echo "  - 25.9 login-shell regression guard"
echo "  - staging secret-exception documentation"
echo "  - production release acceptance document"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Acceptance run:"
echo "  npm run typecheck && npm test"
echo "  docker compose up -d --build api dashboard"
echo "  bash scripts/release-readiness-diagnostics.sh"
echo "  bash scripts/release-smoke-test.sh"
echo "  bash scripts/release-rollback-preflight.sh"
echo "  npm run test:e2e:docker"
echo "  bash scripts/generate-release-artifact.sh"
echo
echo "For the CURRENT staging environment only:"
echo "  SPORTSOS_ALLOW_SECRET_GATE_FAILURE=1 bash scripts/staging-production-rehearsal.sh"
echo
echo "If acceptance is green:"
echo '  git add -A'
echo '  git commit -m "feat(release): complete milestone 25 deployment readiness"'
echo '  git tag -a sportsos-m25-complete -m "SportsOS Milestone 25 complete"'
echo
echo "Next after commit/tag:"
echo "  Milestone 26 - Production Security / Credential Hardening"
