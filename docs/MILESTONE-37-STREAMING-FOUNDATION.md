# Milestone 37 — Streaming Foundation

Milestone 37 pivots SportsOS from infrastructure/security hardening into the
durable product foundation for live and archived sports video.

Tournament and ESP work remain preserved but frozen.

## M37.1 — Durable persistence schema

M37.1 is intentionally schema-only. It does not replace the existing go-live
coordinator, change login behavior, or expose new public streaming routes.

The increment adds:

- durable authenticated-session records using hashed refresh-token material;
- media ownership, visibility, capture time, duration, and checksum metadata;
- explicit per-user media access grants;
- durable recording records tied to organizations, games, owners, and media
  assets;
- durable stream-session records tied to games and recordings;
- recording-to-game-event anchors for future clip extraction.

## Authoritative event rule

`game_events` remains the source of truth for scoring and player events.

`recording_event_anchors` references an existing `game_events.id`; it does not
create game events. Future AI replay/highlight features may rank or select
video around authoritative events, but they must not invent goals, penalties,
players, or event timestamps.

## Privacy baseline

Media visibility defaults to organization scope.

Private media is represented explicitly and per-user grants are stored
separately. Future API work must authorize access by ownership, organization,
or explicit grant before returning archived youth/player media.

## Follow-on increments

M37.2 should implement account/session lifecycle:

- signup;
- admin approval;
- session issuance and rotation;
- revocation/logout;
- account status enforcement.

M37.3 should implement media/recording ownership APIs and authorization.

M37.4 should persist and bridge the existing go-live coordinator into durable
stream-session and recording records.

M37.5 should establish authoritative event-to-video synchronization for clip
generation.

## M37.2 — Signup, approval, and durable sessions

M37.2 adds the account lifecycle required before public streaming/media access:

- self-signup into an existing active organization;
- new self-signups default to the `viewer` role and `PENDING` account status;
- organization member managers can list, approve, or reject pending accounts;
- existing accounts remain `ACTIVE` by default for backward compatibility;
- pending, suspended, rejected, or missing accounts are blocked from
  authenticated API access;
- login continues returning the existing access-token field while also issuing
  a durable refresh session;
- refresh tokens are random opaque values and only their SHA-256 hashes are
  persisted;
- refresh rotates the stored refresh token and extends its 30-day session
  lifetime;
- logout revokes the durable session.

The existing 8-hour access-token lifetime is retained in this increment to
avoid an unrelated compatibility change. A later security-specific increment
may shorten access-token lifetime after dashboard/mobile clients are proven to
rotate refresh sessions reliably.

## M37.3 — Media and recording ownership APIs

M37.3 enforces the persistence model introduced in M37.1.

Media object access now follows an explicit visibility policy:

- `PUBLIC`: anonymous object delivery is allowed;
- `ORGANIZATION`: an active user in the same organization with stream-read
  permission may view the object;
- `PRIVATE`: access is limited to the owner, an explicit grantee, or a
  same-organization stream manager;
- stream-management authority does not implicitly cross organization
  boundaries.

Existing and future `logos/` objects are intentionally `PUBLIC` because
scoreboard and overlay clients render those assets without an authenticated API
session.

Media owners and same-organization stream managers can change visibility and
manage per-user grants. Grants can only target active users in the same
organization.

Recording APIs now provide:

- same-organization recording listing with visibility filtering;
- recording metadata reads;
- recording creation by stream managers;
- recording ownership;
- optional binding to a game in the same organization;
- optional binding to a manageable `VIDEO` media asset in the same
  organization.

M37.3 does not add large video upload transport. Video ingestion needs a
streaming/chunked or object-storage-oriented path rather than expanding the
existing small request body limit or placing large video payloads into JSON.

The existing go-live coordinator is unchanged in M37.3. Durable go-live
bridging remains the next increment.

## M37.4 — Durable go-live bridge

M37.4 mirrors the proven file-backed go-live state machine into the durable
streaming schema without replacing or rewriting the existing coordinator.

For canonical numeric game IDs, critical transitions now synchronize to the
database:

- arm creates or resumes a durable stream-session lifecycle;
- starting records durable runtime start metadata;
- live confirmation creates a `LIVE` recording row and binds it to the stream
  session;
- watchdog degradation/recovery mirrors durable status;
- normal stop transitions the recording from `RECORDING` to `PROCESSING`;
- encoder/start errors and emergency stops mark an existing live recording
  `FAILED`;
- reset closes an unfinished durable lifecycle as `ERROR` while preserving its
  history.

Legacy/test go-live identifiers that are not positive integer database game IDs
remain supported by the file-backed coordinator and are deliberately skipped by
the database bridge.

### Organization-owned live records

