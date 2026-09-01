# Milestone 36.7 — fast-uri and nanoid Security Remediation

Milestone 36.7 remediates the remaining non-Next high-severity transitive
findings identified after the Playwright security update.

## Scope

The affected packages are transitive dependencies. They are not added as
direct SportsOS dependencies.

The existing parent ranges already permit patched releases:

- `fast-uri` 3.x parents permit a release at or above `3.1.5`
- `fast-uri` 4.x parent permits a release at or above `4.1.2`
- PostCSS parent ranges permit `nanoid` at or above `3.3.18`

The installer uses a package-lock-only targeted npm update, rejects unrelated
lockfile churn, and then synchronizes node_modules to the accepted lockfile.

## Preserved baseline

This increment preserves:

- `@playwright/test 1.62.1`
- Next.js `15.5.24`
- `@fastify/jwt 10.2.2`
- `@fastify/swagger-ui 6.1.1`

The Next.js 15 PostCSS/Sharp residual findings and the separate MinIO advisory
chain are intentionally outside this increment.

## Validation

Focused regression:

```bash
npx vitest run packages/core/test/dependency-security-fast-uri-nanoid-36.7.test.ts
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

Do not run `npm audit fix` or `npm audit fix --force`.
