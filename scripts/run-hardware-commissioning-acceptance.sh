#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
cd "$ROOT"

echo "============================================================"
echo " SportsOS Hardware Commissioning Acceptance"
echo "============================================================"

npm run build --workspace @sportsos/core
npm run typecheck
npm test
npm run build
bash firmware/esp32-scoreboard/build-in-docker.sh

test -f apps/api/src/services/scoreboardDeviceCommissioning.ts
test -f apps/api/src/services/scoreboardCommissioningValidator.ts
test -f apps/api/src/services/scoreboardCommissioningSelfTest.ts
test -f apps/api/src/services/scoreboardCommissioningSelfTestDispatch.ts
test -f apps/api/src/services/scoreboardCommissioningSelfTestTransport.ts
test -f apps/dashboard/app/scoreboards/operations/ScoreboardCommissioningWizard.tsx
test -f firmware/esp32-scoreboard/include/CommissioningSelfTest.h
test -f firmware/esp32-scoreboard/include/CommissioningSelfTestCommand.h

grep -q 'COMMISSIONING_SELF_TEST' \
  firmware/esp32-scoreboard/src/CommissioningSelfTestCommand.cpp

grep -q 'commandId' \
  firmware/esp32-scoreboard/src/CommissioningSelfTest.cpp

echo
echo "Hardware Commissioning Acceptance: PASS"
echo
echo "Final runtime/browser gate:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
