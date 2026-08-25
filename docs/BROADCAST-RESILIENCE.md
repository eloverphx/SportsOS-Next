# SportsOS Broadcast Resilience

## Milestone 24.1 — Recovery policy foundation

Milestone 24 begins production hardening of the broadcast lifecycle.

The first resilience layer is intentionally a **decision policy**, not an
automatic FFmpeg watchdog. It compares coordinator intent with observed runtime
state and determines whether SportsOS should:

- do nothing
- observe during a startup grace period
- reconcile harmless idle state
- request a controlled start
- request a controlled stop
- require operator review

### Safety rule

A disagreement between coordinator intent and encoder runtime must never cause
an automatic destructive action.

In particular:

- a missing runtime is not silently restarted
- an unexpected live runtime is not silently killed
- failed or unknown runtime state requires operator review
- stale starting/stopping transitions require operator review
- startup grace prevents restart/recovery flapping

This keeps the coordinator authoritative while creating a deterministic basis
for later supervisor and recovery work.

### Milestone 24 sequence

24.1 Recovery policy foundation  
24.2 Runtime heartbeat and stale-process detection  
24.3 Coordinator/runtime reconciliation supervisor  
24.4 Controlled recovery workflow  
24.5 Restart/crash recovery persistence  
24.6 Stream destination failure handling  
24.7 Backoff and retry budgets  
24.8 Resilience telemetry and operator visibility  
24.9 Failure-injection / chaos regression tests  
24.10 Production resilience acceptance / closeout

## Milestone 24.2 — Runtime heartbeat / stale process detection

SportsOS now has a read-only encoder runtime heartbeat evaluator.

Heartbeat states:

```text
HEALTHY
STALE
MISSING
STOPPED
FAILED
UNKNOWN
```

Default staleness threshold:

```text
20 seconds
```

Configuration is bounded between:

```text
1 second
300 seconds
```

The evaluator uses the freshest runtime activity timestamp available from the existing encoder snapshot:

```text
lastOutputAt
lastProgressAt
telemetry.updatedAt
session.updatedAt
```

API:

```text
GET /broadcast-coordinator/:gameId/runtime-heartbeat
```

Milestone 24.2 is detection only.

A stale, missing, failed, or unknown heartbeat does **not** automatically restart or stop FFmpeg. Later resilience milestones consume this signal through the recovery policy and controlled supervisor.

## Milestone 24.3 — Coordinator / runtime reconciliation supervisor

SportsOS now combines the Milestone 24.1 recovery policy and Milestone 24.2 runtime heartbeat into one read-only reconciliation decision.

The supervisor normalizes current coordinator intent and encoder runtime state, evaluates heartbeat freshness, then returns a recommended recovery action.

API:

```text
GET /broadcast-coordinator/:gameId/resilience-supervisor
```

Response includes:

```text
heartbeat
recovery
```

The supervisor does **not** execute the recommended action.

A stale, missing, failed, or unknown heartbeat is conservatively converted into operator-review recovery behavior.

Milestone 24.3 therefore establishes deterministic reconciliation logic without enabling automatic start/stop recovery.

## Milestone 24.4 — Controlled recovery workflow

SportsOS can now execute a recovery recommendation through an explicit operator-approved API.

Endpoint:

```text
POST /broadcast-coordinator/:gameId/recovery/execute
```

Required operator input:

```text
operator
```

Destructive recovery additionally requires:

```text
approveDestructive = true
```

Behavior:

```text
request-controlled-start
  -> returns to PREPARE only
  -> normal guarded Start Broadcast flow is still required

request-controlled-stop
  -> executes existing coordinated stop path
  -> requires explicit destructive approval

reconcile-to-idle
  -> executes existing coordinator reconciliation

require-operator-review
  -> refused

observe / none
  -> no action
```

Recovery requests, successful executions, and refusals are added to the coordinator audit history.

The controlled recovery service does not call encoder-runtime internals directly.

## Milestone 24.5 — Restart / crash recovery persistence

SportsOS now persists a compact recovery snapshot for each broadcast.

Store:

```text
broadcast-recovery-snapshots.json
```

Each snapshot contains:

```text
gameId
capturedAt
coordinatorIntent
runtimeStatus
lastActivityAt
recoveryAction
heartbeatState
```

APIs:

```text
GET  /broadcast-coordinator/recovery-snapshots
GET  /broadcast-coordinator/:gameId/recovery-snapshot
POST /broadcast-coordinator/:gameId/recovery-snapshot/capture
```

