# Milestone 36.9.2 — MinIO Residual Risk Documentation

Milestone 36.9.2 records the current MinIO advisory chain as a known,
upstream-blocked residual risk and adds regression guards against unsafe
automated remediation.

## Current dependency chain

The SportsOS API currently resolves:

- `minio 8.0.7`
- `query-string 7.1.3`
- `decode-uri-component 0.2.2`

`minio 8.0.7` depends on `query-string ^7.1.3`.

`query-string 7.1.3` depends on `decode-uri-component ^0.2.2`.

The security advisory is fixed in `decode-uri-component 0.5.0`, which is
outside the dependency range accepted by `query-string 7.1.3`.

## Compatibility probe result

Milestone 36.9.1 tested an isolated candidate tree that forced
`decode-uri-component 0.5.0` underneath `query-string 7.1.3`.

That candidate failed during normal query-string parsing with:

```text
TypeError: decodeComponent is not a function
```

Therefore the override is not compatible with the current MinIO dependency
chain and must not be applied to SportsOS.

## Rejected automated fixes

`npm audit fix --force` proposes changing MinIO to `7.0.26`.

SportsOS currently uses `minio 8.0.7`, so this is a backwards major-version
move and must not be accepted as an automated security remediation.

SportsOS must also not add a root override for:

- `decode-uri-component 0.5.0`
- `query-string`
- `minio`

without a dedicated compatibility migration and full validation.

## Residual risk status

The MinIO/query-string/decode-uri-component advisory remains open in the npm
audit inventory.

This is a documented residual dependency risk, not an ignored failure.
Remediation should occur when one of the following becomes available:

1. a MinIO release that no longer depends on the vulnerable query-string path;
2. a compatible query-string release within MinIO's supported dependency tree;
3. an explicitly tested MinIO migration that removes the affected chain.

## Separation from other security work

The remaining high-severity PostCSS finding is tied to the current Next.js 15
dependency tree. It requires a separate Next.js 16 migration and must not be
mixed with the MinIO residual-risk work.

## Validation

Focused regression:

```bash
npx vitest run packages/core/test/dependency-security-minio-residual-risk-36.9.2.test.ts
```

Full repository gate:

```bash
npm run typecheck && npm test && npm run build
```

Docker E2E:

```bash
docker compose up -d --build api dashboard && npm run test:e2e:docker
```

Security inventory:

```bash
npm audit
```

Expected audit residual after this documentation increment:

- MinIO/query-string/decode-uri-component moderate advisory chain remains
- Next.js/PostCSS high advisory remains

Do not run `npm audit fix --force`.
