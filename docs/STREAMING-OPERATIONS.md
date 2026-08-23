# Streaming Operations

Milestone 20 begins the streaming-output and encoder-operations layer.

## Authority boundary

Streaming configuration is operational metadata.

It must never become authoritative for:

- score
- clock
- period
- penalties
- game lifecycle
- scoreboard assignment

## Milestone 20.1 — Stream destination profile

Each game may have one persisted stream destination profile.

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

Profile fields:

- game ID
- enabled state
- protocol
- ingest URL
- stream name
- credential reference
- latency mode
- status
- last error
- updated timestamp

## Credential boundary

SportsOS 20.1 does **not** place a raw stream key in the public API.

The profile stores:

```text
credentialRef
```

rather than a public credential value.

Future milestones should resolve that reference through a server-side credential provider or secret store.

## API

Operator routes:

```text
GET    /stream-destinations/:gameId
PUT    /stream-destinations/:gameId
DELETE /stream-destinations/:gameId
```

Public status route:

```text
GET /public/games/:gameId/stream-status
```

The public route exposes only:

- enabled state
- protocol
- status

It never returns ingest URLs or credential references.

## Milestone 20.2 — Stream destination operator UI and validation

Scoreboard Operations now includes a Stream Destination panel.

Operators can:

- select a game
- enable or disable streaming
- choose RTMP/RTMPS or SRT
- choose latency mode
- configure ingest URL
- configure a display stream name
- provide a server-side credential reference
- save/reset the destination

Client validation requires:

- RTMP ingest URLs to begin with `rtmp://` or `rtmps://`
- SRT ingest URLs to begin with `srt://`
- a credential reference whenever streaming is enabled

The UI explicitly warns operators not to paste raw stream keys into the credential-reference field.

## Milestone 20.3 — Destination readiness and connection probe

Operators can run a safe TCP reachability check against the configured ingest endpoint.

The probe records readiness, latency, timestamp, and error state without transmitting credentials or publishing media.

## Milestone 20.4 — Encoder session model and control foundation

SportsOS now has a persisted encoder-session control model.

States:

```text
STOPPED
STARTING
LIVE
STOPPING
ERROR
```

Operator API:

```text
GET  /encoder-sessions/:gameId
POST /encoder-sessions/:gameId/start
POST /encoder-sessions/:gameId/stop
```

Start is blocked unless the stream destination is enabled and `READY`.

Milestone 20.4 is intentionally **control-plane only**. It does not:

- spawn FFmpeg
- resolve stream credentials
- publish media
- mark a session LIVE automatically

The start action arms the session as `STARTING`. A later milestone will connect this model to an actual encoder runtime and explicitly promote the session to `LIVE` only after the runtime confirms publishing.

## Milestone 20.5 — Encoder runtime adapter and FFmpeg process control

SportsOS can now launch and stop a real FFmpeg child process for an armed encoder session.

Runtime properties:

- `spawn()` is used with `shell: false`
- the FFmpeg binary defaults to `ffmpeg`
- `SPORTSOS_FFMPEG_PATH` may override the binary path
- the source URL is supplied server-side by `SPORTSOS_ENCODER_SOURCE_URL` or `SPORTSOS_ENCODER_SOURCE_URL_TEMPLATE`
- `{gameId}` may be used in the source template
- credentials are resolved server-side from `env://VARIABLE_NAME`
- resolved credential values are not returned by the API and are not logged by SportsOS
- stop sends `SIGTERM`, then `SIGKILL` after 5 seconds if required

Credential references supported by this milestone:

```text
env://MY_STREAM_KEY
```

The referenced environment variable must exist in the API container.

Output behavior:

- RTMP/RTMPS uses FLV output
- SRT uses MPEG-TS output
- audio/video streams are copied without transcoding in this first runtime adapter

Session transition:

```text
READY destination
      ↓
STARTING
      ↓
FFmpeg survives initial 2-second launch window
      ↓
LIVE
```

Unexpected FFmpeg exit moves the encoder session to `ERROR`.

This launch-health window confirms process survival only. Later milestones should add encoder telemetry and upstream publishing confirmation before treating `LIVE` as full end-to-end stream health.

## Milestone 20.6 — Encoder telemetry and publish health

FFmpeg now emits machine-readable progress through `-progress pipe:1`.

SportsOS tracks frame count, FPS, bitrate, output size, output time, speed, and last progress timestamp.

Publish health states:

```text
IDLE
STARTING
HEALTHY
STALE
ERROR
```

A healthy runtime with no progress update for more than 10 seconds is reported as `STALE`.

API:

```text
GET /encoder-sessions/:gameId/telemetry
```

The operator UI polls telemetry every 2 seconds while the encoder is starting or live.

## Milestone 20.7 — Encoder recovery and automatic restart policy

Unexpected FFmpeg exits now trigger bounded automatic recovery.

Defaults:

```text
max restart attempts: 3
base restart backoff: 3000 ms
maximum backoff: 30000 ms
```

Environment overrides:

```text
SPORTSOS_ENCODER_MAX_RESTARTS
SPORTSOS_ENCODER_RESTART_BACKOFF_MS
```

Recovery states:

```text
IDLE
SCHEDULED
RESTARTING
EXHAUSTED
```

Restart attempts are bounded. Once the configured maximum is exceeded, SportsOS enters `EXHAUSTED` and stops retrying automatically.

Operator-requested stop does not trigger automatic recovery.

The operator UI shows recovery state, attempt count, and next retry timestamp.

## Milestone 20.8 — Encoder runtime audit and failure history

SportsOS now persists encoder lifecycle and recovery events.

Audit event types:

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

API:

```text
GET /encoder-sessions/:gameId/audit?limit=50
```

The audit store is bounded to the newest 1000 events globally and the API limits a single request to 200 events.

The operator UI shows recent encoder runtime history alongside telemetry and recovery state.

## Milestone 20.9 — Streaming readiness and operator preflight

Streaming start now has an explicit server-side preflight.

Checks:

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

The encoder start API rejects the request with HTTP 409 when preflight is not ready.

Operator API:

```text
GET /encoder-sessions/:gameId/preflight
```

The operator UI shows every check as PASS or FAIL and provides a dedicated **Run Streaming Preflight** action.

This preflight does not modify game state and does not start media publishing.
