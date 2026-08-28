#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
MYSQL_BACKUP_DIR="${SPORTSOS_MYSQL_BACKUP_DIR:-${ROOT}/data/backups/mysql}"
DATA_BACKUP_DIR="${SPORTSOS_DATA_BACKUP_DIR:-${ROOT}/data/backups/persistent}"
WORK_DIR="${SPORTSOS_RESTORE_REHEARSAL_DIR:-${ROOT}/data/restore-rehearsal}"
MYSQL_IMAGE="${SPORTSOS_RESTORE_MYSQL_IMAGE:-mysql:8.4}"
MYSQL_READY_TIMEOUT="${SPORTSOS_RESTORE_MYSQL_READY_TIMEOUT:-120}"
MYSQL_TMPFS_SIZE="${SPORTSOS_RESTORE_MYSQL_TMPFS_SIZE:-1g}"

STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="${WORK_DIR}/${STAMP}"
CONTAINER="sportsos_restore_rehearsal_${STAMP//[^0-9]/}"
TEMP_DB="sportsos_restore_rehearsal"
TEMP_PASSWORD="sportsos-restore-${STAMP}-only"

cd "$ROOT"

latest() {
  find "$1" \
    -maxdepth 1 \
    -type f \
    -name "$2" \
    -printf '%T@ %p\n' \
    2>/dev/null |
    sort -nr |
    head -1 |
    cut -d' ' -f2-
}

MYSQL_BACKUP="$(latest "$MYSQL_BACKUP_DIR" 'sportsos-mysql-*.sql.gz')"
MINIO_BACKUP="$(latest "$DATA_BACKUP_DIR" 'sportsos-minio-*.tar.gz')"
DATA_BACKUP="$(latest "$DATA_BACKUP_DIR" 'sportsos-data-*.tar.gz')"

for f in "$MYSQL_BACKUP" "$MINIO_BACKUP" "$DATA_BACKUP"; do
  [[ -n "$f" && -f "$f" ]] || {
    echo "ERROR: required backup missing." >&2
    exit 1
  }
done

if ! [[ "$MYSQL_READY_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$MYSQL_READY_TIMEOUT" -lt 30 ]]; then
  echo "ERROR: SPORTSOS_RESTORE_MYSQL_READY_TIMEOUT must be >= 30 seconds." >&2
  exit 1
fi

mkdir -p "$RUN_DIR/minio" "$RUN_DIR/data"
chmod 700 "$WORK_DIR" "$RUN_DIR"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "============================================================"
echo " SportsOS Backup Restore Rehearsal"
echo "============================================================"
echo "MySQL: $(basename "$MYSQL_BACKUP")"
echo "MinIO: $(basename "$MINIO_BACKUP")"
echo "Data:  $(basename "$DATA_BACKUP")"
echo "MySQL tmpfs: $MYSQL_TMPFS_SIZE"
echo "Ready timeout: ${MYSQL_READY_TIMEOUT}s"

gzip -t "$MYSQL_BACKUP"
tar -tzf "$MINIO_BACKUP" >/dev/null
tar -tzf "$DATA_BACKUP" >/dev/null
echo "PASS  archive integrity"

tar -xzf "$MINIO_BACKUP" -C "$RUN_DIR/minio"
tar -xzf "$DATA_BACKUP" -C "$RUN_DIR/data"
echo "PASS  archive extraction"

echo
echo "Starting disposable MySQL restore container in RAM..."

docker run -d \
  --name "$CONTAINER" \
  --network none \
  --tmpfs "/var/lib/mysql:rw,size=${MYSQL_TMPFS_SIZE}" \
  -e MYSQL_ROOT_PASSWORD="$TEMP_PASSWORD" \
  -e MYSQL_DATABASE="$TEMP_DB" \
  "$MYSQL_IMAGE" \
  --skip-log-bin \
  --performance-schema=OFF \
  --innodb-buffer-pool-size=64M \
  >/dev/null

elapsed=0
ready=0

while [[ "$elapsed" -lt "$MYSQL_READY_TIMEOUT" ]]; do
  state="$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo missing)"

  if [[ "$state" == "exited" || "$state" == "dead" || "$state" == "missing" ]]; then
    echo "ERROR: disposable MySQL container stopped before readiness." >&2
    docker logs --tail=160 "$CONTAINER" >&2 || true
    exit 1
  fi

  if docker exec \
    -e MYSQL_PWD="$TEMP_PASSWORD" \
    "$CONTAINER" \
    mysqladmin \
      -uroot \
      --protocol=socket \
      ping \
      --silent \
      >/dev/null 2>&1
  then
    ready=1
    break
  fi

  sleep 2
  elapsed=$((elapsed + 2))

  if (( elapsed % 20 == 0 )); then
    echo "  waiting for MySQL initialization... ${elapsed}s"
  fi
done

if [[ "$ready" != "1" ]]; then
  echo "ERROR: disposable MySQL did not become ready within ${MYSQL_READY_TIMEOUT}s." >&2
  echo
  echo "Container state:" >&2
  docker inspect \
    --format='status={{.State.Status}} exit={{.State.ExitCode}} error={{.State.Error}}' \
    "$CONTAINER" >&2 || true
  echo
  echo "Recent MySQL logs:" >&2
  docker logs --tail=160 "$CONTAINER" >&2 || true
  exit 1
fi

echo "PASS  disposable MySQL ready after ${elapsed}s"

echo
echo "Restoring MySQL backup..."

gzip -dc "$MYSQL_BACKUP" |
  docker exec -i \
    -e MYSQL_PWD="$TEMP_PASSWORD" \
    "$CONTAINER" \
    mysql \
      -uroot \
      --protocol=socket \
      "$TEMP_DB"

echo "PASS  MySQL restore completed"

TABLE_COUNT="$(
  docker exec \
    -e MYSQL_PWD="$TEMP_PASSWORD" \
    "$CONTAINER" \
    mysql \
      -N \
      -B \
      -uroot \
      --protocol=socket \
      -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${TEMP_DB}';"
)"

[[ "$TABLE_COUNT" =~ ^[0-9]+$ && "$TABLE_COUNT" -ge 1 ]] || {
  echo "ERROR: restored database contains no tables." >&2
  exit 1
}

echo "PASS  restored table count: $TABLE_COUNT"

echo
echo "Checking restored database readability..."

docker exec \
  -e MYSQL_PWD="$TEMP_PASSWORD" \
  "$CONTAINER" \
  mysql \
    -N \
    -B \
    -uroot \
    --protocol=socket \
    -e "CHECK TABLE mysql.user QUICK;" \
    >/dev/null

echo "PASS  disposable MySQL database readable"

cleanup
trap - EXIT

echo "PASS  disposable restore container removed"

echo
echo "Rehearsal workspace:"
echo "  $RUN_DIR"

echo
echo "============================================================"
echo "Backup restore rehearsal PASSED."
