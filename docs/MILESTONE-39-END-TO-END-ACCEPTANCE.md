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

## M39.3 — Browser streaming workflow acceptance

M39.3 validates the operator-facing streaming workflow through the real dashboard routes: create a scheduled game, open the scorekeeper console, start game operation, prepare the same game for broadcast, enter the game-specific Broadcast Operations workspace, start and stop the broadcast coordinator, confirm recording finalization to READY, open the Streaming archive, request a secure playback session, and confirm the archived recording loads into the browser video player.

The browser acceptance uses deterministic mocked backend state transitions so CI can exercise the complete dashboard workflow without requiring physical capture hardware, a live encoder, MySQL, MinIO, or FFmpeg runtime services.

M39.3 intentionally does not test event-driven clip generation. Authoritative scorekeeper event anchors, clip jobs, and highlight playback are covered by M39.4.

## M39.4 — Authoritative highlight workflow acceptance

M39.4 validates the browser workflow from an authoritative scorekeeper event anchor to a durable highlight clip and secure clip playback.

The acceptance test verifies that a READY recording exposes its authoritative SCOREKEEPER event anchor, the operator queues a clip by event identity rather than supplying arbitrary clip timestamps, the durable clip job reaches READY with selection source SCOREKEEPER_EVENT, and the resulting media asset is opened through the authenticated short-lived playback-session flow.

This preserves the SportsOS highlight boundary: scorekeeper/game-event timing remains authoritative while downstream clip processing may render and select media without inventing game events or timestamps.

Run only this acceptance slice with:

`npm run test:e2e:highlights`

## M39.5 — Restart and failure acceptance

M39.5 validates the operational boundary around API restart and recording failures.

The acceptance contract verifies that startup recording recovery runs before broadcast supervision, interrupted capture media is finalized into its exact durable recording rather than automatically resuming a LIVE encoder, failed or unattributable captures remain available for operator investigation, already-finalized capture remnants are cleaned, and failure to start archive capture does not take down an otherwise live broadcast.

This intentionally preserves the SportsOS restart safety model: archive recovery is automatic when attribution is safe, while restarting a live broadcast remains an explicit operator decision.

Focused validation:

`npm exec --workspace=@sportsos/api vitest -- run test/restart-failure-acceptance-m39.5.test.ts`

## Milestone 39 closeout

Milestone 39 is complete when the acceptance slices below are present on `main` and their corresponding CI runs have succeeded.

### Completed acceptance slices

- **M39.1 — Game-to-broadcast operator handoff**
  - Commit: `14ffdbaeabef605b332fcf2800c26b94dbe02750`
  - CI: #79, run `34662849700`
- **M39.2 — Browser-level account lifecycle acceptance**
  - Final commit: `693e50fab9494af9a486237ee0638e02429d7cc3`
  - CI: #84, run `34712712646`
- **M39.3 — Browser streaming workflow acceptance**
  - Commit: `07ceb9675558d0bfca47bba58492e4c257b491f4`
  - CI: #85, run `34720584170`
- **M39.4 — Authoritative highlight workflow acceptance**
  - Commit: `ff75a283b10fcb8a0eb1b4ae134db7876f17c322`
  - CI: #86, run `34721776893`
- **M39.5 — Restart and failure acceptance**
  - Commit: `b3bdf40f9019aa2102487ec48b0bf9d0fdeefa1e`
  - CI: #87, run `34736066426`

### Accepted end-to-end boundary

The completed acceptance coverage establishes the following SportsOS operator path:

1. request an account;
2. receive administrator approval;
3. sign in;
4. create a game;
5. open and operate the scorekeeper;
6. record authoritative scorekeeper events;
7. prepare and operate the broadcast for that same game;
8. stop the broadcast and finalize its recording;
9. play the archived recording;
10. create and play a highlight clip anchored to an authoritative scorekeeper event; and
11. preserve safe recording recovery across restart and capture-start failure without automatically resuming LIVE broadcasting.

Scorekeeper/game-event data remains authoritative for highlight timing. Browser clients do not supply arbitrary authoritative clip timing.

Automatic recovery is limited to recording/archive state that can be safely attributed to an exact durable recording and game. Interrupted LIVE broadcasting is never automatically resumed after API restart.

Tournament and ESP work remain frozen and outside Milestone 39.

The next phase is real Unraid deployment and operational acceptance using actual SportsOS services, storage, database, FFmpeg, recording media, playback, restart behavior, and operator workflows.
