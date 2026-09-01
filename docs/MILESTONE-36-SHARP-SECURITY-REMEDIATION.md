# Milestone 36.8 — Sharp Security Remediation

Milestone 36.8 remediates the high-severity Sharp advisory while keeping the
SportsOS dashboard on the supported Next.js 15.5.24 baseline.

## Scope

Next.js 15.5.24 permits the Sharp 0.35 line. The focused transitive update
moves Sharp from the vulnerable 0.34 line to a patched 0.35 release.

Sharp 0.35 carries a broader optional platform package matrix than the prior
resolution. Therefore the lockfile legitimately adds or changes
`@img/sharp-*`, `@img/sharp-libvips-*`, and `@emnapi/runtime` entries. These
entries are part of Sharp's runtime/platform dependency graph and are not
independent SportsOS dependency upgrades.

Sharp is not added as a direct SportsOS dependency.

## Preserved baseline

This increment preserves:

- Next.js `15.5.24`
- `@playwright/test 1.62.1`
- `@fastify/jwt 10.2.2`
- `@fastify/swagger-ui 6.1.1`
- `fast-uri 3.1.6`
- nested `fast-uri 4.1.3`
- `nanoid 3.3.18`

The remaining PostCSS finding is tied to the Next.js 15 dependency tree and
must not be forced into a Next.js 16 upgrade without a dedicated migration.

The separate MinIO/query-string/decode-uri-component moderate advisory chain
is also outside this increment.

## Validation

Focused regression:

```bash
npx vitest run packages/core/test/dependency-security-sharp-36.8.test.ts
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
