#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] || cp .env.example .env
export COMPOSE_PARALLEL_LIMIT=1
echo "Edit .env now if this is the first install. Building API..."
docker compose build --pull api
echo "Building dashboard..."
docker compose build --pull dashboard
docker compose up -d
docker compose ps
