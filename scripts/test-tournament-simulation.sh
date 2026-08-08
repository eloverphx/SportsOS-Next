#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "========================================"
echo " SportsOS Next - Tournament Simulation"
echo "========================================"

npm run test --workspace=@sportsos/api -- test/tournament-simulator.test.ts
