# Broadcast Session Coordinator

Milestone 22 begins production broadcast automation and resilience.

## Milestone 22.1 — Broadcast session coordinator foundation

The coordinator sits above the Milestone 20 encoder stack and Milestone 21 production go-live safety layer.

It does not create a second authoritative stream lifecycle.

Coordinator intent is limited to:

```text
IDLE
PREPARE
GO_LIVE
STOP
```

The authoritative operational state still comes from:

- game-day go-live preflight
- go-live session
- encoder runtime
- publish telemetry
- recovery state

Coordinator API:

```text
GET  /broadcast-coordinator/:gameId
POST /broadcast-coordinator/:gameId/prepare
POST /broadcast-coordinator/:gameId/reset
```

`prepare` runs the existing final game-day go-live preflight and returns HTTP 409 when preparation is blocked.

Each coordinator write receives a correlation ID for later orchestration tracing.

## Milestone 22.2 — Coordinator start / stop orchestration

The coordinator can now issue production start and stop intent while reusing the existing Milestone 21 go-live state and Milestone 20 encoder runtime.

Endpoints:

```text
POST /broadcast-coordinator/:gameId/start
POST /broadcast-coordinator/:gameId/stop
```

Start behavior:

- requires final game-day go-live preflight to pass
- ensures the existing go-live session is ARMED
- uses the existing stream destination profile
- transitions the existing go-live session to STARTING
- starts the existing encoder runtime
- records coordinator `GO_LIVE` intent

Stop behavior:

- records coordinator `STOP` intent
- transitions the existing go-live session to STOPPING
- stops the existing encoder runtime
- completes the existing go-live session
- returns coordinator intent to IDLE

The coordinator does not bypass go-live safety or create duplicate runtime state.

## Milestone 22.3 — Coordinator health / drift detection

The broadcast coordinator now evaluates whether its intent agrees with the actual go-live and encoder state.

Detected drift includes:

```text
INTENT_GO_LIVE_RUNTIME_STOPPED
INTENT_GO_LIVE_SESSION_NOT_ACTIVE
INTENT_STOP_RUNTIME_ACTIVE
GO_LIVE_LIVE_RUNTIME_NOT_LIVE
EMERGENCY_STOP_RUNTIME_ACTIVE
```

API:

```text
GET /broadcast-coordinator/:gameId/health
```

The health endpoint returns both:

- coordinator drift assessment
- current composed coordinator/go-live/runtime snapshot

Drift detection is observational only. It does not mutate the coordinator, go-live session, encoder runtime, or authoritative game state.

## Milestone 22.4 — Coordinator reconciliation / safe repair actions

The coordinator can now attempt narrowly scoped repair for known drift states.

Supported reconciliation actions:

```text
NONE
RESET_INTENT
STOP_RUNTIME
REFUSE_AMBIGUOUS
```

Safe repairs:

- reset stale `GO_LIVE` intent to `IDLE` when both runtime and go-live state are inactive
- stop an unexpectedly active encoder when coordinator intent is `STOP`
- stop an unexpectedly active encoder when go-live state is `EMERGENCY_STOPPED`

Ambiguous drift is never auto-repaired.

The reconciliation layer must not:

- start FFmpeg
- arm a go-live session
- confirm a session LIVE
- clear a degraded incident
- modify authoritative game state

API:

```text
POST /broadcast-coordinator/:gameId/reconcile
```

Ambiguous repair requests return HTTP 409 for operator review.

## Milestone 22.5 — Coordinator audit / reconciliation history

Coordinator automation now has its own persistent audit history, separate from encoder runtime audit, go-live lifecycle audit, and authoritative game events.

Recorded event types include:

```text
INTENT_CHANGED
PREPARE_REQUESTED
PREPARE_BLOCKED
START_REQUESTED
START_COMPLETED
START_BLOCKED
STOP_REQUESTED
STOP_COMPLETED
DRIFT_DETECTED
RECONCILE_REQUESTED
RECONCILE_COMPLETED
RECONCILE_REFUSED
```

