# Milestone 34 — Production Incident Management & Recovery Escalation

Milestone 34 adds a durable, operator-visible incident lifecycle on top of the
Milestone 33 recovery observability foundation.

## Capabilities

- Durable Operations incident journal with fingerprint deduplication and history.
- Deterministic incident synthesis from recovery, reliability, and operations signals.
- Protected read-only incident API.
- Production Incidents panel in the protected Operations Dashboard.
- Explicit authenticated acknowledgement and resolution actions.
- Durable operator identity, notes, and lifecycle audit events.
- Reopening of resolved incidents when the same production signal recurs.
- Bounded escalation policy for unresolved warning and critical incidents.
- Repeat-notification cooldown and persistent escalation audit history.
- Optional webhook delivery with bounded timeout.
- Isolated fault-injection regression coverage.

## Lifecycle

Incidents use these states:

1. `open`
2. `acknowledged`
3. `resolved`

A resolved incident may be reopened by synthesis when its fingerprint recurs.
Acknowledgement and resolution are explicit operator actions. Recovery and
synthesis do not have authority to acknowledge or resolve incidents.

## Protected API

Read:

- `GET /deployment/operations/incidents`
- `GET /deployment/operations/incidents/:incidentId`

Operator lifecycle:

- `POST /deployment/operations/incidents/:incidentId/acknowledge`
- `POST /deployment/operations/incidents/:incidentId/resolve`

The API reuses the protected Operations enable flag and bearer token. Responses
use `Cache-Control: no-store`. The bearer token remains server-side in the
dashboard integration.

## Escalation defaults

- Critical unresolved incident: 5 minutes.
- Warning unresolved incident: 30 minutes.
- Repeat escalation cooldown: 60 minutes.
- Local audit delivery is always available.
- Optional webhook delivery can be configured.
- Dry-run mode is supported.

The escalation layer cannot restart containers, alter recovery budgets, or
perform destructive service actions.

## Runtime data

Incident journal:

`data/operations-incidents/incidents.json`

Escalation state and audit:

`data/operations-incident-escalation/state.json`

`data/operations-incident-escalation/escalation-events.tsv`

These are runtime artifacts under the repository's ignored `data/` tree.

## Safety boundaries

- No incident deletion endpoint.
- No automatic acknowledgement or resolution.
- No recovery authority in dashboard actions.
- No recovery authority in escalation.
- No secret is rendered into public dashboard HTML.
- Fault injection uses temporary isolated runtime data.
- Production services are not stopped for incident regression testing.

## Release validation

Milestone 34 closeout requires:

- focused incident regression tests
- full TypeScript validation
- full unit/integration tests
- API and dashboard production builds
- API/dashboard container rebuild
- Docker Playwright E2E
- protected incident API authorization verification
- public Operations Dashboard availability
- bearer-token leakage check
- exact release-scope verification
