# SportsOS Game-Day Deployment Acceptance

Milestone 18.10 closes the game-day hardware preflight and start-safety sequence.

## Acceptance requirements

A deployment is ready for controlled game-day use only when all of the following pass:

1. API and dashboard TypeScript checks pass.
2. Repository unit/integration tests pass.
3. Docker API and dashboard rebuild successfully.
4. Docker E2E tests pass.
5. The scoreboard device is assigned to the intended game.
6. A fresh game-day hardware preflight passes for that exact game/device assignment.
7. The start-window countdown is visible to the operator.
8. Auto-rerun refreshes a still-valid preflight near expiration, unless intentionally paused.
9. A changed scoreboard assignment invalidates the prior preflight.
10. A failed, stale, or invalid preflight blocks normal game start.
11. Emergency override requires an explicit written reason.
12. Emergency override is scoped to one game/device, expires automatically, and can be revoked.
13. Emergency override does not rewrite a failed preflight as passing.
14. Override history remains visible for operator/audit review.
15. Server-side start authorization remains authoritative.

## Game-day operator sequence

Before game start:

- confirm the correct scoreboard device is assigned
- confirm the device is online and responding
- run the hardware preflight
- verify the preflight reports PASS
- verify the start-window countdown is active
- leave Auto-Rerun enabled unless there is a specific operational reason to pause it
- start the game only while the server accepts the current preflight state

If the assigned device changes, run a new preflight for the replacement device.

If normal preflight cannot pass, do not bypass it casually. Emergency override exists only for deliberate operational authorization and requires a written reason.

## Closeout

Milestones 18.1 through 18.10 establish the game-day preflight safety boundary:

- readiness verification
- assignment-aware validity
- game-start enforcement
- device-swap invalidation
- emergency authorization
- audit visibility
- expiration countdown
- automatic start-window refresh
- acceptance criteria

Future scoreboard work should preserve this boundary and add regression coverage when changing start authorization, assignment behavior, device communication, or preflight semantics.

## Milestone 18.11 corrective closeout

The authoritative `startGame` boundary now resolves the current scoreboard assignment before lifecycle mutation and passes that device ID into the game-day preflight guard.

This closes two gaps: device swaps now invalidate an older preflight, and preflight/readiness rejection occurs before `applyGameScoringAction()` can mutate lifecycle state. Emergency override lookup is also scoped to the currently assigned device.
