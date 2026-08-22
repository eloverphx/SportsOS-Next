# SportsOS Next Architecture

## Applications

### API

Location:

```text
apps/api
```

Responsibilities:

- authentication and authorization
- authoritative game state
- scoring lifecycle
- schedule and roster domains
- realtime events
- scoreboard assignment
- device verification
- firmware management
- commissioning
- game-day hardware preflight
- audit and reliability monitoring

### Dashboard

Location:

```text
apps/dashboard
```

Responsibilities:

- administration
- team/season/game workflows
- scoring operations
- scoreboard operations
- commissioning
- firmware operations
- game-day preflight and emergency override UX

### Scoreboard simulator

Location:

```text
apps/scoreboard-simulator
```

Used for development and protocol regression testing without physical hardware.

## Firmware

Location:

```text
firmware/esp32-scoreboard
```

The ESP32 is a controlled hardware client. It consumes server commands and reports state/telemetry. It does not become authoritative for game state.

## Infrastructure

SportsOS currently uses:

- MySQL
- Redis
- MQTT
- MinIO
- Socket.IO
- Docker Compose

## Scoreboard control flow

```text
Operator / physical button
        ↓
SportsOS control request
        ↓
authorization / policy / assignment checks
        ↓
authoritative game action
        ↓
game snapshot
        ↓
scoreboard synchronization
        ↓
MQTT/device transport
        ↓
ESP32 display
```

## Firmware update flow

```text
firmware release
        ↓
artifact
        ↓
approved rollout
        ↓
device offer
        ↓
device-bound download
        ↓
install policy
        ↓
OTA installation
        ↓
boot health / reporting
```

## Commissioning flow

```text
flash
  ↓
provision
  ↓
enroll
  ↓
verify
  ↓
assign
  ↓
connectivity/readiness
  ↓
firmware validation
  ↓
self-test
  ↓
GAME_READY
```

## Game-day start flow

```text
startGame request
        ↓
current scoreboard assignment
        ↓
fresh assignment-bound preflight
        ↓
optional matching emergency override
        ↓
pregame scoreboard readiness
        ↓
authoritative lifecycle mutation
        ↓
audit + telemetry
```

## Architectural rules

- domain rules belong in services/modules, not duplicated across UI/routes
- API routes should remain thin
- packages must not depend on applications
- firmware protocol changes require compatibility tests
- server remains authoritative for game state
- safety gates run before mutation
