#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
COMPOSE="${ROOT}/docker-compose.yml"
DATA_DIR="${ROOT}/data"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${COMPOSE}.before-api-data-mount-${STAMP}"

cd "$ROOT"

[[ -f "$COMPOSE" ]] || {
  echo "ERROR: missing $COMPOSE" >&2
  exit 1
}

cp -a "$COMPOSE" "$BACKUP"

mkdir -p "$DATA_DIR"
chown -R 1000:1000 "$DATA_DIR"
chmod -R 775 "$DATA_DIR"

python3 - <<'PY'
from pathlib import Path

compose = Path("/mnt/user/appdata/SportsOS-Next/docker-compose.yml")
text = compose.read_text()

api_start = text.find("  api:\n")
if api_start < 0:
    raise SystemExit("ERROR: api service not found")

api_end = text.find("\n  dashboard:\n", api_start)
if api_end < 0:
    raise SystemExit("ERROR: dashboard boundary not found")

before = text[:api_start]
api = text[api_start:api_end]
after = text[api_end:]

env_marker = "      MINIO_SECRET_KEY: ${MINIO_ROOT_PASSWORD}\n"

if "      SPORTSOS_DATA_DIR: /app/data\n" not in api:
    if env_marker not in api:
        raise SystemExit("ERROR: API environment marker not found")
    api = api.replace(
        env_marker,
        env_marker + "      SPORTSOS_DATA_DIR: /app/data\n",
        1,
    )

volume_line = "      - /mnt/user/appdata/SportsOS-Next/data:/app/data\n"

if volume_line not in api:
    ports_marker = '    ports:\n      - "4001:4001"\n'
    if ports_marker not in api:
        raise SystemExit("ERROR: API ports marker not found")

    api = api.replace(
        ports_marker,
        "    volumes:\n" +
        volume_line +
        ports_marker,
        1,
    )

compose.write_text(before + api + after)
PY

echo
echo "========== PATCHED API SOURCE =========="
sed -n '70,120p' "$COMPOSE"

echo
echo "========== EFFECTIVE API CONFIG =========="
docker compose config | sed -n '/^  api:/,/^  dashboard:/p'

echo
echo "========== REQUIRED CHECKS =========="

docker compose config | grep -q 'SPORTSOS_DATA_DIR: /app/data' || {
  echo "ERROR: effective compose missing SPORTSOS_DATA_DIR" >&2
  exit 1
}

docker compose config | grep -q '/mnt/user/appdata/SportsOS-Next/data' || {
  echo "ERROR: effective compose missing host data bind mount" >&2
  exit 1
}

docker compose config | grep -q 'target: /app/data' || {
  echo "ERROR: effective compose missing /app/data mount target" >&2
  exit 1
}

echo "PASS: effective Compose contains SPORTSOS_DATA_DIR=/app/data"
echo "PASS: effective Compose contains persistent API data bind mount"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Next run:"
echo "  docker compose up -d --build --force-recreate api"
