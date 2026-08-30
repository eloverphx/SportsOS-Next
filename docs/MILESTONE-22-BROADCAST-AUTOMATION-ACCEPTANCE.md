# SportsOS Milestone 22 — Broadcast Automation Acceptance

Milestone 22 closes the first production-safety pass for broadcast automation.

## Accepted capabilities

- broadcast-session coordinator
- composed coordinator / go-live / encoder snapshots
- health and drift detection
- bounded safe reconciliation
- persistent coordinator audit history
- bounded retry policy and backoff
- single supervisor tick
- application-lifecycle supervisor scheduler
- authoritative active-broadcast discovery

## Safety invariants

The automation layer must not create a second authoritative game lifecycle.

The supervisor runtime must not directly:

- start FFmpeg
- arm a go-live session
- mark a broadcast LIVE
- bypass final game-day go-live preflight
- silently repair ambiguous drift

Ambiguous conditions remain operator-review conditions.

## Operational inspection

```text
GET  /broadcast-coordinator/active
GET  /broadcast-coordinator/:gameId
GET  /broadcast-coordinator/:gameId/health
GET  /broadcast-coordinator/:gameId/audit
GET  /broadcast-coordinator/:gameId/retry
POST /broadcast-coordinator/:gameId/reconcile
POST /broadcast-coordinator/:gameId/supervisor/tick
```

## Acceptance gate

Milestone 22 is accepted only after all of the following are green:

```text
npm run typecheck
npm test
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

After acceptance, create a clean commit and annotated tag before beginning Milestone 23.
