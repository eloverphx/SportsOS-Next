# Milestone 36.10.2 — Next.js 16 / PostCSS Security Migration

## Scope

This increment performs the controlled dashboard migration from Next.js 15.5.24 to
Next.js 16.3.4 after an isolated compatibility probe succeeded.

The migration is intentionally narrow:

- update only the dashboard Next.js direct dependency to exactly `16.3.4`;
- accept the lockfile changes required by that Next.js upgrade;
- preserve React and React DOM at `19.2.0`;
- preserve the repository Node 22 runtime baseline;
- migrate the deprecated `middleware.ts` file convention to `proxy.ts`;
- rename the exported `middleware` function to `proxy`;
- preserve the existing security-header and matcher behavior;
- verify that the resolved PostCSS version is newer than the vulnerable
  `<=8.5.22` audit range.

No tournament, ESP, game-engine, scoring, roster, streaming, authentication, or
other product feature behavior is intentionally changed by this milestone.

## Security objective

The previous Next.js 15 dependency tree resolved PostCSS 8.4.31. The security
inventory identified a high-severity PostCSS advisory affecting versions through
8.5.22.

Next.js 16.3.4 resolves PostCSS 8.5.23 in the tested dependency tree, removing
that advisory without using `npm audit fix --force` or an unsupported package
override.

## Next.js 16 network boundary convention

Next.js 16 deprecates the `middleware.ts` convention in favor of `proxy.ts`.
The dashboard security-header logic remains unchanged; only the framework file
and exported function naming are migrated:

- `apps/dashboard/middleware.ts` -> `apps/dashboard/proxy.ts`
- `middleware()` -> `proxy()`

## Validation

The required release gate for this increment is:

```bash
npm run typecheck
npm test
npm run build
docker compose up -d --build api dashboard
npm run test:e2e:docker
npm audit
```

Expected audit outcome: the Next.js/PostCSS high-severity finding is absent. The
previously documented MinIO/query-string/decode-uri-component residual finding
may remain until its upstream dependency chain has a compatible remediation.

Do not use `npm audit fix --force`.
