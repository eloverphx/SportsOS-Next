#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=============================================="
echo " SportsOS Next - Real Engine Adapter Gate"
echo "=============================================="

npm run test --workspace=@sportsos/api -- test/sportsos-simulation-adapter.test.ts
