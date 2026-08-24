# Go-Live Operations

Milestone 21 begins the production go-live orchestration layer.

## Milestone 21.1 — Go-live session foundation

Go-live session states:

```text
IDLE
ARMED
STARTING
LIVE
STOPPING
COMPLETE
ERROR
```

The go-live layer orchestrates existing streaming readiness and encoder runtime capabilities.

It does not become authoritative for game state.

## Operator flow

```text
streaming preflight PASS
        ↓
ARMED
        ↓
STARTING
        ↓
encoder LIVE + publish HEALTHY
        ↓
LIVE
        ↓
STOPPING
        ↓
COMPLETE
```

## API

```text
GET  /go-live-sessions/:gameId
POST /go-live-sessions/:gameId/arm
POST /go-live-sessions/:gameId/start
POST /go-live-sessions/:gameId/confirm-live
POST /go-live-sessions/:gameId/stop
POST /go-live-sessions/:gameId/reset
```

Arming requires a passing streaming readiness preflight.

Start requires ARMED plus a fresh passing readiness preflight.

Live confirmation requires encoder state `LIVE` and publish telemetry health `HEALTHY`.

## Milestone 21.2 — Scheduled go-live and start window

Go-live sessions may now define:

- scheduled start timestamp
- early start window in minutes
- late start window in minutes

Defaults:

```text
early window: 15 minutes
late window: 15 minutes
```

Window bounds are clamped to 0–120 minutes.

API:

```text
PUT /go-live-sessions/:gameId/schedule
GET /go-live-sessions/:gameId/start-window
```

A scheduled go-live start is rejected when it is too early or after the configured window expires.

This milestone does not auto-start the encoder. It only provides scheduling metadata and start-window enforcement.

## Milestone 21.3 — Scheduled auto-arm and operator countdown

Scheduled sessions may optionally auto-arm before start. The default lead is 30 minutes and is clamped to 0–240 minutes. Auto-arm remains readiness-gated and never starts FFmpeg automatically.

Endpoints:

```text
PUT  /go-live-sessions/:gameId/auto-arm
GET  /go-live-sessions/:gameId/countdown
POST /go-live-sessions/:gameId/auto-arm/evaluate
```

## Milestone 21.4 — Go-live confirmation health hold

A momentary encoder `LIVE` state is no longer enough to confirm a production broadcast.

The go-live session now tracks:

```text
healthHoldSeconds
healthySinceAt
```

Default confirmation hold:

```text
10 seconds
```

Allowed range:

```text
0–120 seconds
```

The health timer only advances while both conditions remain true:

```text
encoder session = LIVE
publish telemetry = HEALTHY
```

If either condition fails, the continuous-health timer resets.

Endpoints:

```text
PUT /go-live-sessions/:gameId/health-hold
GET /go-live-sessions/:gameId/health-hold
```

`POST /go-live-sessions/:gameId/confirm-live` now requires the configured continuous health hold to complete before the go-live session may transition to `LIVE`.

## Milestone 21.5 — Live broadcast watchdog and degraded-state detection

Confirmed production broadcasts are now monitored for runtime degradation.

Go-live sessions add:

```text
DEGRADED
degradedAt
degradationReason
```

Watchdog endpoint:

```text
POST /go-live-sessions/:gameId/watchdog
```

While the production session is `LIVE` or `DEGRADED`, the watchdog checks:

```text
encoder session = LIVE
publish telemetry = HEALTHY
```

If either condition fails, the production go-live session transitions to `DEGRADED` and records a reason.

If both conditions recover while the session is degraded, the session automatically returns to `LIVE`.

The operator UI polls the watchdog every 3 seconds while a production session is live or degraded.

The watchdog is operational only and does not modify authoritative game state.

## Milestone 21.6 — Live incident acknowledgement and operator recovery controls

A degraded production broadcast now supports explicit operator incident acknowledgement.

Go-live sessions track:

```text
incidentAcknowledgedAt
incidentAcknowledgedBy
```

Endpoints:

```text
POST /go-live-sessions/:gameId/incident/acknowledge
POST /go-live-sessions/:gameId/incident/retry-watchdog
```

Only `DEGRADED` sessions may be acknowledged.

Acknowledgement does not hide or resolve the degradation. It records operator awareness.

Retrying the watchdog clears the acknowledgement and explicitly re-runs runtime/publish health evaluation.

If health is restored, the existing watchdog recovery path returns the go-live session to `LIVE`. If health is still degraded, the session remains `DEGRADED`.

## Milestone 21.7 — Emergency stop / broadcast kill switch

Production go-live sessions now support an `EMERGENCY_STOPPED` state with timestamp and reason.

Emergency stop suppresses automatic encoder recovery, stops the encoder through the existing runtime stop path, and requires an explicit go-live reset before another start.

Endpoint:

```text
POST /go-live-sessions/:gameId/emergency-stop
```

## Milestone 21.8 — Go-live audit timeline and session history

SportsOS now persists the production go-live lifecycle separately from the lower-level encoder runtime audit.

Recorded event types include:

```text
ARMED
START_REQUESTED
STARTING
LIVE_CONFIRMED
DEGRADED
RECOVERED
INCIDENT_ACKNOWLEDGED
INCIDENT_RETRY
STOP_REQUESTED
COMPLETE
EMERGENCY_STOP
RESET
ERROR
```

API:

```text
GET /go-live-sessions/:gameId/audit?limit=100
```

The audit store keeps the newest 2000 events globally and limits individual API requests to 250 events.

The operator UI exposes the latest go-live session history, including incident details and operator acknowledgement information.

## Milestone 21.8 — Go-live audit timeline and session history

SportsOS now persists the production go-live lifecycle separately from the lower-level encoder runtime audit.

Recorded event types include:

```text
ARMED
START_REQUESTED
STARTING
LIVE_CONFIRMED
DEGRADED
RECOVERED
INCIDENT_ACKNOWLEDGED
INCIDENT_RETRY
STOP_REQUESTED
COMPLETE
EMERGENCY_STOP
RESET
ERROR
```

API:

```text
GET /go-live-sessions/:gameId/audit?limit=100
```

The audit store keeps the newest 2000 events globally and limits individual API requests to 250 events.

The operator UI exposes the latest go-live session history, including incident details and operator acknowledgement information.

## Milestone 21.9 — Game-day go-live readiness / final operator preflight

SportsOS provides one final production go-live preflight combining streaming readiness, schedule window, go-live state, emergency-stop lock, degraded incident status, encoder recovery state, encoder availability, and schedule countdown.

Endpoint:

```text
GET /go-live-sessions/:gameId/game-day-preflight
```

Arming is blocked when this final preflight fails.
