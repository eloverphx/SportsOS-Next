#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-19.0-repository-baseline-handoff-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "package.json" \
  "apps/api/src/modules/games/routes.ts" \
  "apps/api/src/services/gameStartPreflightGuard.ts" \
  "apps/api/src/services/gameStartPreflightOverride.ts" \
  "apps/api/src/services/gameDayHardwarePreflight.ts" \
  "firmware/esp32-scoreboard/src/main.cpp"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

README="README.md"
RESUME="docs/RESUME-HERE.md"
ARCH="docs/ARCHITECTURE.md"
STATUS="docs/MILESTONE-STATUS.md"
TEST="packages/core/test/repository-baseline-handoff-19.0.test.ts"

for file in "$README" "$RESUME" "$ARCH" "$STATUS" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p docs packages/core/test

cat > "$README" <<'EOF'
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
EOF

cat > "$RESUME" <<'EOF'
# Resume Here

This file is the canonical continuation point for SportsOS Next development.

## Current checkpoint

Milestones through **18.11** are complete and validated locally.

The next development sequence begins at:

```text
Milestone 19
```

## Authoritative game-start path

The authoritative game-start transition is:

```text
POST /games/:id/lifecycle
command === "startGame"
```

The start boundary must remain ordered as follows:

```text
request authorization
        ↓
resolve current scoreboard assignment
        ↓
game-day preflight guard
        ↓
emergency override lookup if blocked
        ↓
pregame scoreboard readiness gate
        ↓
applyGameScoringAction()
        ↓
audit / telemetry / response
```

Never move game-day hardware authorization after `applyGameScoringAction()`.

## Assignment-bound preflight

A game-day preflight is bound to:

```text
gameId + deviceId
```

A scoreboard assignment change invalidates the prior preflight.

The authoritative start guard must call:

```ts
evaluateGameStartPreflight(
  gameId,
  assignedDeviceId,
);
```

## Emergency override

Emergency start override:

- requires a written reason
- is scoped to a game and device
- expires automatically
- can be revoked
- retains audit history
- does not convert failed preflight into PASS
- must match the currently assigned scoreboard device

## ESP32 firmware boundary

Firmware lives under:

```text
firmware/esp32-scoreboard
```

Firmware responsibilities include provisioning, enrollment, verified runtime gating, MQTT command transport, physical controls, display output, OTA firmware installation/reporting, commissioning self-test, and correlated telemetry.

Firmware must not independently own authoritative game state.

## Commissioning

Commissioning includes:

```text
FLASHED
PROVISIONED
ENROLLED
VERIFIED
ASSIGNED
CONNECTIVITY
READINESS
FIRMWARE
GAME_READY
```

GAME_READY is installation readiness, not a replacement for fresh game-day preflight.

## Game-day preflight

Game-day preflight validates:

- commissioning / GAME_READY
- fresh heartbeat
- acceptable reliability
- passing hardware self-test
- exact current assignment

Passing preflight has a limited freshness window.

The dashboard provides latest result, history, expiration countdown, auto-rerun near expiration, and emergency override controls/audit visibility.

## Validation commands

Run after every meaningful milestone:

```bash
npm run typecheck && npm test
```

For firmware changes:

```bash
bash firmware/esp32-scoreboard/build-in-docker.sh
```

For runtime acceptance:

```bash
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

## Git workflow

Keep `main` green.

Recommended pattern:

```bash
git switch main
git pull --ff-only origin main
git switch -c feature/milestone-19
```

## Do not regress

1. API is authoritative for game state.
2. Scoreboard hardware cannot start or alter a game without server authorization.
3. Start preflight runs before lifecycle mutation.
4. Assignment change invalidates an older preflight.
5. Emergency override is explicit, scoped, expiring, revocable, and audited.
6. OTA and commissioning remain device-bound and verified.
7. Calculation/scoring behavior changes require tests.
8. Existing tests are not removed to make new changes pass.
EOF

cat > "$ARCH" <<'EOF'
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
EOF

cat > "$STATUS" <<'EOF'
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
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.0 repository baseline and continuation handoff", () => {
  const resume = fs.readFileSync(
    new URL(
      "../../../docs/RESUME-HERE.md",
      import.meta.url,
    ),
    "utf8",
  );

  const architecture = fs.readFileSync(
    new URL(
      "../../../docs/ARCHITECTURE.md",
      import.meta.url,
    ),
    "utf8",
  );

  const status = fs.readFileSync(
    new URL(
      "../../../docs/MILESTONE-STATUS.md",
      import.meta.url,
    ),
    "utf8",
  );

  it("records authoritative start path", () => {
    expect(resume).toContain(
      "POST /games/:id/lifecycle",
    );

    expect(resume).toContain(
      'command === "startGame"',
    );

    expect(resume).toContain(
      "before lifecycle mutation",
    );
  });

  it("records assignment-bound preflight", () => {
    expect(resume).toContain(
      "evaluateGameStartPreflight(",
    );

    expect(resume).toContain(
      "assignedDeviceId",
    );
  });

  it("records firmware authority boundary", () => {
    expect(architecture).toContain(
      "does not become authoritative for game state",
    );
  });

  it("records current milestone baseline", () => {
    expect(status).toContain(
      "Milestone 18.11 complete",
    );

    expect(status).toContain(
      "Milestone 19 next",
    );
  });

  it("records validation commands", () => {
    expect(resume).toContain(
      "npm run typecheck && npm test",
    );

    expect(resume).toContain(
      "build-in-docker.sh",
    );

    expect(resume).toContain(
      "npm run test:e2e:docker",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 19.0 installed"
echo "============================================================"
echo
echo "Added/updated:"
echo "  - README.md"
echo "  - docs/RESUME-HERE.md"
echo "  - docs/ARCHITECTURE.md"
echo "  - docs/MILESTONE-STATUS.md"
echo "  - continuation regression tests"
echo
echo "Baseline:"
echo "  Milestone 18.11 complete"
echo "  Milestone 19 ready to begin"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then commit this documentation baseline before 19.1."
