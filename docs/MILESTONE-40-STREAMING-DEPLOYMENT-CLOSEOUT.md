# Milestone 40 — Streaming Deployment Closeout

## Status

COMPLETE

Milestone 40 establishes the deployment and operational baseline for persistent
SportsOS live streaming and recording on the Unraid production environment.

## Acceptance Summary

### Persistent capture

- Recording capture runs under the dedicated capture supervisor.
- API restarts do not terminate a healthy supervisor-owned capture.
- The API can reconnect to an existing supervisor session.
- Supervisor restart does not infer or recreate LIVE sessions from database state.
- Interrupted LIVE broadcasts are not automatically resumed after an application restart.
- Orphaned or unattributed capture evidence is retained rather than silently deleted.

### Publisher reconnect

- Destination/publisher interruption does not terminate the recording capture.
- Publisher reconnect uses bounded retry and backoff.
- Explicit stop suppresses pending reconnect attempts.
- Exhausted reconnect state does not prevent an explicit new operator start.
- Publisher retry state remains process-local and is not treated as durable LIVE state.

### Recording finalization

- Recording failure updates are bound to the exact recording and game.
- Finalized object paths use the authoritative game ID.
- Raw capture is deleted only after successful durable persistence.
- Failed or unattributed capture evidence is retained for recovery.
- Controlled post-hardening recording acceptance completed successfully.

### Game-day workflow

- One-touch broadcast start performs prepare, start, health hold, LIVE confirmation,
  and recording capture checks.
- Primary dashboard action explicitly distinguishes start and stop operations.
- STOP remains available when publisher state fails but authoritative broadcast or
  recording state still requires shutdown.
- Scorekeeper and scoreboard navigation were streamlined for game-day use.
- Authentication resilience avoids unnecessary logout on transient server/network failures.

### Capture supervisor authentication

- API and capture supervisor use a shared internal supervisor token.
- Authenticated supervisor health requests return HTTP 200.
- Unauthenticated supervisor health requests return HTTP 401.
- Docker healthcheck authenticates to the supervisor.
- Supervisor port is not exposed as a host-facing application interface.

### Security closeout

The credentials known to have been exposed during deployment inspection were rotated:

- JWT signing secret
- MySQL SportsOS application password
- MinIO root secret

The internal capture-supervisor token was also configured.

No credential values are stored in this document or committed to the repository.

### Deployment cleanup

- Temporary M40 MediaMTX/source acceptance containers were removed.
- Temporary M40 compose overlays were removed.
- No active FFmpeg processes remained after acceptance.
- No in-progress recording artifacts remained after acceptance.
- Existing archived recording access was verified after MinIO credential rotation.

## Final Verification

Final M40 verification included:

- Full `npm run ci:verify` gate passing.
- API healthy.
- MySQL online.
- Redis online.
- MQTT online.
- MinIO online.
- Capture supervisor healthy.
- API/capture supervisor internal authentication verified.
- Working tree clean before closeout.
- Local and remote repository state verified.

## Operational Safety Rules Preserved

- The scoreboard/game-event system remains authoritative.
- Highlight generation may use AI for ranking and selection but cannot invent event
  timestamps, goals, penalties, players, or authoritative game facts.
- Authoritative highlight clip timing remains server-derived.
- Restarting an interrupted LIVE broadcast remains an explicit operator action.
- Automatic recovery is limited to capture that can be safely attributed to an exact
  durable recording.

## Follow-up Work

Items intentionally deferred beyond Milestone 40 include:

- Dedicated least-privilege MinIO application/service credentials instead of root credentials.
- Additional production destination/source configuration for real game trials.
- Browser-orchestration reduction for the start-health-confirm sequence.
- Review of encoder `startedAt` telemetry lifetime.
- Further operator/trial feedback and UX refinement.
