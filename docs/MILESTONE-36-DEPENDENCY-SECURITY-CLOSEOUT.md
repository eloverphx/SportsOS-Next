# Milestone 36.11.2 — Dependency Security Closeout

Milestone 36.11.2 records the dependency-security state after the controlled
Milestone 36 remediation work.

This document supplements, rather than replaces,
`MILESTONE-36-MINIO-RESIDUAL-RISK.md`. The earlier document remains historical
evidence of the state observed during Milestone 36.9.2.

## Remediated security findings

The following dependency findings have been remediated and validated:

- Next.js was migrated from 15.5.24 to exactly 16.3.4.
- The Next.js dependency tree now resolves patched PostCSS 8.5.23.
- The dashboard migrated from the deprecated `middleware.ts` convention to
  `proxy.ts`.
- Fastify was updated to exactly 5.12.3.
- The Fastify lockfile was synchronized and verified with clean `npm ci`.
- Earlier critical JWT findings were remediated with `@fastify/jwt 10.2.2`.
- Earlier Swagger UI/static dependency findings were remediated with
  `@fastify/swagger-ui 6.1.1`.
- Playwright was updated to the validated security baseline.

The current audit contains zero critical and zero high-severity findings.

## Current audit residual

After the Fastify remediation, the verified `npm audit` state is:

- 4 moderate findings
- 0 high findings
- 0 critical findings

The remaining findings originate from the MinIO dependency tree.

SportsOS currently resolves:

- `minio 8.0.7`
- `query-string 7.1.3`
- `decode-uri-component 0.2.2`
- a vulnerable `stream-json` version pulled transitively by MinIO

The two remaining vulnerable paths are therefore owned by the MinIO
transitive dependency tree:

1. `minio -> query-string -> decode-uri-component`
2. `minio -> stream-json`

They are not direct SportsOS application dependencies.

## Rejected unsafe remediation

`npm audit fix --force` is prohibited.

The current audit proposes installing an older MinIO 7.x release to address
the remaining dependency findings. SportsOS currently uses MinIO 8.0.7, so
that proposal is a backwards major-version change and is not an acceptable
automated security fix.

Milestone 36.9.1 also tested forcing `decode-uri-component 0.5.0` underneath
the existing query-string tree. That compatibility probe failed with:

```text
TypeError: decodeComponent is not a function
```

SportsOS must not add unsupported root overrides for:

- `minio`
- `query-string`
- `decode-uri-component`
- `stream-json`

## Residual-risk decision

The four remaining moderate findings are accepted as an upstream-blocked
dependency residual for the Milestone 36 release baseline.

This does not assert that the findings are harmless. It means:

- forced dependency substitution has either been rejected as a backwards
  major change or demonstrated to be incompatible;
- critical and high-severity findings have been remediated;
- the complete application release gate remains green.

The residual must be reconsidered when any of the following occurs:

1. MinIO publishes a compatible release that resolves the affected dependency
   lines;
2. MinIO changes its query-string or stream-json dependency constraints;
3. npm audit reports a higher severity for the residual;
4. SportsOS changes its object-storage client implementation;
5. a dedicated and fully tested migration becomes available.

## Validation requirements

Focused dependency regression:

```bash
cd packages/core
npx vitest run test/dependency-security-closeout-36.11.2.test.ts
```

Repository gates:

```bash
npm ci --no-audit --no-fund
npm run lint
npm run typecheck
npm test
npm run build
```

Security inventory:

```bash
npm audit
```

Expected security result:

- 0 critical
- 0 high
- 4 moderate, limited to the documented MinIO transitive dependency tree

Do not run `npm audit fix --force`.
