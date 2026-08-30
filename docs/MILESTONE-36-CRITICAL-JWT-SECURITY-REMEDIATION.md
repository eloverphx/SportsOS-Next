# Milestone 36.3 — Critical JWT Security Remediation

Milestone 36.3 addresses the two critical npm audit findings tied to `@fastify/jwt` and its transitive dependency `fast-jwt`.

## Scope

This increment intentionally changes only the JWT dependency family:

- `@fastify/jwt` 9.1.0 → 10.2.2
- transitive `fast-jwt` resolves to a non-vulnerable version at or above 6.2.4

The audit showed the old JWT dependency chain exposed multiple token-verification vulnerabilities, including claim-validation problems, cache confusion, denial-of-service conditions, and an authentication bypass condition.

Because the available fix requires an `@fastify/jwt` major-version upgrade, this dependency is isolated from the other security updates and receives focused authentication and authorization validation.

## Compatibility boundary

SportsOS already runs Fastify 5 and Node 22. `@fastify/jwt` 10.x is the current Fastify-5-era plugin line, so the framework generation does not need to change in this increment.

The application integration itself must still be validated. A major plugin version is never accepted based only on package-manager resolution.

## Excluded from this increment

Milestone 36.3 does not upgrade:

- Fastify
- `@fastify/rate-limit`
- `@fastify/swagger-ui`
- Next.js
- Playwright
- React
- MySQL
- Redis
- TypeScript
- GitHub Actions

Those remain separate remediation increments.

## Required validation

Focused:

```bash
npx vitest run \
  packages/core/test/dependency-security-jwt-36.3.test.ts \
  apps/api/test/auth-model.test.ts \
  apps/api/test/auth-response.test.ts \
  apps/api/test/authorization.test.ts
```

Then:

```bash
npm run typecheck
npm test
npm run build
```

If all local validation passes, rebuild the production-style containers and run Docker E2E:

```bash
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

Finally run:

```bash
npm audit
```

The expected result after 36.3 is that the two critical JWT findings are gone. Remaining high/moderate findings are handled in later focused increments.
