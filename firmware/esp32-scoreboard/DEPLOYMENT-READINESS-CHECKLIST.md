# SportsOS Scoreboard Deployment Readiness

Milestone 12 closes the software-side deployment lifecycle for ESP32 scoreboard devices.

## Lifecycle

A production device progresses through:

1. `FLASHED`
2. `PROVISIONED`
3. `PENDING`
4. `VERIFIED`
5. `ASSIGNED`
6. `ACTIVE`
7. `RETIRED`

A retired device must be reactivated to `PENDING` and claimed again before it can return to authoritative operations.

## Build gate

- repository typecheck passes
- repository tests pass
- firmware behavior simulator passes
- Dockerized PlatformIO compile passes
- release package contains `firmware.bin`
- SHA-256 release hashes exist

## Enrollment gate

- physical device ID reviewed
- firmware version reviewed
- ESP32 chip ID reviewed
- one-time claim token generated
- claim token successfully consumed
- device status is `VERIFIED`

## Operations gate

- device is visible in hardware operations
- enrollment trust is `VERIFIED`
- presence is online
- telemetry is current
- device can be assigned
- reconcile succeeds
- authoritative state matches the game
- horn/status/display outputs pass physical validation

## Retirement gate

Retire a device when:

- hardware is removed from service
- ESP32 is replaced
- identity is suspected compromised
- scoreboard is reassigned to a different physical controller

Retirement must:

- change trust status to `RETIRED`
- invalidate any outstanding claim token
- block verified-device authorization
- require reactivation and a new claim before reuse

## Milestone 12 release gate

Milestone 12 is complete when:

- repository tests are green
- API and dashboard build successfully
- firmware simulator is green
- the operations dashboard loads
- enrollment lifecycle controls load
- a test or physical device can move through pending → verified → retired → pending
