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
echo " SportsOS Physical Control Acceptance"
echo "============================================================"

echo
echo "[1/6] Core package build"
npm run build --workspace @sportsos/core

echo
echo "[2/6] Repository typecheck"
npm run typecheck

echo
echo "[3/6] Repository tests"
npm test

echo
echo "[4/6] Firmware simulator tests"
node --test firmware/esp32-scoreboard/simulator/test/*.test.js

echo
echo "[5/6] Real ESP32 firmware compile"
bash firmware/esp32-scoreboard/build-in-docker.sh

echo
echo "[6/6] Application build"
npm run build

echo
echo "============================================================"
echo " Physical Control Acceptance: PASS"
echo "============================================================"
echo
echo "Final runtime verification:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