The snapshot store is bounded to 500 broadcasts.

This persistence is diagnostic and recovery-context only. Loading a saved recovery snapshot does not automatically start, stop, reconcile, or mutate a broadcast.

Milestone 24.5 establishes the state needed to recognize crash/restart mismatches in later supervisor work.

## Milestone 24.6 — Stream destination failure handling

SportsOS now classifies stream destination failures before they enter recovery or retry logic.

Failure classes:

```text
NONE
TRANSIENT_NETWORK
AUTHENTICATION
CONFIGURATION
REMOTE_REJECTED
RATE_LIMITED
TIMEOUT
UNKNOWN
```

Recommended actions:

```text
NONE
RETRY_ALLOWED
RETRY_WITH_BACKOFF
OPERATOR_REVIEW
```

Classification examples:

```text
401 / 403                -> AUTHENTICATION -> OPERATOR_REVIEW
429                      -> RATE_LIMITED -> RETRY_WITH_BACKOFF
5xx                      -> REMOTE_REJECTED -> RETRY_WITH_BACKOFF
other 4xx                -> CONFIGURATION -> OPERATOR_REVIEW
ETIMEDOUT                 -> TIMEOUT -> RETRY_WITH_BACKOFF
ECONNRESET / ECONNREFUSED -> TRANSIENT_NETWORK -> RETRY_ALLOWED
unknown failure           -> UNKNOWN -> OPERATOR_REVIEW
```

API:

```text
POST /broadcast-coordinator/:gameId/destination-failure/classify
```

Milestone 24.6 performs classification only. It does not directly restart the encoder, retry a publish target, modify credentials, or bypass the existing retry budget.

## Milestone 24.7 — Resilience retry budgets / backoff policy

SportsOS now has a bounded resilience retry-budget policy for stream destination recovery.

Defaults:

```text
max attempts: 5
base delay:   5 seconds
max delay:    120 seconds
```

Hard bounds:

```text
max attempts: 1..20
base delay:   1..60 seconds
max delay:    up to 10 minutes
```

Backoff formula:

```text
delay = min(maxDelay, baseDelay * 2^attempts)
```

Retry-budget states:

```text
AVAILABLE
SCHEDULED
EXHAUSTED
REFUSED
```

Non-retryable or `OPERATOR_REVIEW` failures are refused immediately.

API:

```text
POST /broadcast-coordinator/:gameId/resilience-retry-budget
```

Milestone 24.7 calculates retry eligibility and timing only. It does not create a timer loop or execute retries automatically.

## Milestone 24.8 — Resilience telemetry / operator visibility

Focus Mode now displays the current resilience decision before an operator executes controlled recovery.

API:

```text
GET /broadcast-coordinator/:gameId/resilience-status
```

The response includes:

```text
heartbeat
recovery
persistedSnapshot
```

Operator-visible fields include:

- heartbeat state
- heartbeat age / staleness threshold
- heartbeat reason
- recommended recovery action
- recovery reason
- whether the recommendation is automatic
- whether the recommendation is destructive
- last persisted recovery snapshot

This panel is read-only. It does not execute recovery or mutate broadcast state.

## Milestone 24.9 — Failure injection / chaos regression tests

The resilience layer now includes deterministic failure-injection coverage for:

- missing heartbeat during intended live state
- stale heartbeat
- failed encoder runtime
- unexpected live runtime after stop intent
- authentication failure
- transient remote 5xx failure
- transient network failure
- retry budget exhaustion
- startup grace / anti-flapping behavior
- stale starting transitions
- malformed heartbeat timestamps
- repeated retry attempts under maximum-delay caps

These tests intentionally exercise failure states without starting real encoders or requiring live stream destinations.

The acceptance condition is fail-safe behavior:

```text
ambiguous / unsafe -> operator review
destructive action -> never automatic
retryable failure  -> bounded retry
non-retryable      -> refused
retry budget spent -> exhausted
startup transition -> grace before recovery
```

## Milestone 24.10 — Production resilience acceptance / closeout

Milestone 24 acceptance is documented in:

```text
docs/MILESTONE-24-BROADCAST-RESILIENCE-ACCEPTANCE.md
```

The closeout regression suite verifies recovery policy, heartbeat detection, resilience supervision, controlled recovery, restart/crash persistence, destination failure classification, retry budgets, operator telemetry, and failure-injection coverage.

Milestone 24 is complete only after typecheck, unit tests, combined API/dashboard Docker startup, API health verification, and Docker E2E tests are all green.