The pre-M37 go-live API does not yet require an authenticated user on every
control route. M37.4 therefore permits `created_by_user_id` on stream sessions
and `owner_user_id` on live recordings to be null. Null represents a
system/organization-owned runtime record; it does **not** fabricate a user.

User-created/uploaded recordings remain user-owned. Same-organization stream
managers continue to administer organization-owned live recordings.

### Failure behavior

The existing live state machine remains authoritative for runtime control in
this increment. A database synchronization failure is logged as an operational
error but does not stop or roll back an encoder that has already started.

A later operational increment should add durable reconciliation/health
telemetry so a temporary database outage can be repaired automatically.

M37.4 still does not implement the large-video ingestion pipeline or attach a
finished media asset to the processing recording. Those are separate streaming
transport/storage concerns.

## M37.5 — Authoritative event-to-recording anchors

M37.5 connects the scorekeeper event engine to the durable recording timeline.

When a non-replayed game event is created while that game's durable recording
is actively `RECORDING`, SportsOS creates a `recording_event_anchors` row in the
**same database transaction** as the authoritative `game_events` mutation.

The recording offset is derived only from:

1. the authoritative game event's database `created_at` timestamp; and
2. the durable recording's `started_at` timestamp.

No client, AI process, or highlight selector is allowed to submit or modify that
offset. The anchor source is `SCOREKEEPER`.

If no active recording exists, no anchor is fabricated. If an event timestamp
predates the recording start, no anchor is created.

### Read model

Authorized recording viewers can read:

`GET /recordings/:id/event-anchors`

Each anchor includes:

- authoritative game-event ID;
- event type and team side;
- period and authoritative game clock remaining;
- primary player ID/name/jersey number when present;
- assist player IDs when present;
- recording offset;
- event and void timestamps;
- whether the event remains eligible for highlights;
- a deterministic suggested clip window.

Voiding a game event does not erase its recording anchor. The historical
relationship remains auditable, while `eligibleForHighlights` becomes false.

### Highlight boundary

M37.5 introduces deterministic clip-window math with a default 8-second
pre-roll and 5-second post-roll. This is only a candidate window around an
authoritative event.

Future AI may rank, select, combine, caption, or summarize these candidate
clips. AI must never create a goal/penalty event, assign a player to an event,
or invent/change the authoritative event timestamp or recording offset.

## M37.6 — Durable authoritative clip-job queue

M37.6 adds a durable queue between authoritative event anchors and the future
video-processing worker.

Authorized stream managers can request:

`POST /recordings/:id/event-anchors/:eventId/clip-jobs`

The request accepts no body timing fields. SportsOS loads the existing
authoritative recording/event anchor and derives the candidate clip window
server-side using the M37.5 deterministic clip-window rules.

Voided events are rejected for new clip jobs.

Duplicate requests from the same user for the same recording, game event,
clip window, and selection source resolve to the same durable job rather than
creating duplicate work.

Authorized recording viewers can inspect:

`GET /recordings/:id/clip-jobs`

Clip jobs track:

- organization, recording, and authoritative game-event identity;
- requesting user;
- selection source;
- derived start/end offsets;
- processing state (`PENDING`, `PROCESSING`, `READY`, `FAILED`, `CANCELLED`);
- retry attempt count;
- error text;
- eventual output `media_assets` linkage.

### AI boundary

The durable schema reserves `AI_SELECTION` for a future internal highlight
selector. That means AI may eventually select an **existing authoritative
event anchor** for clip generation.

There is intentionally no public API in M37.6 that accepts `AI_SELECTION`,
arbitrary event IDs without a recording anchor, or client-supplied start/end
times. AI still cannot create or alter scorekeeper events, timestamps, players,
or recording offsets.

### Processing boundary

M37.6 does not execute FFmpeg and does not mutate clip jobs to `READY`.
The repository currently has no FFmpeg dependency or background clip worker.
The next processing increment can claim `PENDING` jobs, render from the
recording media, create a derived `VIDEO` media asset, and atomically attach
that asset to the clip job while preserving the media visibility rules.

## M37.7 — Durable clip worker and FFmpeg rendering

M37.7 adds the first background video-processing worker.

The worker is a separate Compose process built from the API image. The runtime
image includes system FFmpeg, while the normal API process remains responsible
for HTTP and realtime work.

### Claim and recovery model

Workers claim eligible `PENDING` clip jobs transactionally with
`FOR UPDATE SKIP LOCKED`.

A claimed job becomes `PROCESSING`, records `claimed_at`, and increments its
attempt count. A `PROCESSING` lease older than 15 minutes may be reclaimed so a
container crash does not permanently strand the job.

Jobs are not claimed until the recording has an attached same-organization
`VIDEO` media asset. This allows highlight requests to be queued while a live
recording is still in progress and processed only after the source media exists.

