# Milestone 39 — End-to-End Acceptance

Milestone 39 converts the existing SportsOS feature set into a directly testable operator journey.

## Acceptance target

A user can:

1. request an account;
2. receive administrator approval;
3. sign in;
4. create a game;
5. open the scorekeeper console and run the game;
6. record authoritative goals and penalties;
7. prepare and operate the broadcast for that same game;
8. stop the broadcast and finalize its recording;
9. play the archived recording; and
10. create and play a highlight clip anchored to an authoritative scorekeeper event.

Tournament and ESP work remain outside this acceptance milestone.

## M39.1 — Game-to-broadcast operator handoff

The first testability gap was the transition from an actual game into the existing broadcast coordinator.

The scorekeeper console now exposes **Prepare broadcast** to users with `stream.manage`.

- The action uses the current game id; operators do not copy or re-enter identifiers.
- It calls the existing authenticated `POST /broadcast-coordinator/:gameId/prepare` endpoint.
- Server-side broadcast preflight remains authoritative. A blocked preflight is shown to the operator instead of being bypassed.
- Successful preparation routes directly to `/broadcast/operations/:gameId`.
- The broadcast coordinator's M38.4 `stream.manage` guard remains the authorization boundary.
- Scorekeeper events remain the authoritative source for later event anchors and highlight clips.

This establishes the UI handoff:

`Game -> Scorekeeper -> Prepare broadcast -> Broadcast Focus`

Later M39 steps will turn the complete acceptance target into executable end-to-end coverage and close any remaining operator-path gaps discovered by that coverage.
