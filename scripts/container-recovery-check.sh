#!/usr/bin/env bash
set -euo pipefail
# SPORTSOS_M32_5_BOUNDED_SELF_HEALING

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"

STATE_DIR="${SPORTSOS_RECOVERY_STATE_DIR:-${ROOT}/data/operations-recovery}"
STATE_FILE="${STATE_DIR}/restart-counts.env"
ACTION_LOG="${STATE_DIR}/recovery-actions.tsv"
LOCK_FILE="${STATE_DIR}/recovery-engine.lock"

APPLY_RECOVERY="${SPORTSOS_APPLY_RECOVERY:-0}"
RESTART_DELTA_THRESHOLD="${SPORTSOS_RECOVERY_RESTART_DELTA_THRESHOLD:-3}"
COOLDOWN_SECONDS="${SPORTSOS_RECOVERY_COOLDOWN_SECONDS:-900}"
BUDGET_WINDOW_SECONDS="${SPORTSOS_RECOVERY_BUDGET_WINDOW_SECONDS:-3600}"
MAX_ACTIONS_PER_WINDOW="${SPORTSOS_RECOVERY_MAX_ACTIONS_PER_WINDOW:-2}"
POST_RECOVERY_TIMEOUT_SECONDS="${SPORTSOS_RECOVERY_POST_TIMEOUT_SECONDS:-60}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" || "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  exit 1
fi

cd "$ROOT"
mkdir -p "$STATE_DIR"

for value_name in \
  RESTART_DELTA_THRESHOLD \
  COOLDOWN_SECONDS \
  BUDGET_WINDOW_SECONDS \
  MAX_ACTIONS_PER_WINDOW \
  POST_RECOVERY_TIMEOUT_SECONDS
do
  value="${!value_name}"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "ERROR: $value_name must be a non-negative integer." >&2
    exit 1
  fi
done

if [[ "$RESTART_DELTA_THRESHOLD" -lt 1 ]]; then
  echo "ERROR: SPORTSOS_RECOVERY_RESTART_DELTA_THRESHOLD must be >= 1." >&2
  exit 1
fi

if [[ "$MAX_ACTIONS_PER_WINDOW" -lt 1 ]]; then
  echo "ERROR: SPORTSOS_RECOVERY_MAX_ACTIONS_PER_WINDOW must be >= 1." >&2
  exit 1
fi

if [[ "$POST_RECOVERY_TIMEOUT_SECONDS" -lt 5 ]]; then
  echo "ERROR: SPORTSOS_RECOVERY_POST_TIMEOUT_SECONDS must be >= 5." >&2
  exit 1
fi

# Direct invocations are protected in addition to the higher-level operations runner lock.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "INFO recovery engine is already running; skipping duplicate invocation."
  exit 0
fi

# format: compose-service:container-name:auto-recovery-policy
# auto = eligible for one bounded `docker compose restart`
# monitor = diagnostics only; requires operator intervention
containers=(
  "api:sportsos_api:auto"
  "dashboard:sportsos_dashboard:auto"
  "mysql:sportsos_mysql:monitor"
  "redis:sportsos_redis:monitor"
  "mqtt:sportsos_mqtt:auto"
  "minio:sportsos_minio:monitor"
  "scoreboard-simulator:sportsos_scoreboard_simulator:auto"
)

declare -A previous_counts
if [[ -f "$STATE_FILE" ]]; then
  while IFS='=' read -r key value; do
    [[ -n "$key" && "$value" =~ ^[0-9]+$ ]] || continue
    previous_counts["$key"]="$value"
  done < "$STATE_FILE"
fi

tmp_state="$(mktemp "${STATE_DIR}/restart-counts.XXXXXX")"
trap 'rm -f "$tmp_state"' EXIT

touch "$ACTION_LOG"
chmod 640 "$ACTION_LOG" 2>/dev/null || true

now_epoch="$(date +%s)"

log_action() {
  local service="$1"
  local container="$2"
  local action="$3"
  local result="$4"
  local reason="$5"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$now_epoch" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$service" \
    "$container" \
    "$action" \
    "${result}:${reason}" >> "$ACTION_LOG"
}

last_action_epoch() {
  local service="$1"
  awk -F '\t' -v svc="$service" '
    $3 == svc && $5 == "restart" && $6 ~ /^success:/ { last=$1 }
    END { if (last != "") print last }
  ' "$ACTION_LOG"
}

actions_in_window() {
  local service="$1"
  local cutoff="$2"
  awk -F '\t' -v svc="$service" -v cutoff="$cutoff" '
    $3 == svc && $5 == "restart" && $6 ~ /^success:/ && $1 >= cutoff { count++ }
    END { print count+0 }
  ' "$ACTION_LOG"
}

container_state() {
  local container="$1"
  docker inspect "$container" --format \
    '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}|{{.RestartCount}}' \
    2>/dev/null
}

is_healthy_state() {
  local status="$1"
  local health="$2"
  [[ "$status" == "running" && ( "$health" == "healthy" || "$health" == "no-healthcheck" ) ]]
}

wait_for_recovery() {
  local container="$1"
  local deadline=$(( $(date +%s) + POST_RECOVERY_TIMEOUT_SECONDS ))

  while (( $(date +%s) <= deadline )); do
    local state status health restarts
    state="$(container_state "$container" || true)"
    IFS='|' read -r status health restarts <<< "$state"

    if is_healthy_state "$status" "$health"; then
      return 0
    fi

    sleep 2
  done

  return 1
}