Audit entries retain coordinator correlation IDs when available.

API:

```text
GET /broadcast-coordinator/:gameId/audit?limit=100
```

The store keeps the newest 2500 coordinator events globally and limits an individual request to 250 events.

## Milestone 22.6 — Coordinator retry policy / backoff

The coordinator now has a bounded retry policy for automation-level preparation failures.

Retry states:

```text
IDLE
SCHEDULED
RETRYING
EXHAUSTED
```

Defaults:

```text
max attempts: 3
base backoff: 10 seconds
```

Configuration limits:

```text
max attempts: 0–10
backoff: 1–300 seconds
```

Retry APIs:

```text
GET  /broadcast-coordinator/:gameId/retry
PUT  /broadcast-coordinator/:gameId/retry
POST /broadcast-coordinator/:gameId/retry/schedule
POST /broadcast-coordinator/:gameId/retry/execute
```

Backoff grows with the attempt number.

A retry never bypasses final game-day go-live preflight. If preflight remains blocked, another bounded retry is scheduled until attempts are exhausted.

Retry execution only returns to broadcast preparation. It does not automatically start FFmpeg.

## Milestone 22.7 — Coordinator supervisor / automatic retry tick

A bounded supervisor tick now executes due retries, invokes only previously defined safe reconciliation, refuses ambiguous drift, and otherwise performs no action.

```text
POST /broadcast-coordinator/:gameId/supervisor/tick
```

Supervisor actions are `NONE`, `RETRY_EXECUTED`, `RECONCILED`, and `REFUSED`.

The supervisor deliberately remains a single tick rather than an internal timer loop. It never automatically starts FFmpeg; successful retry returns only to preparation.

## Milestone 22.8 — Supervisor runtime scheduling / lifecycle

The bounded coordinator supervisor tick now has an application-runtime scheduler.

Runtime behavior:

```text
default interval: 5000 ms
minimum interval: 1000 ms
maximum interval: 60000 ms
```

The runtime invokes only the existing bounded supervisor tick, isolates failures per game, records startup/shutdown/failure audit events, starts with the API lifecycle, and stops cleanly during API shutdown.

The scheduler accepts a `gameIds()` provider. Milestone 22.8 intentionally wires an empty provider until an authoritative active-broadcast discovery source is added. This establishes lifecycle behavior without accidentally enabling global automation.

The runtime never directly starts FFmpeg.

## Milestone 22.9 — Authoritative active broadcast discovery

The supervisor runtime no longer uses an empty placeholder game provider.

Active broadcast discovery is derived from the existing operational sources:

```text
coordinator intent
go-live session state
encoder runtime state
```

A known game is considered active when coordinator intent is not `IDLE`, the existing go-live session is `ARMED`, `STARTING`, `LIVE`, `DEGRADED`, or `STOPPING`, or the existing encoder runtime is neither `STOPPED` nor `ERROR`.

This avoids creating a second broadcast-active flag or parallel lifecycle.

API:

```text
GET /broadcast-coordinator/active
```

The API runtime supervisor now uses `listActiveBroadcastGameIds()` as its game discovery provider.

Discovery is read-only and does not start, stop, arm, reconcile, or modify authoritative game state.

## Milestone 22.10 — Broadcast automation acceptance / closeout

Milestone 22 acceptance is documented in:

```text
docs/MILESTONE-22-BROADCAST-AUTOMATION-ACCEPTANCE.md
```

The closeout regression test verifies that health/drift detection, bounded reconciliation, retry/backoff, audit history, supervisor scheduling, clean shutdown, and authoritative active-broadcast discovery remain wired together.

Milestone 22 is not considered complete until typecheck, unit tests, rebuilt API/dashboard containers, and Docker E2E tests are all green.
