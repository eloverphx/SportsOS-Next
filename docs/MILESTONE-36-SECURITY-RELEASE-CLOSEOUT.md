# Milestone 36.12 — Security + Release Governance Closeout

Milestone 36 establishes the controlled security and release-governance
baseline for SportsOS-Next.

## Final dependency-security state

The validated Milestone 36 baseline includes:

- Node.js engine baseline: `>=22 <23`
- Next.js: `16.3.4`
- React / React DOM: `19.2.0`
- PostCSS resolved through Next.js: `8.5.23`
- Fastify: `5.12.3`
- `@fastify/jwt`: `10.2.2`
- `@fastify/swagger-ui`: `6.1.1`
- Playwright: `1.62.1`
- Vitest: `4.1.11`
- Sharp: `0.35.4`
- MinIO: `8.0.7`

Vitest 4.1.11 closes the August 2026 `@vitest/mocker` advisory detected during the final release preflight.

The final dependency audit baseline contains:

- 0 critical findings
- 0 high findings
- 4 moderate findings

The remaining moderate findings are limited to the previously documented
MinIO transitive dependency residual:

- `minio`
- `query-string`
- `decode-uri-component`
- `stream-json`

`npm audit fix --force` remains prohibited.

## GitHub Actions supply-chain policy

The CI workflow retains least-privilege `contents: read` permissions and the
full verification sequence:

1. reproducible `npm ci`
2. shared-package build
3. formatting
4. TypeScript validation
5. unit and contract tests
6. production build
7. Playwright browser installation
8. browser smoke tests

Milestone 36.12 pins the currently validated GitHub Actions v4 implementations
to immutable commit SHAs:

- `actions/checkout`:
  `11d5960a326750d5838078e36cf38b85af677262`
- `actions/setup-node`:
  `49933ea5288caeca8642d1e84afbd3f7d6820020`

Newer major GitHub Actions releases exist, but upgrading those majors is
intentionally deferred to a separate compatibility review instead of being
mixed into the final Milestone 36 closeout.

Dependabot continues to monitor the `github-actions` ecosystem weekly so
future action updates remain visible for review.

## Repository ruleset verification

Live GitHub verification on September 7, 2026 found one active repository
ruleset named `lock`.

The ruleset:

- targets all branches;
- prevents branch deletion;
- prevents non-fast-forward updates.

The ruleset does **not** currently require CI status checks or pull requests
before updates to `main`, and the current repository role can bypass the
ruleset.

Therefore SportsOS must not describe the repository as having mandatory
CI-gated branch protection. The release process relies on the documented
preflight, explicit CI verification, and release-tag discipline until stronger
GitHub rules are configured.

## Release-governance audit policy

The release-governance preflight remains non-mutating.

When `SPORTSOS_RUN_NPM_AUDIT=1` is enabled, the preflight now:

- rejects any high or critical audit finding;
- rejects dependency findings outside the documented MinIO residual package
  set;
- permits the documented moderate MinIO residual without treating it as an
  unreviewed failure;
- never runs `npm audit fix`.

This allows the accepted residual to remain explicit while still detecting
new dependency-security regressions.

## Milestone 36 release tag

The annotated tag `sportsos-m36-complete` must be created only after:

1. the M36.12 closeout changes are committed;
2. the commit is pushed to `main`;
3. GitHub CI is green for that exact commit;
4. the local worktree is clean;
5. the release-governance preflight passes against the exact synchronized
   commit.

The tag must be annotated and pushed explicitly. The M36.12 automation does
not create, push, or rewrite release tags.

## Post-M36 direction

Tournament and ESP work remain preserved but frozen.

The next product-development phase can pivot to the streaming foundation:
accounts, media ownership, games, players, recordings, stream sessions,
permissions, authoritative scorekeeper event timestamps, and later
event-to-video clip generation.

AI-derived replay and highlight features must remain downstream of
authoritative game events and must not invent scoring or player events.
