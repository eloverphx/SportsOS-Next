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
