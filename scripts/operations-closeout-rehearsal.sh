#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
REPORT_DIR="${SPORTSOS_CLOSEOUT_REPORT_DIR:-${ROOT}/data/operations-closeout}"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="${REPORT_DIR}/operations-closeout-${STAMP}.txt"

cd "$ROOT"

mkdir -p "$REPORT_DIR"
chmod 700 "$REPORT_DIR"
umask 077

failures=0

step() {
  local title="$1"
  shift

  echo
  echo "------------------------------------------------------------"
  echo "$title"
  echo "------------------------------------------------------------"

  if "$@"; then
    echo "PASS  $title"
  else
    echo "FAIL  $title"
    failures=$((failures + 1))
  fi
}

{
  echo "============================================================"
  echo " SportsOS Disaster Recovery / Operations Closeout"
  echo "============================================================"
  echo "Captured: $(date -Iseconds)"
  echo "Release: $(git describe --tags --always --dirty 2>/dev/null || true)"
  echo

  step \
    "1. Typecheck + unit tests" \
    bash -c \
    "npm run typecheck && npm test"

  step \
    "2. Fresh MySQL backup" \
    bash scripts/backup-mysql.sh

  step \
    "3. Fresh persistent-data backup" \
    bash scripts/backup-persistent-data.sh

  step \
    "4. Isolated backup restore rehearsal" \
    bash scripts/backup-restore-rehearsal.sh

  step \
    "5. Production health monitor" \
    bash scripts/production-health-monitor.sh

  step \
    "6. Production alert pipeline" \
    bash scripts/production-alert-check.sh

  step \
    "7. Container recovery / restart-loop check" \
    bash scripts/container-recovery-check.sh

  step \
    "8. Log retention / rotation check" \
    bash scripts/log-retention-check.sh

  step \
    "9. Production rollback dry-run" \
    bash scripts/production-rollback.sh

  step \
    "10. Docker E2E suite" \
    npm run test:e2e:docker

  echo
  echo "============================================================"

  if (( failures > 0 )); then
    echo "Operations closeout FAILED: ${failures} step(s) failed."
  else
    echo "Operations closeout PASSED."
  fi
} | tee "$REPORT"

chmod 600 "$REPORT"

echo
echo "Report:"
echo "  $REPORT"

if (( failures > 0 )); then
  exit 1
fi
