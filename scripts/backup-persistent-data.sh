#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
ENV_FILE="${SPORTSOS_ENV_FILE:-${ROOT}/.env}"
BACKUP_DIR="${SPORTSOS_DATA_BACKUP_DIR:-${ROOT}/data/backups/persistent}"
RETENTION_DAYS="${SPORTSOS_DATA_BACKUP_RETENTION_DAYS:-14}"
STAMP="$(date +%Y%m%d-%H%M%S)"

MINIO_ARCHIVE="${BACKUP_DIR}/sportsos-minio-${STAMP}.tar.gz"
DATA_ARCHIVE="${BACKUP_DIR}/sportsos-data-${STAMP}.tar.gz"

cd "$ROOT"

echo "============================================================"
echo " SportsOS Persistent Data Backup"
echo "============================================================"

[[ -f "$ENV_FILE" ]] || {
  echo "ERROR: missing environment file: $ENV_FILE" >&2
  exit 1
}

get_env() {
  local name="$1"

  awk -v key="$name" '
    index($0, key "=") == 1 {
      print substr($0, length(key) + 2)
      exit
    }
  ' "$ENV_FILE"
}

MINIO_USER="$(
  get_env MINIO_ROOT_USER
)"

MINIO_PASSWORD="$(
  get_env MINIO_ROOT_PASSWORD
)"

if [[ -z "$MINIO_USER" || -z "$MINIO_PASSWORD" ]]; then
  echo "ERROR: MINIO_ROOT_USER / MINIO_ROOT_PASSWORD missing from .env" >&2
  exit 1
fi

if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || [[ "$RETENTION_DAYS" -lt 1 ]]; then
  echo "ERROR: SPORTSOS_DATA_BACKUP_RETENTION_DAYS must be >= 1" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
umask 077

echo
echo "Checking MinIO container..."

docker compose ps minio

echo
echo "Locating MinIO data mount..."

MINIO_SOURCE="$(
  docker inspect sportsos_minio \
    --format='{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}'
)"

if [[ -z "$MINIO_SOURCE" || ! -d "$MINIO_SOURCE" ]]; then
  echo "ERROR: unable to locate MinIO /data host mount." >&2
  exit 1
fi

echo "PASS  MinIO data mount located"

echo
echo "Creating MinIO filesystem backup..."

tar \
  -C "$MINIO_SOURCE" \
  -czf "$MINIO_ARCHIVE" \
  .

chmod 600 "$MINIO_ARCHIVE"

if [[ ! -s "$MINIO_ARCHIVE" ]]; then
  echo "ERROR: MinIO backup is empty." >&2
  rm -f "$MINIO_ARCHIVE"
  exit 1
fi

tar -tzf "$MINIO_ARCHIVE" >/dev/null

echo "PASS  MinIO archive integrity"

echo
echo "Creating SportsOS data backup..."

tar \
  -C "$ROOT" \
  --exclude='data/backups' \
  --exclude='data/operations-baselines' \
  -czf "$DATA_ARCHIVE" \
  data

chmod 600 "$DATA_ARCHIVE"

if [[ ! -s "$DATA_ARCHIVE" ]]; then
  echo "ERROR: data backup is empty." >&2
  rm -f "$DATA_ARCHIVE"
  exit 1
fi

tar -tzf "$DATA_ARCHIVE" >/dev/null

echo "PASS  SportsOS data archive integrity"

echo
echo "Applying retention: ${RETENTION_DAYS} day(s)"

find "$BACKUP_DIR" \
  -type f \
  \( \
    -name 'sportsos-minio-*.tar.gz' \
    -o \
    -name 'sportsos-data-*.tar.gz' \
  \) \
  -mtime +"$RETENTION_DAYS" \
  -print \
  -delete

echo
echo "Backup files:"
echo "  $MINIO_ARCHIVE"
echo "  $DATA_ARCHIVE"

echo
echo "Sizes:"
du -h \
  "$MINIO_ARCHIVE" \
  "$DATA_ARCHIVE"

echo
echo "Checksums:"
sha256sum \
  "$MINIO_ARCHIVE" \
  "$DATA_ARCHIVE" |
  sed -E \
    's#  .*/#  [backup]/#'

echo
echo "============================================================"
echo "Persistent data backup PASSED."
