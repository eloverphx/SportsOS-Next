#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for app in api dashboard; do
  echo "Validating $app lockfile registry..."
  if grep -q "applied-caas-gateway" "$ROOT/apps/$app/package-lock.json"; then
    echo "ERROR: internal package registry found in $app/package-lock.json" >&2
    exit 1
  fi
done
cd "$ROOT/apps/api"
npm ci --no-audit --no-fund
npm run typecheck
npm run build
cd "$ROOT/apps/dashboard"
npm ci --no-audit --no-fund
npm run typecheck
npm run build
