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

## M39.2 — Browser-level account lifecycle acceptance

M39.2 adds executable Chromium coverage for the complete account entry lifecycle using the actual dashboard pages.

The acceptance test drives:

1. `/signup` organization selection and access request submission;
2. `PENDING_APPROVAL` confirmation;
3. an authenticated organization administrator opening `/users`;
4. the pending account being visibly presented and approved;
5. the newly approved member signing in through `/login`;
6. access and refresh credentials being persisted by the client;
7. the authenticated dashboard loading; and
8. **Sign out** sending the durable refresh token to `/auth/logout` and clearing all browser credentials.

The test isolates the UI contract by mocking API boundaries in Playwright rather than depending on production or Unraid database state. This keeps the acceptance run repeatable while exercising the real Next.js forms, routing, permission-gated Users page, browser storage, and logout behavior.

Run only this acceptance slice with:

`npm run test:e2e:accounts`
