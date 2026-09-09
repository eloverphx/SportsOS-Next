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
