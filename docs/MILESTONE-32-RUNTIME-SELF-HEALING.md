# Milestone 32 — Production Runtime Self-Healing & Continuity

Milestone 32 hardens SportsOS production continuity without weakening server authority, device authentication, or stateful-service safety.

## Scope

Milestone 32 repaired the scoreboard simulator runtime crash loop and expanded production recovery coverage with bounded, auditable self-healing.

### Scoreboard simulator runtime repair

The simulator image now installs runtime dependencies directly from the simulator package manifest so the MQTT dependency cannot be omitted by workspace pruning.

The simulator remains subject to its existing authenticated device configuration. Milestone 32 does not bypass `SCOREBOARD_DEVICE_ID`, `SCOREBOARD_DEVICE_KEY`, API authority, or MQTT authentication.

### Recovery inventory

The production recovery engine monitors:

- API
- dashboard
- MySQL
- Redis
- MQTT
- MinIO
- scoreboard simulator

### Automatic recovery policy

Automatic bounded recovery is allowed for:

- API
- dashboard
- MQTT
- scoreboard simulator

The following stateful services are monitor-only by default:

- MySQL
- Redis
- MinIO

A scheduled recovery check cannot automatically restart those monitor-only services.

## Guardrails

The recovery engine includes:

- dry-run behavior by default
- explicit `SPORTSOS_APPLY_RECOVERY=1` requirement for recovery actions
- direct-script `flock` concurrency protection
- per-service cooldown
- per-service recovery budget within a time window
- restart-delta detection
- post-restart health verification
- persistent recovery action audit logging
- persistent restart-count state
- bounded one-service recovery actions
- no volume deletion
- no database reset
- no credential reset
- no destructive data recovery operations

Default limits:

- cooldown: 900 seconds
- recovery budget window: 3600 seconds
- successful automatic recoveries allowed per service/window: 2
- post-recovery verification timeout: 60 seconds

## Scheduled production behavior

The existing Unraid recovery wrapper explicitly enables bounded recovery for scheduled recovery runs.

Direct/manual execution of the recovery engine remains dry-run unless the operator explicitly sets `SPORTSOS_APPLY_RECOVERY=1`.

## Fault-injection validation

Milestone 32 performed controlled live fault injection against the scoreboard simulator only.

Validation proved:

1. simulator failure detection
2. bounded automatic restart
3. post-restart health verification
4. recovery audit logging
5. cooldown/recovery-budget suppression on a repeated failure
6. operator restoration after circuit-breaker suppression
7. healthy final production fleet

Stateful services, API, and MQTT were not intentionally fault-injected.

## Operational principle

Docker restart policies remain the first process/container restart layer. SportsOS self-healing is a bounded supervisory layer and must not become an infinite restart loop.

When the recovery budget or cooldown blocks an action, the condition remains visible for operator intervention rather than repeatedly forcing restarts.

## Release validation

Milestone 32 release closeout requires:

- shell validation
- source contract regression test
- production recovery dry run
- healthy scoreboard simulator
- TypeScript typecheck
- unit/integration tests
- production build
- API/dashboard image rebuild
- Docker E2E tests
- exact release file whitelist
- release commit and annotated tag only after explicit operator apply
