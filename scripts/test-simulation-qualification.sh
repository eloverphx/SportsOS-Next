#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=============================================="
echo " SportsOS Next - Live Simulation Qualification"
echo "=============================================="

npm run test --workspace=@sportsos/api -- test/simulation-qualification.test.ts
