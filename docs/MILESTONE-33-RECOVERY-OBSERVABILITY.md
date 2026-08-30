# Milestone 33 — Recovery Observability & Operator Diagnostics

Milestone 33 makes SportsOS runtime self-healing observable without changing
recovery authority.

## Scope

Milestone 33 adds:

- recovery telemetry to the protected operations status snapshot
- recent successful, blocked, and failed recovery activity
- canonical shared recovery policy ownership
- per-service live recovery guardrail state
- dashboard operator diagnostics
- regression coverage for recovery observability and authority separation

## Recovery authority

Recovery authority remains in:

`scripts/container-recovery-check.sh`

The recovery engine remains dry-run by default unless explicitly enabled with
`SPORTSOS_APPLY_RECOVERY=1`.

The dashboard and operations snapshot are observability surfaces only. They do
not execute container restarts or mutate recovery state.

## Canonical recovery policy

Recovery guardrails and service policy ownership are centralized in:

`scripts/lib/recovery-policy.sh`

The canonical service policies are:

- api — auto
- dashboard — auto
- mysql — monitor
- redis — monitor
- mqtt — auto
- minio — monitor
- scoreboard-simulator — auto

## Recovery telemetry

The operations status snapshot exposes recovery telemetry under the top-level
`recovery` object.

The protected API preserves the established response envelope:

`{ success, data: snapshot }`

Therefore dashboard recovery telemetry is read from:

`response.data?.recovery`

## Live guardrail state

Each recovery service exposes:

- `guardrailState`
- `eligible`
- `blockedReason`
- `successfulActionsInWindow`
- `remainingBudget`
- `cooldownRemainingSeconds`

Operator states are:

- READY
- COOLDOWN
- BUDGET EXHAUSTED
- MONITOR ONLY

Guardrail state matches recovery-engine ordering: cooldown is evaluated before
budget exhaustion.

## Security

Milestone 33 does not weaken the protected operations status API.

The operations dashboard continues to use server-side status retrieval. The
operations status bearer token is not rendered into the public page or moved
into client-side recovery code.

## Validation

Milestone 33 closeout validates:

- recovery engine dry-run behavior
- fresh recovery status snapshot
- seven-service policy contract
- guardrail telemetry contract
- TypeScript typecheck
- full unit/integration tests
- production build
- rebuilt API and dashboard containers
- Docker Playwright E2E
- protected API authentication behavior
- authenticated recovery telemetry response
- public Operations Dashboard availability
- exact release repository scope

