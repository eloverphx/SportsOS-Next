# Broadcast Operations Acceptance

Milestone 19.10 closes the first production-style broadcast operations sequence.

## Acceptance boundary

SportsOS broadcast operations are presentation-only.

They must never become authoritative for:

- score
- clock
- period
- penalties
- teams
- lifecycle
- scoreboard assignment

Authoritative game state continues to come from the SportsOS API and public scoreboard snapshot.

## Broadcast session profile

Each game may have a persisted broadcast-session profile containing:

- enabled state
- title
- sponsor URL
- team-logo visibility
- power-play visibility
- scene preset
- sponsor rotation URLs
- sponsor rotation interval
- audio enabled state
- goal sound URL
- penalty sound URL
- horn sound URL
- intermission-complete sound URL

## Overlay configuration precedence

Presentation precedence is:

```text
temporary URL override
        ↓
persisted broadcast-session profile
        ↓
overlay default
```

URL overrides remain useful for testing and one-off presentation changes.

## Realtime requirements

Open overlays must update without manual refresh when the persisted broadcast profile changes.

Realtime events:

```text
broadcast-session:updated
broadcast-session:deleted
scoreboard:effect
scoreboard:sound
```

Public overlay clients subscribe to the existing:

```text
game:<gameId>
```

realtime room.

## Scene presets

Supported presets:

```text
STANDARD
MINIMAL
SPONSOR_FOCUS
```

STANDARD preserves the full scoreboard layout.

MINIMAL reduces presentation density.

SPONSOR_FOCUS keeps the game score visible while increasing sponsor prominence.

## Sponsor rotation

Broadcast profiles may include multiple sponsor URLs.

The overlay:

- rotates through configured sponsors
- uses the configured interval
- enforces a minimum interval
- resets cleanly when the profile changes

Sponsor rotation is presentation-only.

## Broadcast effects

The overlay consumes:

```text
scoreboard:effect
```

Supported effects:

```text
GOAL
PENALTY
PENALTY_ENDED
```

Effects are temporary visual treatments and automatically clear.

They do not create or modify scoring or penalty state.

## Broadcast audio

The overlay consumes:

```text
scoreboard:sound
```

Supported sound event types include:

```text
GOAL
PENALTY
HORN
INTERMISSION_COMPLETE
```

Audio is disabled by default.

Operators explicitly enable audio and configure media URLs.

Browser or OBS autoplay rejection must not affect overlay rendering, game state, or operator controls.

## Operator audio testing

The Broadcast Session panel provides local audio tests.

Audio tests:

- play only in the operator browser
- do not emit scoreboard sound events
- do not create game events
- do not alter game or broadcast state

## Operator acceptance sequence

Before a production broadcast:

1. Select the intended game.
2. Confirm the saved broadcast title.
3. Confirm team-logo and power-play visibility.
4. Select the intended scene preset.
5. Verify sponsor images and rotation.
6. Open the live overlay preview.
7. Confirm realtime branding changes appear without refresh.
8. If audio is enabled, confirm Audio Readiness reports ready.
9. Test each configured audio source locally.
10. Confirm game score, clock, period, and penalties continue to follow authoritative SportsOS state.
11. Confirm broadcast effects appear and clear without modifying game state.
12. Confirm reset returns presentation to overlay defaults.

## Validation gates

Required:

```bash
npm run typecheck && npm test
```

Runtime acceptance:

```bash
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

For final Milestone 19 closeout, both validation gates must remain green.

## Closeout

Milestones 19.0 through 19.10 establish:

- repository continuation baseline
- persisted broadcast sessions
- overlay profile consumption
- operator broadcast controls
- realtime profile updates
- scene presets
- sponsor rotation
- goal/penalty effects
- audio policy
- local audio readiness/testing
- broadcast operations acceptance

Future broadcast work should extend these contracts rather than duplicate overlay, realtime, or game-state authority.
