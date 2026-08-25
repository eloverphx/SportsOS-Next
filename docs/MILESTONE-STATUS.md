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
Milestone 19.10 complete
Milestone 20.1 in progress
Milestone 20.1 in progress
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


### Milestone 19

Broadcast operations foundation:

- repository continuation baseline
- persisted broadcast-session profile
- overlay profile consumption
- operator broadcast-session UI
- realtime profile updates
- scene presets
- sponsor rotation
- goal and penalty presentation effects
- audio policy
- local audio test/readiness controls
- broadcast operations acceptance


### Milestone 20

Streaming output and encoder operations.

Current work:

- 20.1 stream destination profile foundation


### Milestone 20

Streaming output and encoder operations:

- stream destination profile
- stream destination operator UI
- reachability probe
- encoder session model
- FFmpeg runtime adapter
- telemetry and publish health
- automatic recovery policy
- runtime audit history
- streaming readiness preflight
- streaming operations acceptance

## Current streaming checkpoint

```text
Milestone 20.10 complete
```

### Milestone 21

Production streaming orchestration and game-day go-live.

Current work:

- 21.1 production go-live session foundation


## Milestone 21 closeout

Production streaming orchestration and game-day go-live:

- production go-live session lifecycle
- scheduled start window
- scheduled auto-arm countdown
- go-live health hold
- live broadcast watchdog
- degraded incident acknowledgement
- emergency broadcast stop
- go-live audit timeline
- final game-day go-live preflight
- production go-live acceptance

```text
Milestone 21.10 complete
```

### Milestone 22

Production broadcast automation and resilience.

Current work:

- 22.1 broadcast session coordinator foundation

### Milestone 23

Broadcast operations and operator experience.

Current work:

- 23.1 broadcast operations console foundation

### Milestone 23

Broadcast operations and operator experience.

Current work:

- 23.1 broadcast operations console foundation
