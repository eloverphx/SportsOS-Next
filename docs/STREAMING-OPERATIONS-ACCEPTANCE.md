# Streaming Operations Acceptance

Milestone 20.10 closes the first SportsOS streaming-output and encoder-operations sequence.

## Authority boundary

Streaming and encoder operations are operational subsystems. They must never become authoritative for score, clock, period, penalties, game lifecycle, or scoreboard assignment.

Authoritative game state remains in the SportsOS API/game engine.

## Stream destination profile

Each game may have a persisted stream destination profile.

Supported protocols:

```text
RTMP
SRT
```

Supported latency modes:

```text
NORMAL
LOW
ULTRA_LOW
```

Destination states:

```text
DISABLED
CONFIGURED
READY
LIVE
ERROR
```

The public API exposes only redacted stream status. It does not expose ingest URL, credential reference, resolved credential, or stream key.

## Credential boundary

Credential references use server-side references such as:

```text
env://MY_STREAM_KEY
```

Resolved credential values must never be returned by the API or logged by SportsOS.

## Destination readiness probe

Operators may run a server-side reachability check. The probe opens a short TCP connection, records reachability, latency, and timestamp, and marks the destination READY or ERROR.

The probe does not transmit credentials or publish media.

## Encoder session lifecycle

Encoder session states:

```text
STOPPED
STARTING
LIVE
STOPPING
ERROR
```

Start requires a READY stream destination. Stop is operator-controlled and must suppress automatic restart.

## FFmpeg runtime

The encoder runtime uses `spawn()` with `shell: false`, supports a configurable FFmpeg binary path and server-side source URL configuration, supports RTMP/RTMPS FLV output and SRT MPEG-TS output, and sends SIGTERM before SIGKILL fallback.

## Encoder telemetry

SportsOS collects machine-readable FFmpeg progress.

Tracked metrics include frame, FPS, bitrate, total output size, output time, speed, and last progress timestamp.

Publish-health states:

```text
IDLE
STARTING
HEALTHY
STALE
ERROR
```

A runtime with no fresh progress for more than the stale threshold is reported as STALE.

## Automatic recovery

Recovery states:

```text
IDLE
SCHEDULED
RESTARTING
EXHAUSTED
```

Recovery is bounded by maximum restart attempts and restart backoff. Automatic retry stops once attempts are exhausted. Intentional operator stop does not trigger recovery.

## Runtime audit

SportsOS persists encoder runtime history.

Audited events include:

```text
START_REQUESTED
RUNTIME_STARTED
RUNTIME_LIVE
STOP_REQUESTED
RUNTIME_STOPPED
RUNTIME_ERROR
RESTART_SCHEDULED
RESTARTING
RESTART_EXHAUSTED
```

## Streaming readiness preflight

Encoder start is protected by server-side readiness validation.

Checks include:

```text
DESTINATION_PRESENT
DESTINATION_ENABLED
INGEST_URL
CREDENTIAL_REFERENCE
DESTINATION_PROBE
ENCODER_STATE
RECOVERY_STATE
SOURCE_CONFIGURATION
```

Start must return HTTP 409 when readiness fails.

## Operator acceptance sequence

Before production streaming:

1. Select the intended game.
2. Confirm stream destination profile exists.
3. Confirm streaming is enabled.
4. Confirm RTMP/RTMPS or SRT protocol.
5. Confirm ingest URL.
6. Confirm credential reference is server-side and not a raw stream key.
7. Run destination probe.
8. Confirm destination reaches READY.
9. Run Streaming Readiness preflight.
10. Confirm every required check passes.
11. Arm encoder start.
12. Confirm runtime progresses from STARTING to LIVE.
13. Confirm Publish Health becomes HEALTHY.
14. Confirm FPS, bitrate, speed, and last progress update.
15. Confirm runtime history records the start.
16. Stop the encoder.
17. Confirm STOPPED.
18. Confirm no automatic restart occurs after intentional stop.
19. Simulate or observe a controlled runtime failure during testing.
20. Confirm recovery is bounded and audit history explains the failure/retry sequence.

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

For a real encoder runtime test, the API container also requires `SPORTSOS_ENCODER_SOURCE_URL` or `SPORTSOS_ENCODER_SOURCE_URL_TEMPLATE`, plus the environment variable referenced by the destination `credentialRef`.

## Closeout

Milestones 20.1 through 20.10 establish stream destination profiles, operator destination configuration, safe reachability probing, encoder session state, real FFmpeg process control, telemetry and publish health, bounded automatic recovery, runtime audit history, streaming readiness preflight, and streaming operations acceptance.

Future streaming work should extend these contracts rather than duplicate destination, encoder, telemetry, or readiness logic.
