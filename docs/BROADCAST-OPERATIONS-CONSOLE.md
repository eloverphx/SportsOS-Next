# Broadcast Operations Console

Milestone 23 begins the operator-experience layer for production broadcast operations.

## Milestone 23.1 — Operations console foundation

The dashboard adds:

```text
/broadcast/operations
```

The page consolidates:

- coordinator intent
- go-live session state
- encoder runtime state
- publish health
- coordinator health/drift
- retry state
- correlation ID

API:

```text
GET /broadcast-coordinator/operations-summary
```

The operations console is read-only in Milestone 23.1.

It does not introduce new lifecycle state or bypass existing safety controls.

The page refreshes every 5 seconds and also supports manual refresh.

## Milestone 23.2 — Operator actions / safe control surface

The broadcast operations console now exposes bounded operator actions:

```text
Prepare
Reconcile
Execute Retry
Stop Broadcast
```

All actions call the existing coordinator endpoints.

The dashboard does not call encoder runtime services directly and does not duplicate safety logic.

Action mapping:

```text
Prepare       -> POST /broadcast-coordinator/:gameId/prepare
Reconcile     -> POST /broadcast-coordinator/:gameId/reconcile
Execute Retry -> POST /broadcast-coordinator/:gameId/retry/execute
Stop Broadcast-> POST /broadcast-coordinator/:gameId/stop
```

Retry execution is disabled unless the coordinator retry state is `SCHEDULED`.

Operator action results are surfaced in the console and the summary refreshes after successful actions.

## Milestone 23.3 — Start broadcast confirmation / guarded operator flow

The operations console now exposes a guarded start flow.

Start is available only when:

```text
coordinator intent = PREPARE
coordinator health = healthy
```

Operator sequence:

```text
Prepare
Review status
Start Broadcast
Confirm Start Broadcast
```

The first click only opens the confirmation state.

The second click sends:

```text
POST /broadcast-coordinator/:gameId/start
```

The dashboard still does not call encoder runtime services directly.

Cancel Start clears the pending confirmation without changing broadcast state.

## Milestone 23.4 — Operator incident / emergency controls

The broadcast operations console now surfaces the existing production incident and emergency controls.

Available incident controls while go-live status is `DEGRADED`:

```text
Acknowledge Incident
Retry Health Check
```

Available emergency control while a broadcast is active or degraded:

```text
Emergency Stop Broadcast
```

Action mapping:

```text
POST /go-live-sessions/:gameId/acknowledge-incident
POST /go-live-sessions/:gameId/retry-health
POST /go-live-sessions/:gameId/emergency-stop
```

The dashboard does not implement incident-state transitions itself. All enforcement remains in the existing go-live API/service layer.

Incident acknowledgement requires an operator name.

Emergency-stop reason is operator-supplied and the resulting `EMERGENCY_STOPPED` state is displayed in the operations console.

## Milestone 23.5 — Operator audit timeline / action history

The operations console now exposes a combined operator timeline.

Sources:

```text
COORDINATOR
GO_LIVE
```

The API merges the existing coordinator audit and go-live audit without creating a third persistence layer.

Endpoint:

```text
GET /broadcast-coordinator/:gameId/operator-timeline?limit=50
```

Timeline events may include:

- preparation
- start / stop orchestration
- drift detection
- reconciliation
- retry scheduling / execution / exhaustion
- supervisor actions
- degraded incidents
- incident acknowledgements
- emergency stops
- recovery
- live confirmation

Coordinator correlation IDs and go-live operator identities are preserved when available.

The operator timeline is read-only.

## Milestone 23.6 — Attention queue / operator prioritization

The operations console now includes a ranked attention queue.

Severity levels:

```text
CRITICAL
HIGH
MEDIUM
LOW
```

Priority is derived from existing state only.

Examples:

```text
EMERGENCY_STOPPED -> CRITICAL
coordinator drift -> HIGH
DEGRADED -> HIGH
retry EXHAUSTED -> HIGH
retry SCHEDULED -> MEDIUM
STARTING / STOPPING -> MEDIUM
healthy active broadcast -> LOW
```

Endpoint:

```text
GET /broadcast-coordinator/attention-queue
```

The queue does not create a second incident or severity persistence model.

Severity and reason are calculated from the current coordinator, go-live, runtime, health, and retry state each time the endpoint is requested.

## Milestone 23.7 — Operator focus mode / single broadcast workspace

The operations console now links each attention item to:

```text
/broadcast/operations/:gameId
```

Focus Mode consolidates one broadcast's coordinator intent, go-live state, encoder state, publish health, retry state, coordinator health issues, safe coordinator actions, degraded incident controls, emergency stop, and operator timeline.

Focus Mode consumes the existing coordinator and go-live APIs only.

It does not create new lifecycle, incident, audit, retry, or encoder state.

The workspace refreshes every 5 seconds.

## Milestone 23.8 — Operator notes / shift handoff context

Focus Mode now supports persistent operator handoff notes.

API:

```text
GET  /broadcast-coordinator/:gameId/operator-notes
POST /broadcast-coordinator/:gameId/operator-notes
```

Each note contains:

```text
gameId
operator
note
createdAt
```

Notes are stored in the shared SportsOS data directory:

```text
broadcast-operator-notes.json
```

The notes store is bounded to the newest 2500 notes globally.

Operator notes are context only. They do not modify:

- coordinator intent
- go-live state
- encoder state
- retry state
- incident state
- automation decisions
- authoritative game state

Focus Mode displays newest notes first and refreshes them with the rest of the broadcast workspace.

## Milestone 23.9 — Operator shift summary / handoff snapshot

Focus Mode can now generate a read-only handoff snapshot.

Endpoint:

```text
GET /broadcast-coordinator/:gameId/handoff-summary
```

The snapshot combines:

- current coordinator snapshot
- current coordinator health
- current retry state
- newest 5 operator notes
- newest 10 combined coordinator/go-live events

No new persistence is created.

The handoff snapshot is generated on demand and reflects current operational state at the moment it is requested.

Focus Mode exposes:

```text
Generate Handoff Snapshot
```

for fast operator-to-operator context transfer.

## Milestone 23.10 — Broadcast operations acceptance / closeout

Milestone 23 acceptance is documented in:

```text
docs/MILESTONE-23-BROADCAST-OPERATIONS-ACCEPTANCE.md
```

The closeout regression suite verifies the operations console, guarded controls, incident/emergency actions, attention queue, Focus Mode, audit timeline, shift notes, handoff snapshot, and the rule that dashboard code never directly controls the encoder runtime.

Milestone 23 is complete only after typecheck, unit tests, combined API/dashboard Docker startup, API health verification, and Docker E2E tests are all green.
