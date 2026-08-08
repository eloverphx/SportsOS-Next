#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

PLAYWRIGHT_VERSION=$(
  node -p "require('@playwright/test/package.json').version"
)

echo "========================================"
echo " SportsOS Next - Playwright E2E"
echo " Playwright: ${PLAYWRIGHT_VERSION}"
echo "========================================"

docker run --rm \
  --ipc=host \
  --network=host \
  -v "$(pwd):/work" \
  -w /work \
  "mcr.microsoft.com/playwright:v${PLAYWRIGHT_VERSION}-noble" \
  npx playwright test
