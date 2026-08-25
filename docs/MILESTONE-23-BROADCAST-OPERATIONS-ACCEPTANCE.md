# SportsOS Milestone 23 — Broadcast Operations Acceptance

Milestone 23 completes the first operator-experience pass for production broadcast operations.

## Accepted capabilities

- consolidated broadcast operations console
- safe operator control surface
- guarded two-step broadcast start
- degraded incident controls
- emergency-stop controls
- combined operator timeline
- ranked attention queue
- per-broadcast Focus Mode
- persistent shift-handoff notes
- on-demand handoff snapshot

## Operator safety invariants

The dashboard must not directly:

- start FFmpeg
- stop FFmpeg
- mutate encoder runtime state
- bypass coordinator preflight
- bypass go-live incident controls
- create a second authoritative broadcast lifecycle

Operator notes and handoff summaries are context only.

## Production acceptance gate

Milestone 23 is accepted only when all of the following are green:

```text
npm run typecheck
npm test
docker compose up -d --build api dashboard
docker compose ps
curl -fsS http://127.0.0.1:4001/health
npm run test:e2e:docker
```

The API and dashboard must both be running normally after the combined Docker Compose command.

## Closeout

After acceptance, commit and tag Milestone 23 before beginning Milestone 24.
