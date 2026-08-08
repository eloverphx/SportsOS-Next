#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

DOCKERFILE="apps/dashboard/Dockerfile"
PKG="package.json"

for f in "$DOCKERFILE" "$PKG"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing expected file: $f" >&2
    exit 1
  fi
done

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/dashboard-docker-build-order-${STAMP}"
mkdir -p "$BACKUP_DIR/apps/dashboard"
cp "$DOCKERFILE" "$BACKUP_DIR/$DOCKERFILE"
cp "$PKG" "$BACKUP_DIR/package.json"

node <<'NODE'
const fs = require("fs");
const path = "apps/dashboard/Dockerfile";
let text = fs.readFileSync(path, "utf8");

if (!text.includes("RUN npm run build --workspace=@sportsos/core")) {
  const marker = `RUN echo "Building dashboard for API: $NEXT_PUBLIC_API_URL"

RUN npm run typecheck
RUN npm run build`;

  if (!text.includes(marker)) {
    throw new Error("Could not find dashboard build marker in Dockerfile");
  }

  const replacement = `RUN echo "Building dashboard for API: $NEXT_PUBLIC_API_URL"

# Build shared workspace packages first so dashboard TypeScript can resolve
# @sportsos/core and @sportsos/config exactly like the root production build.
RUN npm run build --workspace=@sportsos/core
RUN npm run build --workspace=@sportsos/config

RUN npm run typecheck
RUN npm run build`;

  text = text.replace(marker, replacement);
}

fs.writeFileSync(path, text);
NODE

echo
echo "============================================="
echo " SportsOS Dashboard Docker Build-Order Fix"
echo "============================================="
echo
echo "Modified:"
echo "  $DOCKERFILE"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Dashboard Docker build now runs:"
echo "  core build"
echo "  config build"
echo "  dashboard typecheck"
echo "  dashboard build"
echo
echo "Next:"
echo "  docker compose up -d --build dashboard"
