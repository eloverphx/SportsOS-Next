# Milestone Status

## Completed foundation

SportsOS Next has completed the core platform, game engine, scoreboard-device, firmware, commissioning, physical-control, reliability, and game-day preflight sequences through Milestone 18.11.

## Recent milestone groups

### Milestones 9–12
Scoreboard synchronization, device protocol, simulator support, and core hardware integration.

### Milestones 13–14
Firmware release/rollout behavior and physical control transport.

### Milestone 15
Physical-control audit, safety, readiness, incident, and recovery behavior.

### Milestone 16
Pregame scoreboard readiness and authoritative start protection.

### Milestone 17
Commissioning lifecycle, validation, wizard, remediation, hardware self-test, remote self-test correlation, transport execution, and acceptance.

### Milestone 18
Game-day preflight, freshness, start enforcement, assignment binding, emergency override, audit visibility, countdown guidance, auto-rerun, deployment acceptance, and authoritative assignment-bound start-gate correction.

## Current state

```text
Milestone 18.11 complete
Milestone 19 next
```

## Required acceptance

```bash
npm run typecheck && npm test
```

When relevant:

```bash
bash firmware/esp32-scoreboard/build-in-docker.sh
docker compose up -d --build api dashboard
npm run test:e2e:docker
```
