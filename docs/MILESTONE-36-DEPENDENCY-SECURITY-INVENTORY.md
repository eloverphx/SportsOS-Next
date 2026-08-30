# Milestone 36.2 — Dependency Security Inventory

Milestone 36.2 establishes a reproducible, read-only dependency inventory before any package upgrade is accepted.

## GitHub snapshot reviewed before this increment

The open Dependabot queue was reviewed after Milestone 36.1 completed.

Current high-priority security-relevant updates include:

- `fastify` 5.10.0 → 5.12.1. The target release is a security release covering GHSA-w2qp-rph6-63g4 and GHSA-3m5p-2c4r-xxw2.
- `@fastify/rate-limit` 11.1.0 → 11.2.0. The target release is a security release covering GHSA-grpc-p53c-r64v.
- `@fastify/jwt` 9.1.0 → 10.2.2. The target release contains security fixes, but this is a major-version jump and must be treated as an independent compatibility migration.

Other open major-version candidates include Next.js 15 → Next.js 16, TypeScript 5 → TypeScript 7, `@types/node` 22 → 26, and GitHub Actions major upgrades. Those are not bundled into the initial security remediation.

Dependabot PR #5 currently groups 15 npm minor/patch updates. Do not merge PR #5 wholesale. It includes security-relevant packages mixed with unrelated tooling, UI, test, and database updates.

## Policy

Milestone 36 uses one security-focused dependency set at a time.

The preferred first remediation candidate after this inventory is:

1. `fastify` within major 5.
2. `@fastify/rate-limit` within major 11.

They are same-major security releases and can be validated together against the API/security/rate-limit regression suite.

`@fastify/jwt` is security-relevant but crosses a major version boundary. It receives a separate compatibility increment after the same-major Fastify security work.

Next.js 16 and TypeScript 7 remain deferred until security-critical same-major remediation is complete.

## Inventory command

Run:

```bash
bash scripts/dependency-security-inventory.sh
```

The command performs:

- `npm audit --json`
- `npm outdated --json`
- severity and version-jump classification
- package.json/package-lock.json hash verification before and after inventory

Reports are written under `.game-engine-backups/` and are intentionally not tracked.

The command does not run `npm install`, `npm update`, `npm audit fix`, Git merge, Git push, or release tagging.

## Exit behavior

`npm audit` commonly returns non-zero when vulnerabilities are present. That is treated as inventory information rather than automatic remediation.

`npm outdated` commonly returns exit code 1 when outdated packages exist. That is also inventory information.

The inventory script itself fails only when prerequisites are missing or package metadata is unexpectedly mutated.

## Next increment

After the 36.2 inventory output is reviewed, Milestone 36.3 should remediate the same-major Fastify security baseline with focused tests and full Docker E2E validation before any major-version dependency migration.