echo "============================================================"
echo " SportsOS Container Recovery / Restart-Loop Check"
echo "============================================================"
echo "mode=$([[ "$APPLY_RECOVERY" == "1" ]] && echo APPLY || echo DRY-RUN)"
echo "restart-delta-threshold=$RESTART_DELTA_THRESHOLD"
echo "cooldown-seconds=$COOLDOWN_SECONDS"
echo "budget=${MAX_ACTIONS_PER_WINDOW}/${BUDGET_WINDOW_SECONDS}s"
echo

failures=0
recovery_candidates=0
recovery_actions=0
recovery_suppressed=0

for item in "${containers[@]}"; do
  IFS=':' read -r service container policy <<< "$item"

  if ! docker inspect "$container" >/dev/null 2>&1; then
    echo "${service}: status=missing health=unknown restarts=unknown delta=unknown policy=${policy}"
    echo "FAIL  ${service}: container is missing"
    printf '%s=0\n' "$container" >> "$tmp_state"
    failures=$((failures + 1))
    echo
    continue
  fi

  state="$(container_state "$container")"
  IFS='|' read -r status health restarts <<< "$state"

  previous="${previous_counts[$container]:-${restarts}}"
  if ! [[ "$previous" =~ ^[0-9]+$ ]]; then
    previous="$restarts"
  fi

  if (( restarts >= previous )); then
    delta=$((restarts - previous))
  else
    # Container recreation legitimately resets RestartCount to zero.
    delta=0
  fi

  printf '%s=%s\n' "$container" "$restarts" >> "$tmp_state"

  echo "${service}: status=${status} health=${health} restarts=${restarts} delta=${delta} policy=${policy}"

  reason=""
  if [[ "$status" == "restarting" ]]; then
    reason="container-restarting"
  elif [[ "$status" != "running" ]]; then
    reason="container-status-${status}"
  elif [[ "$health" != "healthy" && "$health" != "no-healthcheck" ]]; then
    reason="container-health-${health}"
  elif (( delta >= RESTART_DELTA_THRESHOLD )); then
    reason="restart-delta-${delta}"
  fi

  if [[ -z "$reason" ]]; then
    echo "PASS  ${service}: running"
    echo
    continue
  fi

  failures=$((failures + 1))
  recovery_candidates=$((recovery_candidates + 1))
  echo "FAIL  ${service}: ${reason}"

  if [[ "$policy" != "auto" ]]; then
    echo "GUARD ${service}: monitor-only; automatic restart is prohibited"
    log_action "$service" "$container" "none" "blocked" "monitor-only-${reason}"
    recovery_suppressed=$((recovery_suppressed + 1))
    echo
    continue
  fi

  if [[ "$APPLY_RECOVERY" != "1" ]]; then
    echo "INFO  ${service}: recovery not applied; SPORTSOS_APPLY_RECOVERY=1 is required"
    log_action "$service" "$container" "none" "dry-run" "$reason"
    echo
    continue
  fi

  last_epoch="$(last_action_epoch "$service")"
  if [[ -n "$last_epoch" ]] && (( now_epoch - last_epoch < COOLDOWN_SECONDS )); then
    remaining=$((COOLDOWN_SECONDS - (now_epoch - last_epoch)))
    echo "GUARD ${service}: cooldown active (${remaining}s remaining)"
    log_action "$service" "$container" "none" "blocked" "cooldown-${reason}"
    recovery_suppressed=$((recovery_suppressed + 1))
    echo
    continue
  fi

  cutoff=$((now_epoch - BUDGET_WINDOW_SECONDS))
  action_count="$(actions_in_window "$service" "$cutoff")"

  if (( action_count >= MAX_ACTIONS_PER_WINDOW )); then
    echo "GUARD ${service}: recovery budget exhausted (${action_count}/${MAX_ACTIONS_PER_WINDOW})"
    log_action "$service" "$container" "none" "blocked" "budget-exhausted-${reason}"
    recovery_suppressed=$((recovery_suppressed + 1))
    echo
    continue
  fi

  echo "RECOVERY ${service}: executing one controlled docker compose restart"
  if ! docker compose restart "$service"; then
    echo "FAIL  ${service}: docker compose restart failed"
    log_action "$service" "$container" "restart" "failed" "$reason"
    echo
    continue
  fi

  if wait_for_recovery "$container"; then
    post_state="$(container_state "$container")"
    IFS='|' read -r post_status post_health post_restarts <<< "$post_state"
    echo "PASS  ${service}: recovered status=${post_status} health=${post_health}"
    log_action "$service" "$container" "restart" "success" "$reason"
    recovery_actions=$((recovery_actions + 1))
    # This failure was successfully recovered during the same invocation.
    failures=$((failures - 1))
  else
    post_state="$(container_state "$container" || true)"
    IFS='|' read -r post_status post_health post_restarts <<< "$post_state"
    echo "FAIL  ${service}: post-recovery verification failed status=${post_status:-unknown} health=${post_health:-unknown}"
    log_action "$service" "$container" "restart" "failed" "post-verification-${reason}"
  fi

  echo
done

mv "$tmp_state" "$STATE_FILE"
chmod 640 "$STATE_FILE" 2>/dev/null || true

echo "============================================================"
echo "Recovery candidates: ${recovery_candidates}"
echo "Recovery actions:    ${recovery_actions}"
echo "Recovery suppressed: ${recovery_suppressed}"
echo "Remaining failures:  ${failures}"

if (( failures > 0 )); then
  echo "Container recovery check FAILED: ${failures} unresolved issue(s)."
  exit 1
fi

echo "Container recovery check PASSED."
