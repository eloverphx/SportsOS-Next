#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
REPORT_RETENTION_DAYS="${SPORTSOS_REPORT_RETENTION_DAYS:-30}"
MAX_CONTAINER_LOG_MB="${SPORTSOS_MAX_CONTAINER_LOG_MB:-100}"

cd "$ROOT"

echo "============================================================"
echo " SportsOS Log Retention / Rotation Check"
echo "============================================================"

if ! [[ "$REPORT_RETENTION_DAYS" =~ ^[0-9]+$ ]] || [[ "$REPORT_RETENTION_DAYS" -lt 1 ]]; then
  echo "ERROR: SPORTSOS_REPORT_RETENTION_DAYS must be >= 1" >&2
  exit 1
fi

if ! [[ "$MAX_CONTAINER_LOG_MB" =~ ^[0-9]+$ ]] || [[ "$MAX_CONTAINER_LOG_MB" -lt 1 ]]; then
  echo "ERROR: SPORTSOS_MAX_CONTAINER_LOG_MB must be >= 1" >&2
  exit 1
fi

failures=0

containers=(
  sportsos_api
  sportsos_dashboard
  sportsos_mysql
  sportsos_redis
  sportsos_mqtt
  sportsos_minio
)

echo
echo "=== Docker log driver / size ==="

for container in "${containers[@]}"; do
  if ! docker inspect "$container" >/dev/null 2>&1; then
    echo "FAIL  ${container}: missing"
    failures=$((failures + 1))
    continue
  fi

  driver="$(docker inspect --format='{{.HostConfig.LogConfig.Type}}' "$container")"
  log_path="$(docker inspect --format='{{.LogPath}}' "$container")"

  echo "${container}: driver=${driver}"

  if [[ -n "$log_path" && -f "$log_path" ]]; then
    size_bytes="$(stat -c '%s' "$log_path" 2>/dev/null || echo 0)"
    size_mb=$(( size_bytes / 1024 / 1024 ))

    echo "  size=${size_mb}MB"

    if [[ "$size_mb" -le "$MAX_CONTAINER_LOG_MB" ]]; then
      echo "PASS  ${container}: log size within ${MAX_CONTAINER_LOG_MB}MB threshold"
    else
      echo "FAIL  ${container}: log size exceeds ${MAX_CONTAINER_LOG_MB}MB threshold"
      failures=$((failures + 1))
    fi
  else
    echo "INFO  ${container}: log file path unavailable for direct size inspection"
  fi
done

echo
echo "=== Compose logging configuration ==="

COMPOSE_RENDERED="$(docker compose config)"

if grep -qE 'max-size|max-file' <<< "$COMPOSE_RENDERED"; then
  echo "PASS  compose includes explicit logging rotation options"
else
  echo "WARN  compose does not show explicit max-size/max-file logging options"
  echo "      Docker daemon-level rotation may still be configured."
fi

echo
echo "=== SportsOS operational report retention ==="

report_dirs=(
  "$ROOT/data/operations-baselines"
  "$ROOT/data/operations-health"
  "$ROOT/data/operations-alerts"
)

for dir in "${report_dirs[@]}"; do
  [[ -d "$dir" ]] || continue

  echo "Cleaning files older than ${REPORT_RETENTION_DAYS} day(s): $dir"

  find "$dir" \
    -type f \
    -mtime +"$REPORT_RETENTION_DAYS" \
    -print \
    -delete
done

echo
echo "Cleaning restore rehearsal directories older than ${REPORT_RETENTION_DAYS} day(s)..."

if [[ -d "$ROOT/data/restore-rehearsal" ]]; then
  find "$ROOT/data/restore-rehearsal" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -mtime +"$REPORT_RETENTION_DAYS" \
    -print \
    -exec rm -rf -- {} +
fi

echo
echo "=== Current operations storage ==="

storage_dirs=(
  "$ROOT/data/operations-baselines"
  "$ROOT/data/operations-health"
  "$ROOT/data/operations-alerts"
  "$ROOT/data/backups"
  "$ROOT/data/restore-rehearsal"
)

for dir in "${storage_dirs[@]}"; do
  if [[ -e "$dir" ]]; then
    du -sh "$dir" 2>/dev/null || true
  fi
done

echo
echo "============================================================"

if (( failures > 0 )); then
  echo "Log retention check FAILED: ${failures} issue(s)."
  exit 1
fi

echo "Log retention check PASSED."
