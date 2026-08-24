# Production Go-Live Operations Acceptance

Milestone 21.10 closes the first SportsOS production go-live orchestration sequence.

## Authority boundary

Go-live orchestration is operational only.

It must never become authoritative for:

- score
- game clock
- period
- penalties
- game lifecycle
- scoreboard assignment

Authoritative game state remains in the SportsOS game engine and API.

## Go-live lifecycle

Production go-live states:

```text
IDLE
ARMED
STARTING
LIVE
DEGRADED
STOPPING
COMPLETE
ERROR
EMERGENCY_STOPPED
```

Expected production path:

```text
IDLE
  ↓
ARMED
  ↓
STARTING
  ↓
LIVE
  ↓
STOPPING
  ↓
COMPLETE
```

Operational exception paths include:

```text
LIVE → DEGRADED → LIVE
LIVE → DEGRADED → EMERGENCY_STOPPED
STARTING → ERROR
```

## Scheduling

Go-live sessions may define:

- scheduled start
- early start window
- late start window
- optional auto-arm
- auto-arm lead time

Auto-arm may transition only to `ARMED`.

Auto-arm must never start FFmpeg automatically.

## Start-window enforcement

A scheduled start is allowed only while the configured start window is open.

Too-early and expired starts must be rejected.

## Streaming readiness

Go-live arm and start depend on the existing Milestone 20 streaming readiness layer.

Streaming readiness includes:

- destination profile
- destination enabled
- ingest URL
- credential reference
- destination reachability
- encoder availability
- recovery state
- source configuration

## Final game-day preflight

The final game-day preflight includes:

```text
STREAMING_PREFLIGHT
START_WINDOW
GO_LIVE_STATE
EMERGENCY_STOP
DEGRADED_INCIDENT
RECOVERY_EXHAUSTION
ENCODER_AVAILABILITY
SCHEDULE_COUNTDOWN
```

Arming must fail when this final preflight is blocked.

## Health hold

A momentary encoder live state is not sufficient for production confirmation.

The encoder must remain:

```text
session = LIVE
telemetry = HEALTHY
```

for the configured health-hold duration.

Default:

```text
10 seconds
```

Allowed:

```text
0–120 seconds
```

If health is interrupted during the hold, the hold resets.

## Live watchdog

Confirmed production broadcasts are watched for:

- encoder session no longer LIVE
- publish telemetry no longer HEALTHY

If either condition fails, the go-live session becomes:

```text
DEGRADED
```

The watchdog records:

- degraded timestamp
- degradation reason

If runtime health recovers, the go-live session may return to `LIVE`.

## Incident acknowledgement

A degraded incident may be acknowledged by an operator.

Acknowledgement records awareness only.

It must not:

- hide degradation
- clear the degraded state
- claim recovery
- modify game state

Operators may explicitly retry watchdog evaluation after taking corrective action.

## Emergency stop

Emergency stop is the production kill switch.

It:

- suppresses encoder recovery
- stops the encoder runtime
- records timestamp
- records reason
- transitions to `EMERGENCY_STOPPED`

An emergency-stopped session must be reset before another production start.

## Go-live audit

Production lifecycle history is persisted separately from the lower-level encoder runtime audit.

Events include:

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

## Operator production acceptance sequence

Before game day:

1. Select the intended game.
2. Confirm stream destination settings.
3. Run destination probe.
4. Confirm stream destination is READY.
5. Configure scheduled start if applicable.
6. Confirm early/late start window.
7. Configure auto-arm if desired.
8. Confirm auto-arm does not start the encoder.
9. Configure confirmation health hold.
10. Run streaming readiness preflight.
11. Run final Game-Day Go-Live Preflight.
12. Confirm all final checks PASS.
13. Arm Go-Live.
14. Start Go-Live during the allowed window.
15. Confirm encoder reaches LIVE.
16. Confirm publish telemetry remains HEALTHY for the configured hold.
17. Confirm production session transitions to LIVE.
18. Confirm watchdog reports healthy state.
19. Test or simulate a controlled degradation.
20. Confirm production session becomes DEGRADED.
21. Acknowledge the incident.
22. Confirm acknowledgement does not falsely clear degradation.
23. Restore runtime health.
24. Retry or allow watchdog evaluation.
25. Confirm session returns to LIVE.
26. Perform normal stop.
27. Confirm COMPLETE.
28. Test emergency stop in a non-production test session.
29. Confirm encoder stops and recovery is suppressed.
30. Confirm session becomes EMERGENCY_STOPPED.
31. Confirm a new start is blocked until reset.
32. Confirm go-live audit history explains the full sequence.

## Required validation

Run:

```bash
npm run typecheck && npm test
```

Then:

```bash
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

For a real streaming runtime test, the Milestone 20 FFmpeg/source/credential configuration must also be present.

## Closeout

Milestones 21.1 through 21.10 establish:

- production go-live session lifecycle
- scheduled start windows
- auto-arm countdown
- continuous health confirmation
- live watchdog and degraded state
- incident acknowledgement
- emergency broadcast stop
- go-live session audit
- final game-day preflight
- production go-live acceptance

Future production-streaming work should extend these contracts rather than duplicate lifecycle, safety, audit, or readiness logic.
