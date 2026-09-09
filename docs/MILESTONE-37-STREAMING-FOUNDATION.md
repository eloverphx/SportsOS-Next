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
