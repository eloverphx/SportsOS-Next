#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  exit 1
fi

cd "$ROOT"

echo "============================================================"
echo " SportsOS Firmware Fleet Acceptance"
echo "============================================================"

echo
echo "[1/5] Repository typecheck"
npm run typecheck

echo
echo "[2/5] Repository tests"
npm test

echo
echo "[3/5] Firmware behavior simulator"
node --test firmware/esp32-scoreboard/simulator/test/*.test.js

echo
echo "[4/5] Real ESP32 compile"
bash firmware/esp32-scoreboard/build-in-docker.sh

echo
echo "[5/5] Build dashboard/API"
npm run build

echo
echo "============================================================"
echo " Firmware Fleet Acceptance: PASS"
echo "============================================================"
echo
echo "Recommended runtime verification:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
