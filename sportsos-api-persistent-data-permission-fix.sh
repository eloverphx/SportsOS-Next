#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
COMPOSE="${ROOT}/docker-compose.yml"
DATA_DIR="${ROOT}/data"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${COMPOSE}.before-data-fix-${STAMP}"

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
if api_start == -1:
    raise SystemExit("ERROR: api service not found")

dashboard_start = text.find("\n  dashboard:\n", api_start)
if dashboard_start == -1:
    raise SystemExit("ERROR: dashboard service boundary not found")

api = text[api_start:dashboard_start]

if "SPORTSOS_DATA_DIR:" not in api:
    marker = "      MINIO_SECRET_KEY: ${MINIO_ROOT_PASSWORD}\n"
    if marker not in api:
        raise SystemExit("ERROR: API environment insertion marker not found")
    api = api.replace(
        marker,
        marker + "      SPORTSOS_DATA_DIR: /app/data\n",
        1,
    )

if "/mnt/user/appdata/SportsOS-Next/data:/app/data" not in api:
    marker = '    ports:\n      - "4001:4001"\n'
    if marker not in api:
        raise SystemExit("ERROR: API ports insertion marker not found")
    api = api.replace(
        marker,
        '    volumes:\n'
        '      - /mnt/user/appdata/SportsOS-Next/data:/app/data\n'
        + marker,
        1,
    )

new_text = text[:api_start] + api + text[dashboard_start:]
compose.write_text(new_text)
PY

echo "============================================================"
echo " SportsOS API persistent data permission fix installed"
echo "============================================================"
echo
echo "Added to API environment:"
echo "  SPORTSOS_DATA_DIR: /app/data"
echo
echo "Added API volume:"
echo "  /mnt/user/appdata/SportsOS-Next/data:/app/data"
echo
echo "Prepared host directory:"
echo "  $DATA_DIR"
echo
echo "Compose backup:"
echo "  $BACKUP"
echo
echo "Next:"
echo "  docker compose up -d --build --force-recreate api"
echo "  docker compose ps api"
echo "  docker compose logs --tail=50 api"
echo "  curl -i http://127.0.0.1:4001/health"
