#!/usr/bin/env bash
# SPORTSOS_M33_5_SHARED_RECOVERY_POLICY
#
# Canonical bounded recovery policy shared by execution and observability.
# This file defines policy only; it performs no recovery actions.

RESTART_DELTA_THRESHOLD="${SPORTSOS_RECOVERY_RESTART_DELTA_THRESHOLD:-3}"
COOLDOWN_SECONDS="${SPORTSOS_RECOVERY_COOLDOWN_SECONDS:-900}"
BUDGET_WINDOW_SECONDS="${SPORTSOS_RECOVERY_BUDGET_WINDOW_SECONDS:-3600}"
MAX_ACTIONS_PER_WINDOW="${SPORTSOS_RECOVERY_MAX_ACTIONS_PER_WINDOW:-2}"
POST_RECOVERY_TIMEOUT_SECONDS="${SPORTSOS_RECOVERY_POST_TIMEOUT_SECONDS:-60}"

# format: compose-service:container-name:auto-recovery-policy
containers=(
  "api:sportsos_api:auto"
  "dashboard:sportsos_dashboard:auto"
  "mysql:sportsos_mysql:monitor"
  "redis:sportsos_redis:monitor"
  "mqtt:sportsos_mqtt:auto"
  "minio:sportsos_minio:monitor"
  "scoreboard-simulator:sportsos_scoreboard_simulator:auto"
)

sportsos_recovery_policy_json() {
  local first=1
  local entry service container policy

  printf '{'
  for entry in "${containers[@]}"; do
    IFS=':' read -r service container policy <<< "$entry"
    if (( first == 0 )); then
      printf ','
    fi
    first=0
    printf '"%s":"%s"' "$service" "$policy"
  done
  printf '}'
}
