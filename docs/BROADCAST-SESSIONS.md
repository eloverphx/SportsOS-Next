# Broadcast Sessions

Milestone 19 begins the broadcast/streaming operations layer on top of the existing public scoreboard and broadcast overlay.

## Existing overlay

SportsOS already exposes a realtime broadcast overlay:

```text
/games/:id/overlay
```

The overlay consumes the same public authoritative scoreboard snapshot as:

```text
/games/:id/scoreboard
```

Milestone 19 preserves that architecture.

## Milestone 19.1

Broadcast presentation settings are now represented by a persisted per-game broadcast session profile.

Profile fields:

- game ID
- enabled state
- broadcast title
- sponsor image URL
- show/hide power-play indicator
- show/hide team logos
- last update timestamp

API:

```text
GET    /broadcast-sessions/:gameId
PUT    /broadcast-sessions/:gameId
DELETE /broadcast-sessions/:gameId
GET    /public/games/:gameId/broadcast-session
```

The public endpoint returns the profile only when the broadcast session is enabled.

## Architecture boundary

Broadcast presentation configuration must not become authoritative game state.

Score, clock, period, penalties, teams, and lifecycle remain sourced from the authoritative public scoreboard snapshot.

Future Milestone 19 work should make the overlay consume this profile rather than encode persistent presentation configuration only in URL query parameters.

## Milestone 19.2 — Overlay profile consumption

The broadcast overlay loads the persisted public broadcast-session profile.

Presentation precedence:

```text
URL override
    ↓
saved broadcast-session profile
    ↓
existing overlay default
```

Supported settings:

- title
- sponsor URL
- power-play visibility
- team-logo visibility

Temporary query overrides remain supported:

```text
title
sponsorUrl
showPowerPlay=0|1
showTeamLogos=0|1
```

Authoritative game state continues to come only from the public scoreboard snapshot.

## Milestone 19.3 — Broadcast session operator UI

Scoreboard Operations now includes a Broadcast Session panel.

Operators can:

- select a game
- load its persisted broadcast profile
- enable or disable the broadcast session
- set the broadcast title
- set a sponsor image URL
- show/hide the power-play indicator
- show/hide team logos
- save changes
- reset the game to overlay defaults
- open the live overlay in a new window
- view an embedded live overlay preview

The preview uses the real overlay route and therefore continues to consume authoritative public scoreboard game state.

## Milestone 19.4 — Realtime broadcast profile updates

Broadcast-session saves and resets now emit realtime events to the game’s public realtime room.

Events:

```text
broadcast-session:updated
broadcast-session:deleted
```

The overlay listens for both events.

This means an already-open overlay immediately reflects:

- title changes
- sponsor changes
- power-play visibility
- team-logo visibility
- profile reset

without requiring a manual browser refresh.

Game state realtime and broadcast-profile realtime remain separate concerns.

## Milestone 19.5 — Scene presets and sponsor rotation foundation

Broadcast-session profiles now support:

- `STANDARD`
- `MINIMAL`
- `SPONSOR_FOCUS`

They also support a sponsor rotation list and configurable rotation interval.

The operator UI accepts one sponsor URL per line and a minimum rotation interval of 3 seconds.

The overlay rotates through saved sponsor URLs without altering authoritative game state. Scene preset is exposed on the overlay as `data-scene-preset` for presentation-specific styling in later milestones.

## Milestone 19.6 — Scene preset styling

Scene presets now alter the visual presentation of the live overlay.

### STANDARD

Uses the existing full scoreboard presentation.

### MINIMAL

Reduces visual density by:

- hiding long team-name text
- using smaller logo treatment
- hiding secondary power-play text
- tightening the scoreboard footprint

### SPONSOR_FOCUS

Keeps the score visible while:

- slightly reducing the scoreboard bar emphasis
- enlarging the sponsor strip
- increasing sponsor image size
- hiding secondary power-play text

These presets change presentation only. Score, clock, period, penalties, and game lifecycle remain sourced from authoritative SportsOS game state.

## Milestone 19.7 — Goal and penalty effect presentation

The live overlay now consumes the existing:

```text
scoreboard:effect
```

realtime event.

Supported effect types:

- `GOAL`
- `PENALTY`
- `PENALTY_ENDED`

The overlay displays a temporary presentation card containing available team, player, jersey, infraction, and penalty-minute information.

Default display duration:

- goal: 5 seconds
- penalty / penalty ended: 4 seconds

Effects are presentation-only. They do not create, alter, or reconcile game state. Authoritative scoring and penalty state still come from the SportsOS game engine and public scoreboard snapshot.

## Milestone 19.8 — Broadcast sound controls and audio policy

Broadcast-session profiles now include an explicit audio policy.

Audio is disabled by default.

When enabled, operators may configure URLs for:

- goal
- penalty
- horn
- intermission-complete

The overlay consumes the existing:

```text
scoreboard:sound
```

realtime channel and selects the configured sound by event type.

Playback failures caused by browser or OBS autoplay policy are ignored. Audio playback must never alter overlay state, game state, scoring, lifecycle, or scoreboard synchronization.

This milestone intentionally keeps sound sources configurable rather than embedding specific copyrighted media in the repository.

## Milestone 19.9 — Audio test controls and readiness

The Broadcast Session operator panel now includes local audio test controls.

Tests are available for:

- goal audio
- penalty audio
- horn audio
- intermission-complete audio

These tests play the configured URL directly in the operator browser. They do **not** emit `scoreboard:sound`, create a game event, alter score, or mutate broadcast/game state.

Audio readiness reports:

- `Audio disabled` when audio is intentionally muted
- `Audio not ready` when audio is enabled with no configured sound URLs
- `Audio ready` when at least one sound source is configured

Browser autoplay or media playback failure is isolated from SportsOS state and operator controls.
