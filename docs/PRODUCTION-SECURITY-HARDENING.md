# SportsOS Production Security Hardening

## Milestone 26.1 — Credential rotation readiness

Milestone 26 begins production credential and security hardening.

The first step is a read-only credential-rotation readiness gate.

Rotation targets:

```text
JWT_SECRET
MYSQL_PASSWORD
MINIO_SECRET_KEY
```

API:

```text
GET /broadcast-coordinator/credential-rotation-readiness
```

Required prerequisites include:

- rollback / restore readiness
- database and persistent-data readiness
- current JWT, MySQL, and MinIO secrets configured
- dedicated non-root MySQL user
- current MinIO access key present
- persistent SportsOS data mounted at `/app/data`

The readiness endpoint does not change credentials.

## Milestone 26 sequence

26.1 Credential rotation readiness  
26.2 JWT secret rotation workflow  
26.3 MySQL credential rotation workflow  
26.4 MinIO credential rotation workflow  
26.5 Secret-file / environment-source hardening  
26.6 Session/token invalidation readiness  
26.7 Security headers / transport hardening  
26.8 Security telemetry / operator visibility  
26.9 Security regression / attack-surface tests  
26.10 Production security acceptance / closeout

## Milestone 26.2 — JWT secret rotation workflow

SportsOS now includes an explicit JWT rotation helper:

```text
scripts/rotate-jwt-secret.sh
```

Default execution is **preflight only**:

```bash
bash scripts/rotate-jwt-secret.sh
```

No secret is changed unless the operator explicitly runs:

```bash
SPORTSOS_APPLY_ROTATION=1 \
  bash scripts/rotate-jwt-secret.sh
```

The rotation workflow:

1. verifies `.env` and `JWT_SECRET`
2. creates a timestamped backup of the environment file
3. generates a cryptographically random replacement secret
4. updates `JWT_SECRET` without printing the new value
5. recreates API/dashboard containers
6. waits for API health
7. runs the release smoke test

Security effect:

```text
existing JWT sessions/tokens become invalid
users must sign in again
```

The new secret is not printed to stdout or written into logs by the rotation helper.

## Milestone 26.3 — MySQL credential rotation workflow

SportsOS now includes a coordinated MySQL application-password rotation helper:

```text
scripts/rotate-mysql-password.sh
```

Default behavior is preflight-only:

```bash
bash scripts/rotate-mysql-password.sh
```

The preflight verifies the current application credential, MySQL root/admin credential, dedicated non-root application user, and required environment settings.

Rotation requires explicit opt-in:

```bash
SPORTSOS_APPLY_ROTATION=1 \
  bash scripts/rotate-mysql-password.sh
```

The workflow updates the actual MySQL account first, updates `.env` with the exact same value, verifies the new credential before restarting the API, and rolls back the database password plus `.env` if immediate verification fails.

The new password is never printed.

## Milestone 26.3 — MySQL credential rotation workflow

SportsOS now includes a coordinated MySQL application-password rotation helper:

```text
scripts/rotate-mysql-password.sh
```

Default behavior is preflight-only:

```bash
bash scripts/rotate-mysql-password.sh
```

The preflight verifies the current application credential, MySQL root/admin credential, dedicated non-root application user, and required environment settings.

Rotation requires explicit opt-in:

```bash
SPORTSOS_APPLY_ROTATION=1 \
  bash scripts/rotate-mysql-password.sh
```

The workflow updates the actual MySQL account first, updates `.env` with the exact same value, verifies the new credential before restarting the API, and rolls back the database password plus `.env` if immediate verification fails.

The new password is never printed.

## Milestone 26.4 — MinIO credential rotation workflow

SportsOS now includes a coordinated MinIO credential rotation helper:

```text
scripts/rotate-minio-credentials.sh
```

Default execution is preflight-only:

```bash
bash scripts/rotate-minio-credentials.sh
```

The preflight validates the current MinIO access/secret pair using `mc` from inside the MinIO container.

Rotation requires explicit opt-in:

```bash
SPORTSOS_APPLY_ROTATION=1 \
  bash scripts/rotate-minio-credentials.sh
```

The workflow:

1. validates current MinIO credentials
2. backs up `.env`
3. generates a strong replacement secret
4. updates `.env` without printing the value
5. recreates MinIO with the new root credential
6. waits for MinIO health
7. verifies the new credential with `mc`
8. recreates the API
9. waits for API health
10. restores dependent services
11. runs readiness diagnostics

The new secret is never printed.

## Milestone 26.5 — Secret file / environment source hardening

SportsOS now validates how deployment secrets are sourced.

API:

```text
GET /broadcast-coordinator/secret-source-hardening
```

Host audit:

```text
scripts/secret-source-audit.sh
```

Checks include:

- `.env` exists
- `.env` permissions are `600`
- `.env` is covered by `.gitignore`
- `.env` is not tracked by git
- no alternate environment source files are present
- key secret variables are not duplicated in other repository files

Alternate files that currently block readiness:

```text
.env.local
.env.production
.env.development
.env.override
```

Milestone 26.5 does not modify or print secret values.

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

## Milestone 26.7 — Security headers / transport hardening

SportsOS now applies a production security-header baseline at the API layer.

Headers include:

```text
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: no-referrer
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Resource-Policy: same-origin
Permissions-Policy: camera=(), microphone=(), geolocation=()
```

In production, SportsOS also sends:

```text
Strict-Transport-Security: max-age=31536000; includeSubDomains
```

HSTS is meaningful only when the public deployment is actually served over HTTPS. Local HTTP testing may still be used during development, but production ingress should terminate TLS before requests reach SportsOS.

Milestone 26.7 does not change CORS origins or authentication behavior.

## Milestone 26.8 — Security telemetry / operator visibility

SportsOS now exposes a consolidated security telemetry endpoint:

```text
GET /broadcast-coordinator/security-telemetry
```

and dashboard:

```text
/broadcast/security
```

The security gate consolidates credential rotation readiness, secret/environment validation, secret-source hardening, and session/token invalidation readiness.

The response includes `ready`, `sections`, and `blockers[]`.

The dashboard is read-only and does not rotate credentials, invalidate sessions, or modify security configuration.

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
