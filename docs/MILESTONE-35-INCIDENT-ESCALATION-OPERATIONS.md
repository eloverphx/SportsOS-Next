# Milestone 35 — Incident Escalation Operations & Delivery Observability

## Status

Release closeout complete. Milestone 35 is ready for release commit and tag.

## Objective

Milestone 35 operationalizes the Milestone 34 incident escalation subsystem by integrating it into production operations, providing Unraid scheduling, exposing delivery telemetry, surfacing escalation observability in the Operations Dashboard, creating durable incidents for real notification delivery failures, and validating the complete notification-failure path with controlled fault injection.

## Delivered Capabilities

### M35.2 — Production Runner Integration

The production operations runner now supports an explicit `incident-escalation` mode. Escalation remains intentionally separate from unrelated daily and weekly operations flows.

The escalation runtime directory and generated state/audit files are normalized for the API runtime ownership model:

- directory: `1000:1000`, mode `0750`
- state/audit files: `1000:1000`, mode `0640`

### M35.3 — Unraid Scheduling

A dedicated Unraid User Scripts wrapper and installer were added for incident escalation.

The wrapper does not modify Unraid cron internals. Scheduling remains an explicit operator action through the Unraid User Scripts interface, with the validated cadence:

`*/5 * * * *`

### M35.4 — Escalation Delivery Telemetry

The escalation subsystem now exposes structured status telemetry including:

- availability
- state/audit presence
- tracked incident count
- audit event count
- recent event count
- recent delivery failure count
- last event
- recent escalation events

The telemetry is merged into the protected Operations status snapshot as `incidentEscalation`.

Operations status snapshot ownership is preserved as `1000:1000` with mode `0640`.

### M35.5 — Operations Dashboard Observability

The protected Operations Dashboard now renders Incident Escalation Delivery observability alongside the existing Production Incidents section.

The dashboard reads the protected server-side status response and never exposes the Operations bearer token to client-side code.

### M35.6 — Delivery Failure Incident Integration

Actual webhook delivery failures now signal the protected internal Operations incident API.

The deterministic fingerprint is:

`operations:incident-escalation-delivery-failure`

The durable incident uses:

- source: `operations`
- severity: `critical`
- service: `incident-escalation`

Repeated failures update the same incident rather than creating unique incidents. If the incident was resolved and delivery later fails again, the same durable incident is reopened.

Dry-run and local-only escalation paths do not create delivery failure incidents.

The escalation script never writes the incident journal directly. Journal mutation remains owned by the API service.

### M35.7 — Controlled Notification Fault Injection

A controlled runtime exercise validated the complete escalation failure chain using an intentionally unreachable loopback webhook target.

Validated behavior:

1. synthetic critical incident becomes escalation-eligible
2. webhook delivery fails
3. escalation audit records the failed delivery
4. delivery telemetry reports the failure
5. protected internal signaling creates the durable critical delivery-failure incident
6. repeated failure updates the same deterministic incident
7. Operations Dashboard exposes escalation and incident observability
8. original runtime incident/escalation state is restored

The exercise also identified and repaired a duplicate embedded Node `path` declaration before final validation.

## Security and Authority Invariants

Milestone 35 preserves the following boundaries:

- Operations bearer token is not printed by scripts.
- Dashboard access to protected Operations APIs remains server-side.
- Escalation remains notification-only.
- Escalation has no Docker restart/stop/remove authority.
- Escalation has no system service restart/stop authority.
- Delivery failure signaling uses the protected Operations API.
- Bash does not directly mutate the durable incident journal.
- No webhook configuration is persisted by fault-injection tests.
- Fault injection restores production runtime state.

## Validation

Release closeout validated:

- focused M35 regression suite
- repository TypeScript typechecks
- complete repository unit/integration test suite
- production build
- API/dashboard container rebuild
- bounded local readiness checks
- protected Operations status authorization
- protected incident API authorization
- escalation delivery telemetry availability
- public API health
- public Operations Dashboard availability
- Docker Playwright E2E suite
- runtime ownership and permission invariants
- escalation notification-only authority
- Operations token secrecy checks over tracked first-party source

## Release State

Milestone 35 closeout is complete.

The next step is to create the Milestone 35 release commit and annotated tag:

- expected tag: `sportsos-m35-complete`

No release commit or tag is created by the documentation repair.
