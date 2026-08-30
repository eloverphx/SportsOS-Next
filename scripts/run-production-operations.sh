#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
MODE="${1:-}"
LOCK_DIR="${SPORTSOS_OPERATIONS_LOCK_DIR:-${ROOT}/data/operations-locks}"
LOG_DIR="${SPORTSOS_OPERATIONS_RUN_LOG_DIR:-${ROOT}/data/operations-runs}"
HISTORY_DIR="${SPORTSOS_OPERATIONS_HISTORY_DIR:-${ROOT}/data/operations-history}"
LOCK_WAIT_SECONDS="${SPORTSOS_OPERATIONS_LOCK_WAIT_SECONDS:-5}"
STAMP="$(date +%Y%m%d-%H%M%S)"

cd "$ROOT"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/run-production-operations.sh <mode>

Modes:
  health
  alert
  recovery
  mysql-backup
  persistent-backup
  backup-all
  restore-rehearsal
  retention
  daily
  weekly
  reliability-alert
USAGE
}

run_step() {
  local label="$1"
  shift

  echo
  echo "---- $label ----"

  if "$@"; then
    echo "PASS $label"
    return 0
  else
    local rc=$?
    echo "FAIL $label (exit=$rc)" >&2
    return "$rc"
  fi
}


# SPORTSOS_M35_2_INCIDENT_ESCALATION_RUNNER
run_incident_escalation() {
  local escalation_script="${ROOT}/scripts/operations-incident-escalation.sh"

  if [[ ! -x "$escalation_script" ]]; then
    echo "ERROR: incident escalation script is missing or not executable: $escalation_script" >&2
    return 1
  fi

  bash "$escalation_script" "$ROOT"
}

case "$MODE" in
  incident-escalation)
    run_incident_escalation
    ;;
  health|alert|recovery|mysql-backup|persistent-backup|backup-all|restore-rehearsal|retention|daily|weekly|reliability-alert)
    ;;
  observability-refresh)
    run_step "operations observability refresh" bash "$ROOT/scripts/refresh-operations-observability.sh" || exit $?
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if ! [[ "$LOCK_WAIT_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: SPORTSOS_OPERATIONS_LOCK_WAIT_SECONDS must be a non-negative integer." >&2
  exit 1
fi

mkdir -p "$LOCK_DIR" "$LOG_DIR" "$HISTORY_DIR"
chmod 700 "$LOCK_DIR" "$LOG_DIR" "$HISTORY_DIR"
umask 077

LOCK_FILE="${LOCK_DIR}/${MODE}.lock"
RUN_LOG="${LOG_DIR}/${MODE}-${STAMP}.log"
HISTORY_FILE="${HISTORY_DIR}/${MODE}-${STAMP}.json"

exec 9>"$LOCK_FILE"
if ! flock -w "$LOCK_WAIT_SECONDS" 9; then
  echo "SKIP  another '${MODE}' operation is already running."
  exit 0
fi

write_history() {
  local status="$1"
  local exit_code="$2"
  local finished="$3"

  node - "$HISTORY_FILE" "$MODE" "$STAMP" "$status" "$exit_code" "$finished" "$RUN_LOG" <<'NODE'
const fs = require("node:fs");
const [file, mode, stamp, status, exitCode, finished, runLog] =
  process.argv.slice(2);

const record = {
  schemaVersion: 1,
  mode,
  stamp,
  status,
  exitCode: Number(exitCode),
  finishedAt: finished,
  runLog,
};

fs.writeFileSync(
  file,
  `${JSON.stringify(record, null, 2)}\n`,
  { mode: 0o600 },
);
NODE
  chmod 600 "$HISTORY_FILE"
}



status="passed"

set +e
{
  echo "============================================================"
  echo " SportsOS Production Operations Runner"
  echo "============================================================"
  echo "Mode: $MODE"
  echo "Started: $(date -Iseconds)"
  echo "Release: $(git describe --tags --always --dirty 2>/dev/null || true)"

  case "$MODE" in
    health)
      run_step "Production health" bash scripts/production-health-monitor.sh || exit $?
      ;;
    alert)
      run_step "Production alert check" bash scripts/production-alert-check.sh || exit $?
      ;;
    recovery)
      run_step "Container recovery / restart-loop check" bash scripts/container-recovery-check.sh || exit $?
      ;;
    reliability-alert)
      run_step "Reliability alert check" bash scripts/production-reliability-alert-check.sh || exit $?
      ;;
    mysql-backup)
      run_step "MySQL backup" bash scripts/backup-mysql.sh || exit $?
      ;;
    persistent-backup)
      run_step "Persistent data backup" bash scripts/backup-persistent-data.sh || exit $?
      ;;
    backup-all)
      run_step "MySQL backup" bash scripts/backup-mysql.sh || exit $?
      run_step "Persistent data backup" bash scripts/backup-persistent-data.sh || exit $?
      ;;
    restore-rehearsal)
      run_step "Backup restore rehearsal" bash scripts/backup-restore-rehearsal.sh || exit $?
      ;;
    retention)
      run_step "Log / report retention" bash scripts/log-retention-check.sh || exit $?
      ;;
    daily)
      run_step "Production alert check" bash scripts/production-alert-check.sh || exit $?
      run_step "Container recovery / restart-loop check" bash scripts/container-recovery-check.sh || exit $?
      run_step "MySQL backup" bash scripts/backup-mysql.sh || exit $?
      run_step "Persistent data backup" bash scripts/backup-persistent-data.sh || exit $?
      run_step "Log / report retention" bash scripts/log-retention-check.sh || exit $?
        run_step "refresh operations observability" bash "$ROOT/scripts/refresh-operations-observability.sh" || exit $?
;;
    weekly)
      run_step "Backup restore rehearsal" bash scripts/backup-restore-rehearsal.sh || exit $?
      run_step "Log / report retention" bash scripts/log-retention-check.sh || exit $?
      ;;
  esac

  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo
    echo "============================================================"
    echo "Production operation '${MODE}' PASSED."
    echo "Finished: $(date -Iseconds)"
    echo "============================================================"
  fi
  exit "$rc"
} 2>&1 | tee "$RUN_LOG"

exit_code=${PIPESTATUS[0]}
set -e

chmod 600 "$RUN_LOG"
LATEST="${LOG_DIR}/latest-${MODE}.log"
cp "$RUN_LOG" "$LATEST"
chmod 600 "$LATEST"

if [[ "$exit_code" -ne 0 ]]; then
  status="failed"
fi

finished="$(date -Iseconds)"
write_history "$status" "$exit_code" "$finished"

echo
echo "Run log:"
echo "  $RUN_LOG"
echo "History:"
echo "  $HISTORY_FILE"

exit "$exit_code"
