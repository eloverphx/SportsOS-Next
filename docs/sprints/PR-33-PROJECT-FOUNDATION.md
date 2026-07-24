# PR #33 — Project Foundation and Governance

## Status

In progress

## Objective

Establish the repository governance, documentation structure, shared platform contracts, and automated validation required for long-term SportsOS development.

## Scope

- GitHub issue and pull request templates
- CODEOWNERS
- Repository documentation structure
- Architecture Decision Record framework
- Engineering standards
- Product roadmap and versioning policy
- Shared core package foundation
- Shared errors, types, validation, logging, and event contracts
- Continuous integration checks

## Out of scope

- Game Center
- Game clock
- Scoring
- Penalties
- Venue management
- Officials management
- MQTT protocol changes
- Database migrations
- Dashboard feature changes

## Acceptance criteria

### Governance

- [ ] Pull request template exists
- [ ] Bug report template exists
- [ ] Feature request template exists
- [ ] Architecture proposal template exists
- [ ] CODEOWNERS exists

### Documentation

- [ ] Documentation index exists
- [ ] Vision is documented
- [ ] Architecture is documented
- [ ] Engineering standards are documented
- [ ] Roadmap is documented
- [ ] Versioning policy is documented
- [ ] ADR template exists
- [ ] Initial ADRs are recorded

### Core platform

- [ ] Shared core package structure exists
- [ ] Shared TypeScript contracts compile
- [ ] Shared error hierarchy exists
- [ ] Domain event interfaces exist
- [ ] Logger interface exists
- [ ] Shared validation utilities exist

### Validation

- [ ] API typecheck passes
- [ ] API build passes
- [ ] Dashboard typecheck passes
- [ ] Dashboard build passes
- [ ] Docker configuration remains operational
- [ ] Existing functionality remains unchanged

## Risk

Overall risk is low.

The primary technical risk is accidentally changing the existing build or deployment workflow while introducing shared project infrastructure. PR #33 must therefore avoid converting the repository to npm workspaces.

## Rollback

All changes in this pull request are additive except for documentation file moves. The pull request can be reverted without requiring a database or application-data rollback.
