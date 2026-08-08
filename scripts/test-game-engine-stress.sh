#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "========================================"
echo " SportsOS Next - Game Engine Stress Gate"
echo "========================================"

npm run test --workspace=@sportsos/api -- test/game-engine-stress.test.ts
