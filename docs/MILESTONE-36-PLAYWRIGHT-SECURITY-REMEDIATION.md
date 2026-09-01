# Milestone 36.6 — Playwright Security Remediation

Milestone 36.6 performs a focused Playwright security update.

## Change

The root development dependency is updated from `@playwright/test 1.55.0` to
`@playwright/test 1.62.1`. The lockfile must also resolve `playwright 1.62.1`
and `playwright-core 1.62.1`.

This addresses the Playwright advisory identified during the Milestone 36
dependency security inventory without mixing the update with unrelated
package churn.

## Docker E2E compatibility

`scripts/test-e2e-docker.sh` derives `PLAYWRIGHT_VERSION` from the installed
`@playwright/test` package and launches the matching Microsoft Playwright
`noble` image. Docker E2E is therefore a mandatory release gate.

## Preserved baseline

This increment does not perform a Next.js 16 migration. It preserves Next.js
`15.5.24`, React `19.2.0`, React DOM `19.2.0`, `@fastify/jwt 10.2.2`, and
`@fastify/swagger-ui 6.1.1`.

Remaining audit findings such as `fast-uri`, `nanoid`, and the documented
Next.js 15 PostCSS/Sharp residual risk are handled separately.

## Validation

Focused regression:

```bash
npx vitest run packages/core/test/dependency-security-playwright-36.6.test.ts
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
