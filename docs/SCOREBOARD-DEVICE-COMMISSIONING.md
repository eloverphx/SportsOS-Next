# SportsOS Scoreboard Device Commissioning

Milestone 17.1 establishes the installation workflow for a physical scoreboard controller.

A controller progresses through these stages:

1. **FLASHED** — production ESP32 firmware has been installed.
2. **PROVISIONED** — local network/API configuration is present.
3. **ENROLLED** — the controller has completed SportsOS enrollment.
4. **VERIFIED** — the server recognizes the device as verified hardware.
5. **ASSIGNED** — the device is assigned to the intended scoreboard/game context.
6. **CONNECTIVITY** — API/MQTT communication is functioning.
7. **READINESS** — heartbeat/readiness checks pass.
8. **FIRMWARE** — installed firmware is on the approved release/channel.
9. **GAME_READY** — all previous commissioning requirements have passed.

`GAME_READY` cannot be set until every prior commissioning stage is complete.

The commissioning record is persistent and is intended to become the server-side source for the Milestone 17 installation UI and automated commissioning checks.

## Automated validation

Milestone 17.2 adds server-side validation of the commissioning record.

Automatically evaluated stages:

- **ENROLLED**
- **VERIFIED**
- **ASSIGNED**
- **CONNECTIVITY**
- **READINESS**
- **FIRMWARE**

The **FLASHED** and **PROVISIONED** stages remain explicit installation confirmations because they represent physical work that may occur before the controller is visible to the server.

The validator combines the live heartbeat readiness gate and reliability classification before marking **READINESS** complete.

`GAME_READY` is evaluated automatically after every validation pass and is set only when every prerequisite stage is complete.

## Remote self-test command correlation

Milestone 17.8 adds a command correlation lifecycle for remote commissioning self-tests:

- `PENDING` when SportsOS creates the request
- `ACKNOWLEDGED` when the device accepts the command
- `COMPLETED` when correlated firmware telemetry reports PASS
- `FAILED` when correlated firmware telemetry reports FAIL

Each request receives a unique `commandId`. Firmware telemetry echoes that `commandId`, allowing SportsOS to bind the device response to the exact commissioning request rather than treating telemetry as an uncorrelated event.

## MQTT self-test command transport

Milestone 17.9 connects the correlated self-test command to the scoreboard command transport.

The command payload contains `COMMISSIONING_SELF_TEST`, `commandId`, `deviceId`, and `requestedAt`.

Firmware validates the command type and target device before executing the non-game-state-changing commissioning test. Generated telemetry echoes the same `commandId`, preserving request/response correlation.
