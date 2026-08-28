#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
ENV_FILE="${SPORTSOS_ENV_FILE:-${ROOT}/.env}"
BACKUP_DIR="${SPORTSOS_MYSQL_BACKUP_DIR:-${ROOT}/data/backups/mysql}"
RETENTION_DAYS="${SPORTSOS_MYSQL_BACKUP_RETENTION_DAYS:-14}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${BACKUP_DIR}/sportsos-mysql-${STAMP}.sql.gz"

cd "$ROOT"

echo "============================================================"
echo " SportsOS MySQL Backup"
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

MYSQL_DATABASE="$(get_env MYSQL_DATABASE)"
MYSQL_USER="$(get_env MYSQL_USER)"
MYSQL_PASSWORD="$(get_env MYSQL_PASSWORD)"

for name in MYSQL_DATABASE MYSQL_USER MYSQL_PASSWORD; do
  value="${!name:-}"

  if [[ -z "$value" ]]; then
    echo "ERROR: ${name} is missing from .env" >&2
    exit 1
  fi
done

if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || [[ "$RETENTION_DAYS" -lt 1 ]]; then
  echo "ERROR: SPORTSOS_MYSQL_BACKUP_RETENTION_DAYS must be >= 1" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

echo "Checking MySQL container..."
docker compose ps mysql

echo
echo "Checking application database credentials..."

if ! docker exec \
  -e MYSQL_PWD="$MYSQL_PASSWORD" \
  sportsos_mysql \
  mysql \
    -u"$MYSQL_USER" \
    "$MYSQL_DATABASE" \
    -e "SELECT 1" \
    >/dev/null
then
  echo "ERROR: MySQL application credentials failed." >&2
  exit 1
fi

echo "PASS  MySQL credentials valid"

echo
echo "Creating compressed backup..."

umask 077

docker exec \
  -e MYSQL_PWD="$MYSQL_PASSWORD" \
  sportsos_mysql \
  mysqldump \
    -u"$MYSQL_USER" \
    --single-transaction \
    --no-tablespaces \
    --quick \
    --routines \
    --triggers \
    --events \
    --hex-blob \
    --set-gtid-purged=OFF \
    "$MYSQL_DATABASE" |
  gzip -9 > "$OUT"

chmod 600 "$OUT"

if [[ ! -s "$OUT" ]]; then
  echo "ERROR: backup file is empty." >&2
  rm -f "$OUT"
  exit 1
fi

echo "PASS  backup created"

echo
echo "Verifying gzip integrity..."

gzip -t "$OUT"
echo "PASS  gzip integrity"

echo
echo "Verifying SQL content..."

if ! gzip -dc "$OUT" |
  grep -Eq \
    'CREATE TABLE|INSERT INTO|LOCK TABLES|Dump completed'
then
  echo "ERROR: backup does not appear to contain a valid MySQL dump." >&2
  exit 1
fi

echo "PASS  SQL dump content detected"

echo
echo "Applying retention: ${RETENTION_DAYS} day(s)"

find "$BACKUP_DIR" \
  -type f \
  -name 'sportsos-mysql-*.sql.gz' \
  -mtime +"$RETENTION_DAYS" \
  -print \
  -delete

echo
echo "Backup:"
echo "  $OUT"

echo
echo "Size:"
du -h "$OUT"

echo
echo "SHA256:"
sha256sum "$OUT" |
  sed 's#  .*#  [backup file]#'

echo
echo "============================================================"
echo "MySQL backup PASSED."
