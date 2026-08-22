#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

echo "============================================================"
echo " SportsOS Game-Day Control Safety Acceptance"
echo "============================================================"

echo
echo "[1/5] Core build"
npm run build --workspace @sportsos/core

echo
echo "[2/5] Repository typecheck"
npm run typecheck

echo
echo "[3/5] Repository tests"
npm test

echo
echo "[4/5] Production application build"
npm run build

echo
echo "[5/5] Milestone 15 contract presence"
test -f apps/api/src/services/scoreboardControlPolicy.ts
test -f apps/api/src/services/scoreboardControlAuthorization.ts
test -f apps/api/src/services/scoreboardControlLifecyclePolicy.ts
test -f apps/api/src/services/scoreboardEmergencyControlLock.ts
test -f apps/api/src/services/scoreboardControlPolicyAudit.ts
test -f apps/api/src/services/scoreboardPhysicalControlHealth.ts
test -f apps/api/src/services/scoreboardControlIncidentResolution.ts

echo
echo "============================================================"
echo " Game-Day Control Safety Acceptance: PASS"
echo "============================================================"
echo
echo "Final container/browser gate:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
