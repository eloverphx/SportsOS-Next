# SportsOS Next

SportsOS Next is a modular sports operations platform for live scoring, game administration, broadcast overlays, streaming workflows, and connected scoreboard hardware.

## Current platform

SportsOS Next currently includes:

- Fastify API
- Next.js dashboard
- shared TypeScript packages
- MySQL
- Redis
- MQTT
- MinIO
- Socket.IO realtime transport
- scoreboard device enrollment and verification
- scoreboard assignment and synchronization
- ESP32 scoreboard firmware
- firmware release, artifact, rollout, OTA, and recovery flows
- physical scoreboard controls
- commissioning workflow
- firmware-driven commissioning self-test
- game-day hardware preflight
- assignment-bound game-start safety enforcement
- emergency start override with expiration and audit history

## Repository structure

```text
apps/
  api/                  Fastify API and realtime services
  dashboard/            Next.js administration and operations UI
  scoreboard-simulator/ Hardware/device simulator

packages/
  config/               Typed runtime configuration
  core/                 Shared contracts and utilities

firmware/
  esp32-scoreboard/     Production ESP32 scoreboard firmware

docs/                   Architecture, acceptance, and continuation notes
scripts/                Repository maintenance and acceptance scripts
e2e/                    Playwright end-to-end tests
```

## Local deployment

Primary ports:

- Dashboard: `4000`
- API: `4001`
- MQTT: `4012`
- MinIO API: `4013`
- MinIO Console: `4014`
- Scoreboard simulator: `4020`

The development environment is designed to run locally first using Docker Compose.

## Validation

From the repository root:

```bash
npm run typecheck
npm test
npm run build
bash firmware/esp32-scoreboard/build-in-docker.sh
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

Changes to scoring, lifecycle, scoreboard-device, firmware, or start-authorization behavior must include regression tests.

## Authoritative game state

The API remains authoritative for game state.

Scoreboards and physical controllers are clients of that state and must not independently become authoritative for score, clock, period, or lifecycle state.

The explicit game-start transition is:

```text
POST /games/:id/lifecycle
command = startGame
```

Game-day preflight and scoreboard readiness checks execute before lifecycle mutation.

## Continue development

Read:

```text
docs/RESUME-HERE.md
docs/ARCHITECTURE.md
docs/MILESTONE-STATUS.md
```

before beginning a new milestone.
