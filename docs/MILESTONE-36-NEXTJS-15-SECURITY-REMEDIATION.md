# Milestone 36.5 — Next.js 15 Security Remediation

Milestone 36.5 updates the SportsOS dashboard from Next.js `15.5.9` to
Next.js `15.5.24`, the current Next.js 15 backport available during this
security pass.

## Result

The update removes the direct Next.js advisory cluster reported against
`15.5.9`.

Dependency inspection confirms Next.js `15.5.24` still declares
`postcss: 8.4.31` and optional `sharp: ^0.34.3 || ^0.35.3`. The currently
resolved supported tree can therefore retain residual PostCSS and Sharp audit
findings.

## 36.5.1 finding

A root override experiment for PostCSS and Sharp caused npm to report the
Next.js dependency tree as invalid (`ELSPROBLEMS`). That override approach is
not accepted as the remediation.

Milestone 36.5.2 removes those overrides and restores a valid npm dependency
tree while retaining the Next.js `15.5.24` security update.

We will not hide residual audit findings behind an invalid dependency tree,
and we will not silently jump to Next.js 16. A Next.js 16 migration requires a
separate focused compatibility increment.

## Preserved baseline

- React and React DOM remain `19.2.0`.
- Playwright remains deferred to its own focused security increment.
- `@fastify/jwt` remains `10.2.2`.
- `@fastify/swagger-ui` remains `6.1.1`.

## Validation

Focused regression:

```bash
npx vitest run packages/core/test/dependency-security-nextjs-36.5.test.ts
```

Full repository:

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

Remaining PostCSS/Sharp findings are documented residual risk, not a claim
that those transitive vulnerabilities were remediated.

Do not run `npm audit fix` or `npm audit fix --force`.