Failed processing attempts return to `PENDING` until three attempts have been
made. The third failed attempt becomes `FAILED`.

### Rendering

The worker:

1. downloads the recording's source video from MinIO to an isolated temporary
   directory;
2. uses the server-derived `start_ms` / `end_ms` already persisted on the clip
   job;
3. invokes FFmpeg with a fixed argument array and no shell;
4. re-encodes H.264/AAC MP4 with `+faststart`;
5. computes SHA-256 and output size;
6. uploads to a deterministic `clips/<year>/job-<id>.mp4` MinIO key;
7. creates a derived `VIDEO` `media_assets` row;
8. inherits the source media asset's owner, visibility, and explicit access grants;
9. atomically links the new media asset and marks the clip job `READY`.

The deterministic object key makes retry behavior safer: a retry replaces the
same job output rather than creating a new uncontrolled object name.

### Failure boundary

If MinIO upload succeeds but database finalization fails during the same worker
attempt, the worker tries to remove that output object before returning the job
to its retry state.

A hard process/container failure can still leave a temporary object in MinIO;
the deterministic job key prevents unbounded duplicates and a later retry
reuses the same destination. A future storage-reconciliation increment may
sweep orphaned derived objects.

### Authoritative-data boundary

The worker never updates `game_events` or `recording_event_anchors`. It consumes
only the durable clip window produced from the authoritative M37.5/M37.6 chain.

AI remains downstream: it may eventually select existing authoritative anchors,
but it cannot manufacture game events, players, timestamps, recording offsets,
or arbitrary render windows.

## M37.8 — Source recording capture and finalization

M37.8 connects the existing live broadcast lifecycle to an actual durable source VIDEO asset.

- The existing outbound RTMP/SRT encoder remains unchanged.
- Archive capture starts only after the go-live session is confirmed LIVE and the durable LIVE recording row has been persisted.
- Capture runs as a separate FFmpeg process and writes a Matroska work file beneath `SPORTSOS_DATA_DIR/recordings/in-progress`.
- Normal stop first persists COMPLETE/PROCESSING, then stops and finalizes the capture.
- Finalization first attempts a stream-copy MP4 remux with `+faststart`; incompatible source codecs fall back to H.264/AAC.
- The finalized MP4 is uploaded to MinIO with SHA-256, duration, VIDEO kind, and ORGANIZATION visibility.
- `media_assets` creation and `recordings.media_asset_id`/READY linkage occur in one database transaction.
- An object uploaded before a failed database transaction is removed from MinIO.
- Failed finalization marks the PROCESSING recording FAILED and leaves local work files available for operator recovery.
- Emergency stop terminates capture without publishing the partial file as a READY archive.
- Scorekeeper game events and recording event anchors remain authoritative and are not modified.

## M37.9 — Authenticated streaming dashboard

M37.9 exposes the durable recording lifecycle in the existing SportsOS dashboard.

- The sidebar Streaming placeholder now routes to `/streaming` and remains permission-gated by `STREAM_READ`.
- The page is protected by the existing `AuthGate` and loads `GET /recordings?limit=100` through the existing authenticated `api()` client.
- Operators can see live capture, processing, ready archive, failed, and archived counts plus per-recording game linkage, duration, timestamps, source, and attached media asset state.
- The page refreshes every 30 seconds and supports manual refresh.
- Large recording playback is intentionally not implemented by embedding protected `/media/:id` directly in a `<video>` element because the current authorization model requires a bearer header. A dedicated authenticated range-streaming path will be implemented separately rather than leaking bearer credentials through URLs.

## M37.10 — Authenticated recording playback and HTTP Range streaming

M37.10 adds browser-native playback for finalized video assets without placing the normal SportsOS bearer token in a media URL.

- An authenticated `POST /media/assets/:id/playback-session` requires `STREAM_READ`, reuses the existing media visibility/ownership/grant policy, only accepts `VIDEO` assets, and issues a five-minute HMAC-signed playback ticket.
- The ticket is stored as an `HttpOnly`, `SameSite=Lax` cookie scoped to `/media/playback/:id`; `Secure` is added when the request is HTTPS.
- `GET /media/playback/:id` accepts only a valid unexpired ticket for that exact asset and organization.
- Playback supports normal full-object responses and single HTTP byte ranges. Valid ranges return `206 Partial Content` with `Accept-Ranges`, `Content-Range`, and exact `Content-Length`; malformed or unsatisfiable ranges return `416` with `Content-Range: bytes */<size>`.
- Partial reads use MinIO `getPartialObject`, avoiding full-object downloads for browser seeking.
- The streaming dashboard requests the playback session with credentials enabled and renders a native `<video controls>` player only for `READY` recordings with an attached media asset.
- The standard bearer token remains in the existing authenticated API client and is never copied into playback URLs or query strings.
