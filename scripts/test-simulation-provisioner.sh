#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=============================================="
echo " SportsOS Next - Simulation Provisioning Gate"
echo "=============================================="

npm run test --workspace=@sportsos/api -- test/simulation-provisioner.test.ts
