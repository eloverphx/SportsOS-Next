# Milestone 36 — GitHub / Release Governance + Dependency Security Baseline

Milestone 36 hardens the path from a validated SportsOS repository state to a controlled GitHub release while establishing a dependency-security baseline that can be remediated incrementally.

## M36.1 — Release Governance Baseline

M36.1 intentionally does not upgrade dependencies. It first makes the release assumptions executable and testable so later dependency changes can be reviewed against a stable baseline.

The new `scripts/release-governance-preflight.sh` verifies:

- the canonical SportsOS repository root
- annotated release-tag lineage from `sportsos-m35-complete`
- release execution on `main`
- local `HEAD` synchronization with `origin/main`
- clean worktree/index by default
- expected GitHub `origin`
- no tracked real `.env`, `.game-engine-backups/`, or runtime `data/`
- CI retains least-privilege `contents: read`
- CI retains lint, typecheck, test, build, and browser smoke-test gates
- Dependabot continues to monitor npm and GitHub Actions
- the pull-request template requires explicit release/dependency governance review
- the Node/npm/lockfile baseline remains structurally valid

### Dependency audit mode

The preflight does not silently mutate dependencies and never runs `npm audit fix`.

A network-backed npm vulnerability audit is opt-in during the baseline phase:

```bash
SPORTSOS_RUN_NPM_AUDIT=1 bash scripts/release-governance-preflight.sh
```

Once M36 dependency remediation is complete, a later increment can promote the audit from observed baseline to a blocking security gate without hiding existing findings.

### Authority boundaries

The preflight is read-only with respect to Git history and dependency resolution. It does not push, merge, create tags, rewrite package locks, or change installed package versions.

## Validation

Focused validation:

```bash
bash -n scripts/release-governance-preflight.sh && \
npx vitest run packages/core/test/release-governance-preflight-36.1.test.ts && \
npm run typecheck && npm test
```

Full project gate after focused validation:

```bash
npm run typecheck && \
npm test && \
npm run build && \
docker compose up -d --build api dashboard && \
npm run test:e2e:docker
```

## Next increment

M36.2 should use the established baseline to inventory and remediate security-relevant dependency updates separately from unrelated major-version migrations.
