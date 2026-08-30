# Resume Here

This file is the canonical continuation point for SportsOS Next development.

## Current checkpoint

Milestones through **18.11** are complete and validated locally.

The next development sequence begins at:

```text
Milestone 19
```

## Authoritative game-start path

The authoritative game-start transition is:

```text
POST /games/:id/lifecycle
command === "startGame"
```

The start boundary must remain ordered as follows:

```text
request authorization
        ↓
resolve current scoreboard assignment
        ↓
game-day preflight guard
        ↓
emergency override lookup if blocked
        ↓
pregame scoreboard readiness gate
        ↓
applyGameScoringAction()
        ↓
audit / telemetry / response
```

Never move game-day hardware authorization after `applyGameScoringAction()`.

## Assignment-bound preflight

A game-day preflight is bound to:

```text
gameId + deviceId
```

A scoreboard assignment change invalidates the prior preflight.

The authoritative start guard must call:

```ts
evaluateGameStartPreflight(
  gameId,
  assignedDeviceId,
);
```

## Emergency override

Emergency start override:

- requires a written reason
- is scoped to a game and device
- expires automatically
- can be revoked
- retains audit history
- does not convert failed preflight into PASS
- must match the currently assigned scoreboard device

## ESP32 firmware boundary

Firmware lives under:

```text
firmware/esp32-scoreboard
```

Firmware responsibilities include provisioning, enrollment, verified runtime gating, MQTT command transport, physical controls, display output, OTA firmware installation/reporting, commissioning self-test, and correlated telemetry.

Firmware must not independently own authoritative game state.

## Commissioning

Commissioning includes:

```text
FLASHED
PROVISIONED
ENROLLED
VERIFIED
ASSIGNED
CONNECTIVITY
READINESS
FIRMWARE
GAME_READY
```

GAME_READY is installation readiness, not a replacement for fresh game-day preflight.

## Game-day preflight

Game-day preflight validates:

- commissioning / GAME_READY
- fresh heartbeat
- acceptable reliability
- passing hardware self-test
- exact current assignment

Passing preflight has a limited freshness window.

The dashboard provides latest result, history, expiration countdown, auto-rerun near expiration, and emergency override controls/audit visibility.

## Validation commands

Run after every meaningful milestone:

```bash
npm run typecheck && npm test
```

For firmware changes:

```bash
bash firmware/esp32-scoreboard/build-in-docker.sh
```

For runtime acceptance:

```bash
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

## Git workflow

Keep `main` green.

Recommended pattern:

```bash
git switch main
git pull --ff-only origin main
git switch -c feature/milestone-19
```

## Do not regress

1. API is authoritative for game state.
2. Scoreboard hardware cannot start or alter a game without server authorization.
3. Start preflight runs before lifecycle mutation.
4. Assignment change invalidates an older preflight.
5. Emergency override is explicit, scoped, expiring, revocable, and audited.
6. OTA and commissioning remain device-bound and verified.
7. Calculation/scoring behavior changes require tests.
8. Existing tests are not removed to make new changes pass.
