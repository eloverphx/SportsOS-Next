# SportsOS Broadcast Release Readiness

## Milestone 25.1 — Release-readiness foundation

Milestone 25 begins deployment and release hardening.

The release-readiness evaluator verifies that a production deployment has the
minimum required configuration before SportsOS is considered deployable.

Checks include:

- required environment variables
- API port 4001
- dashboard port 4000
- persistent API data mount
- API healthcheck
- dashboard dependency on healthy API
- API production runtime image
- dashboard production runtime image
- non-placeholder JWT secret

API:

```text
GET /broadcast-coordinator/release-readiness
```

The endpoint returns:

```text
ready
checks[]
```

Release readiness is read-only. It does not modify Docker, environment files,
secrets, containers, or broadcast state.

## Milestone 25 sequence

25.1 Release-readiness foundation  
25.2 Deployment manifest / version metadata  
25.3 Database and persistent-data migration readiness  
25.4 Secret and environment validation  
25.5 Health / smoke-test command bundle  
25.6 Rollback and restore readiness  
25.7 Release artifact / changelog generation  
25.8 Preflight deployment dashboard  
25.9 Staging-to-production acceptance rehearsal  
25.10 Deployment / release readiness closeout

## Milestone 25.2 — Deployment manifest / version metadata

SportsOS now exposes a deployment manifest for release identification and auditing.

API:

```text
GET /broadcast-coordinator/deployment-manifest
```

The manifest includes:

```text
generatedAt

repository:
  commit
  branch
  tag
  dirty

versions:
  root
  api
  dashboard
  node

runtime:
  NODE_ENV
  PORT
  HOST
  SPORTSOS_DATA_DIR
```

Git metadata is best-effort. If the production image does not contain `.git`, repository fields return `null` rather than failing the API.

The manifest is read-only and does not alter release state or deployment configuration.

## Milestone 25.3 — Database / persistent data migration readiness

SportsOS now checks deployment-time readiness for both MySQL and JSON-backed persistent stores.

API:

```text
GET /broadcast-coordinator/data-migration-readiness
```

Required checks:

```text
MySQL reachable
SPORTSOS_DATA_DIR configured
persistent data directory readable/writable
existing JSON stores parse successfully
```

A missing JSON store is not considered a failure because a new deployment may legitimately create it on first use.

Existing stores that are present but unreadable or invalid JSON fail readiness.

Checked persistent stores include operator notes, recovery snapshots, broadcast session profiles, stream destination profiles, encoder state/audit, go-live state/audit, and coordinator state/audit.

This endpoint does not mutate database schema or rewrite existing persistent stores.

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

## Milestone 25.5 — Health / smoke-test command bundle

SportsOS now includes a reusable deployment smoke test:

```text
scripts/release-smoke-test.sh
```

The bundle checks:

- API container health
- dashboard container state
- API `/health`
- dashboard HTTP reachability
- release readiness
- data migration readiness
- secret/environment validation

Run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash scripts/release-smoke-test.sh
```

Optional overrides:

```text
SPORTSOS_ROOT
SPORTSOS_API_URL
SPORTSOS_DASHBOARD_URL
```

The smoke test exits non-zero when any required check fails, making it suitable for deployment gates and CI/manual release verification.

## Milestone 25.6 — Rollback / restore readiness

SportsOS now includes rollback and restore preflight validation.

API:

```text
GET /broadcast-coordinator/rollback-restore-readiness
```

Required checks include:

- compose file present
- release smoke-test script present
- persistent data directory configured/readable
- backup directory configured/readable/writable

Default backup directory:

```text
/app/data/backups
```

Host-side rollback preflight:

```text
scripts/release-rollback-preflight.sh
```

Run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash scripts/release-rollback-preflight.sh
```

The preflight also verifies the current git commit can be resolved.

Milestone 25.6 does **not** automatically change git revisions, restore backups, stop containers, or modify production state.

## Milestone 25.7 — Release artifact / changelog generation

SportsOS now includes a reproducible release artifact generator:

```text
scripts/generate-release-artifact.sh
```

The generated Markdown artifact includes:

- package version
- full and short git commit
- branch
- exact tag when present
- dirty-working-tree status
- recent git commit history
- Milestone 23 acceptance summary
- Milestone 24 resilience acceptance summary
- deployment verification commands

Default output directory:

```text
release-artifacts/
```

Optional override:

```text
SPORTSOS_RELEASE_ARTIFACT_DIR
```

Run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash scripts/generate-release-artifact.sh
```

The generator is read-only with respect to application and deployment state. It only writes the release artifact file.

## Milestone 25.8 — Preflight deployment dashboard

SportsOS now includes a deployment preflight dashboard:

```text
/broadcast/deployment
```

The page consolidates release readiness, data migration readiness, secret/environment validation, rollback/restore readiness, and deployment manifest identity.

The overall gate is:

```text
READY
BLOCKED
```

`READY` requires every required readiness section to pass.

The dashboard is read-only and does not rotate secrets, run migrations, perform rollback, or change container state.

## Milestone 25.9 — Staging-to-production acceptance rehearsal

SportsOS now includes a single staging-to-production rehearsal command:

```text
scripts/staging-production-rehearsal.sh
```

The rehearsal executes, in order:

1. typecheck and unit tests
2. API/dashboard production build and startup
3. container status
4. release-readiness diagnostics
5. release smoke test
6. Docker E2E tests
7. release artifact generation

Run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash scripts/staging-production-rehearsal.sh
```

For development/staging only, known credential-strength blockers may be tolerated while every other release gate remains mandatory:

```bash
SPORTSOS_ALLOW_SECRET_GATE_FAILURE=1 \
  bash scripts/staging-production-rehearsal.sh
```

That override permits continuation only when the remaining secret validation failures are exactly:

```text
jwt:quality
mysql-password:quality
minio-password:quality
```

It does not bypass API health, migration readiness, dashboard reachability, E2E tests, or any other release check.

The rehearsal does not deploy to production.

## Milestone 25.10 — Deployment / release readiness closeout

Milestone 25 acceptance is documented in:

```text
docs/MILESTONE-25-DEPLOYMENT-RELEASE-READINESS-ACCEPTANCE.md
```

Milestone 25 is complete when typecheck, unit tests, deployment build/start, readiness diagnostics, smoke testing, rollback preflight, Docker E2E, and release artifact generation have all been exercised successfully.

The current staging-only secret-quality exception does not count as full production acceptance. Production remains blocked until JWT, MySQL, and MinIO secrets satisfy the production validation gate.
