# Milestone 36.4 — Fastify Swagger UI / Static Security Remediation

Milestone 36.4 removes the high-severity `@fastify/static` advisory chain reported through `@fastify/swagger-ui`.

## Scope

This increment updates only `@fastify/swagger-ui` to `6.1.1` and the transitive `@fastify/static` version selected by npm. The installer verifies that the resolved `@fastify/static` version is greater than the vulnerable `<=10.1.1` range reported by `npm audit`.

No broad `npm audit fix`, `npm update`, grouped Dependabot merge, Next.js update, Playwright update, or unrelated dependency churn is performed.

Milestone 36.3 is preserved: `@fastify/jwt` remains exactly `10.2.2`.

## Validation

Focused validation:

```bash
npx vitest run \
  packages/core/test/dependency-security-swagger-static-36.4.test.ts \
  apps/api/test/platform.test.ts
```

Full validation:

```bash
npm run typecheck && \
npm test && \
npm run build
```

Docker E2E:

```bash
docker compose up -d --build api dashboard && \
npm run test:e2e:docker
```

Security verification:

```bash
npm audit
```

Expected result: the `@fastify/static` / `@fastify/swagger-ui` finding disappears and the JWT critical findings remain absent.

Do not run `npm audit fix` or `npm audit fix --force`.
