#!/usr/bin/env bash
set -euo pipefail

ROOT="/mnt/user/appdata/SportsOS-Next"
cd "$ROOT"

bash scripts/run-production-operations.sh recovery
