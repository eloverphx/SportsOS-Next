#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
USER_SCRIPTS_ROOT="${SPORTSOS_UNRAID_USER_SCRIPTS_ROOT:-/boot/config/plugins/user.scripts/scripts}"
OUTPUT_DIR="${SPORTSOS_SCHEDULED_VERIFY_DIR:-${ROOT}/data/operations-scheduled-verification}"
HISTORY_DIR="${SPORTSOS_OPERATIONS_HISTORY_DIR:-${ROOT}/data/operations-history}"

mkdir -p "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR" 2>/dev/null || true

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$OUTPUT_DIR/scheduled-operations-verification-$STAMP.txt"
exec > >(tee "$REPORT") 2>&1

echo "SportsOS Scheduled Production Operations Verification"
echo "Generated: $(date -Iseconds)"
echo

failures=0

check() {
  local label="$1"
  shift

  echo "---- $label ----"
  if "$@"; then
    echo "PASS $label"
  else
    local rc=$?
    echo "FAIL $label (exit=$rc)"
    failures=$((failures + 1))
  fi
  echo
}

check_entry() {
  local name="$1"
  local expected_schedule="$2"
  local delegated_wrapper="$3"
  local expected_mode="$4"

  local dir="$USER_SCRIPTS_ROOT/$name"
  local outer="$dir/script"
  local schedule="$dir/schedule"
  local name_file="$dir/name"
  local description="$dir/description"
  local delegated="$ROOT/scripts/$delegated_wrapper"

  [[ -d "$dir" ]] || return 1
  [[ -f "$outer" ]] || return 1
  [[ -f "$schedule" ]] || return 1
  [[ -f "$name_file" ]] || return 1
  [[ -f "$description" ]] || return 1
  [[ -f "$delegated" ]] || return 1

  # Exact entry identity.
  [[ "$(cat "$name_file")" == "$name" ]] || return 1
  grep -Fq "Managed by SportsOS Milestone 29.11" "$description" || return 1

  # Exact discovered Unraid schedule format:
  #   custom
  #   <cron expression>
  local schedule_line1 schedule_line2 extra
  schedule_line1="$(sed -n '1p' "$schedule" | tr -d '\r')"
  schedule_line2="$(sed -n '2p' "$schedule" | tr -d '\r')"
  extra="$(sed -n '3,$p' "$schedule" | tr -d '\r[:space:]')"

  [[ "$schedule_line1" == "custom" ]] || return 1
  [[ "$schedule_line2" == "$expected_schedule" ]] || return 1
  [[ -z "$extra" ]] || return 1

  # The flash-backed User Scripts entry delegates to the repository wrapper.
  # Do not require an executable mode bit on the outer file; Unraid invokes it
  # through its plugin and the discovered flash metadata reports mode 0600.
  grep -Fq '#!/usr/bin/env bash' "$outer" || return 1
  grep -Fq 'set -euo pipefail' "$outer" || return 1
  grep -Fq "exec bash \"$delegated\"" "$outer" || return 1

  # The delegated SportsOS wrapper owns the actual production operation mode.
  grep -Fq "run-production-operations.sh $expected_mode" "$delegated" || return 1

  return 0
}

check "Unraid observability entry" \
  check_entry \
    "SportsOS Observability" \
    "*/5 * * * *" \
    "unraid-user-script-sportsos-observability.sh" \
    "observability-refresh"

check "Unraid recovery entry" \
  check_entry \
    "SportsOS Recovery" \
    "*/5 * * * *" \
    "unraid-user-script-sportsos-recovery.sh" \
    "recovery"

check "Unraid daily entry" \
  check_entry \
    "SportsOS Daily Operations" \
    "15 3 * * *" \
    "unraid-user-script-sportsos-daily.sh" \
    "daily"

check "Unraid weekly entry" \
  check_entry \
    "SportsOS Weekly Rehearsal" \
    "30 4 * * 0" \
    "unraid-user-script-sportsos-weekly.sh" \
    "weekly"

check "Observability refresh execution" \
  bash "$ROOT/scripts/run-production-operations.sh" observability-refresh

check "Recovery execution" \
  bash "$ROOT/scripts/run-production-operations.sh" recovery

check "Alert execution" \
  bash "$ROOT/scripts/run-production-operations.sh" alert

check "Status snapshot exists" \
  test -s "$ROOT/data/operations-status/latest.json"

check "Severity metrics exist" \
  test -s "$ROOT/data/operations-metrics/latest.json"

check "Operations history exists" \
  bash -c 'find "$1" -type f -name "*.json" -print -quit 2>/dev/null | grep -q .' _ "$HISTORY_DIR"

echo "============================================================"
if [[ "$failures" -eq 0 ]]; then
  echo "SCHEDULED OPERATIONS VERIFICATION: PASS"
else
  echo "SCHEDULED OPERATIONS VERIFICATION: FAIL ($failures checks failed)"
fi
echo "Report: $REPORT"
echo "============================================================"

chmod 600 "$REPORT" 2>/dev/null || true

[[ "$failures" -eq 0 ]] || exit 3
