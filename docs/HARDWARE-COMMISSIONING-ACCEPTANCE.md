# SportsOS Hardware Commissioning Acceptance

Milestone 17 closes the physical scoreboard installation and commissioning workflow.

## 17.1 Scoreboard device commissioning lifecycle
FLASHED → PROVISIONED → ENROLLED → VERIFIED → ASSIGNED → CONNECTIVITY → READINESS → FIRMWARE → GAME_READY.

GAME_READY requires every prerequisite to pass.

## 17.2 Automated commissioning validation
SportsOS automatically evaluates enrollment, verification, assignment, heartbeat/connectivity, readiness, reliability, firmware, and final GAME_READY status.

## 17.3 Commissioning dashboard / installation wizard
The operations UI starts commissioning by device ID, shows every stage, supports manual FLASHED/PROVISIONED confirmation, automated validation, notes, timestamps, and final GAME_READY status.

## 17.4 Live commissioning progress
Validation repeats automatically while commissioning is active, avoids overlapping requests, can be paused, and stops at GAME_READY.

## 17.5 Failure guidance / remediation
Incomplete stages show actionable remediation for flashing, provisioning, enrollment, verification, assignment, connectivity, readiness, reliability, firmware, and GAME_READY prerequisites.

## 17.6 Commissioning hardware self-test
Self-test covers controller runtime, display path, physical input path, connectivity, and firmware runtime with PASS/FAIL results.

## 17.7 Firmware-driven self-test telemetry
ESP32 firmware implements a non-game-state-changing commissioning self-test and reports results with `source: FIRMWARE`.

## 17.8 Remote command correlation
Each remote test receives a unique `commandId` and tracks PENDING, ACKNOWLEDGED, COMPLETED, or FAILED. Firmware telemetry echoes the same commandId.

## 17.9 Self-test transport and device execution
SportsOS publishes `COMMISSIONING_SELF_TEST` through the scoreboard transport. Firmware validates the target device, runs the local self-test, and returns command-correlated telemetry without modifying authoritative game state.

## Final Milestone 17 gate

```bash
cd /mnt/user/appdata/SportsOS-Next
bash scripts/run-hardware-commissioning-acceptance.sh
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

Milestone 17 is complete when all commands are green.
