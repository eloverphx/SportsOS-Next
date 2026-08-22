# SportsOS Game-Day Hardware Preflight

Milestone 18.1 introduces a fresh, game-specific hardware preflight.

Commissioning `GAME_READY` status proves that the scoreboard was installed correctly. A game-day preflight proves that the assigned scoreboard is still ready immediately before the game.

The preflight evaluates:

- commissioning status is `GAME_READY`
- device heartbeat is currently fresh
- reliability classification is `HEALTHY` or `WATCH`
- latest commissioning hardware self-test is `PASS`

Each run is persisted with its game ID, device ID, individual check results, timestamps, and final PASS/FAIL result.

API:

- `POST /game-day-hardware-preflight/:gameId`
- `GET /game-day-hardware-preflight/:gameId/latest`
- `GET /game-day-hardware-preflight/:gameId/history`

A failed preflight returns HTTP 409. The preflight does not modify game state.

## Preflight freshness and expiration

Milestone 18.3 makes passing game-day preflights time-limited.

The default freshness window is 15 minutes (`900000` ms) and can be changed with `SPORTSOS_GAME_DAY_PREFLIGHT_FRESHNESS_MS`.

A preflight is fresh only when it exists, passed, and its completion time remains inside the configured window. Expired or failed preflights must be rerun before they count as current game-day readiness evidence.

## Preflight freshness and expiration

Milestone 18.3 makes passing game-day preflights time-limited.

The default freshness window is 15 minutes (`900000` ms) and can be changed with `SPORTSOS_GAME_DAY_PREFLIGHT_FRESHNESS_MS`.

A preflight is fresh only when it exists, passed, and its completion time remains inside the configured window. Expired or failed preflights must be rerun before they count as current game-day readiness evidence.

## Assignment binding and device swap invalidation

Milestone 18.5 binds every game-day preflight to the exact game/device assignment present when the preflight ran.

Each preflight stores an `assignmentFingerprint` in the form:

`gameId::deviceId`

If the game is later assigned to a different scoreboard device, the old preflight no longer matches the current assignment and must not authorize game start.

The game-start guard exposes `PREFLIGHT_ASSIGNMENT_CHANGED` for this condition. A replacement device therefore requires its own fresh passing preflight.

## Preflight countdown and start-window guidance

Milestone 18.8 adds a live operator countdown to the expiration of the current passing preflight.

Guidance bands:

- more than 5 minutes remaining: normal start window
- 2–5 minutes remaining: start window is getting short
- 2 minutes or less: rerun preflight now to avoid a start delay
- expired or invalid: rerun is required before game start

The countdown is advisory UI built from the server-provided expiration timestamp. The server-side game-start gate remains authoritative.

## Automatic preflight rerun

Milestone 18.9 adds optional automatic refresh of a still-valid preflight as it approaches expiration.

Behavior:

- auto-rerun is enabled by default
- when a fresh preflight has 2 minutes or less remaining, SportsOS runs a new preflight automatically
- overlapping background reruns are prevented
- the operator may pause auto-rerun
- failed reruns do not silently authorize game start; the server-side start gate remains authoritative

This keeps the game-start window current without relying on the operator to manually rerun at the last second.
