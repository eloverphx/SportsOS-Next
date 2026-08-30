## Summary

Describe what changed and why.

## Validation

- [ ] `npm run ci:verify`
- [ ] Relevant focused API tests were run
- [ ] Dashboard behavior was checked when UI code changed
- [ ] Realtime/scoring behavior has regression coverage when affected

## Safety checks

- [ ] No unrelated generated files, backups, or inventory files are included
- [ ] Database migrations are additive/backward-safe when applicable
- [ ] Scoring or clock behavior changes include matching automated tests
- [ ] Shared API/dashboard payload changes update `@sportsos/core` contracts
- [ ] No secrets or local-only credentials are committed

## Deployment notes

List migrations, environment changes, rebuild requirements, or operational checks. Write "None" when not applicable.

<!-- SPORTSOS_M36_1_RELEASE_GOVERNANCE -->
## Release and dependency governance

- [ ] The branch is based on the current `main` release lineage.
- [ ] CI is green for the candidate commit before merge/release.
- [ ] Dependency changes are isolated from unrelated product changes when practical.
- [ ] Security-related dependency updates identify the advisory/update being addressed and include focused regression coverage.
- [ ] Major-version dependency upgrades are reviewed and validated independently; they are not treated as routine auto-merge updates.
- [ ] Release tags are annotated and created only after the full release gate passes.
