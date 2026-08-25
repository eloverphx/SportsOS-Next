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
