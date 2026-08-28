#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
STATE_DIR="${SPORTSOS_RECOVERY_STATE_DIR:-${ROOT}/data/operations-recovery}"
STATE_FILE="${STATE_DIR}/restart-counts.env"
LOOP_THRESHOLD="${SPORTSOS_RESTART_LOOP_THRESHOLD:-3}"
APPLY_RECOVERY="${SPORTSOS_APPLY_RECOVERY:-0}"

cd "$ROOT"

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
umask 077

if ! [[ "$LOOP_THRESHOLD" =~ ^[0-9]+$ ]] || [[ "$LOOP_THRESHOLD" -lt 1 ]]; then
  echo "ERROR: SPORTSOS_RESTART_LOOP_THRESHOLD must be >= 1" >&2
  exit 1
fi

declare -A PREVIOUS

if [[ -f "$STATE_FILE" ]]; then
  while IFS='=' read -r key value; do
    [[ -n "$key" ]] || continue
    PREVIOUS["$key"]="$value"
  done < "$STATE_FILE"
fi

containers=(
  "api:sportsos_api"
  "dashboard:sportsos_dashboard"
  "mysql:sportsos_mysql"
  "redis:sportsos_redis"
  "mqtt:sportsos_mqtt"
  "minio:sportsos_minio"
)

failures=0
loop_detected=0

tmp_state="$(mktemp)"
trap 'rm -f "$tmp_state"' EXIT

echo "============================================================"
echo " SportsOS Container Recovery / Restart-Loop Check"
echo "============================================================"

for item in "${containers[@]}"; do
  service="${item%%:*}"
  container="${item#*:}"

  if ! docker inspect "$container" >/dev/null 2>&1; then
    echo "FAIL  ${service}: container missing"
    failures=$((failures + 1))
    printf '%s=%s\n' "$container" "0" >> "$tmp_state"
    continue
  fi

  STATUS="$(
    docker inspect \
      --format='{{.State.Status}}' \
      "$container"
  )"

  HEALTH="$(
    docker inspect \
      --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' \
      "$container"
  )"

  RESTARTS="$(
    docker inspect \
      --format='{{.RestartCount}}' \
      "$container"
  )"

  PREV="${PREVIOUS[$container]:-$RESTARTS}"

  if [[ "$RESTARTS" =~ ^[0-9]+$ && "$PREV" =~ ^[0-9]+$ ]]; then
    DELTA=$(( RESTARTS - PREV ))
  else
    DELTA=0
  fi

  printf '%s=%s\n' "$container" "$RESTARTS" >> "$tmp_state"

  echo "${service}: status=${STATUS} health=${HEALTH} restarts=${RESTARTS} delta=${DELTA}"

  if [[ "$STATUS" == "restarting" ]]; then
    echo "FAIL  ${service}: currently restarting"
    failures=$((failures + 1))
  elif [[ "$STATUS" != "running" ]]; then
    echo "FAIL  ${service}: status=${STATUS}"
    failures=$((failures + 1))
  elif [[ "$HEALTH" != "healthy" && "$HEALTH" != "no-healthcheck" ]]; then
    echo "FAIL  ${service}: health=${HEALTH}"
    failures=$((failures + 1))
  else
    echo "PASS  ${service}: running"
  fi

  if [[ "$DELTA" -ge "$LOOP_THRESHOLD" ]]; then
    echo "FAIL  ${service}: restart loop suspected (${DELTA} new restarts)"
    loop_detected=1
    failures=$((failures + 1))

    if [[ "$APPLY_RECOVERY" == "1" ]]; then
      echo "RECOVERY  restarting service ${service} once"
      docker compose restart "$service"
    else
      echo "INFO  recovery not applied; set SPORTSOS_APPLY_RECOVERY=1 for one controlled restart"
    fi
  fi

  echo
done

mv "$tmp_state" "$STATE_FILE"
chmod 600 "$STATE_FILE"
trap - EXIT

if [[ "$APPLY_RECOVERY" == "1" && "$loop_detected" -eq 1 ]]; then
  echo "Waiting briefly for controlled recovery..."
  sleep 5
  docker compose ps
fi

echo "============================================================"

if (( failures > 0 )); then
  echo "Container recovery check FAILED: ${failures} issue(s)."
  exit 1
fi

echo "Container recovery check PASSED."
