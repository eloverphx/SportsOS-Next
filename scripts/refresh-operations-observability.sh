#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
METRICS="${ROOT}/scripts/operations-severity-metrics.sh"
SNAPSHOT="${ROOT}/scripts/operations-status-snapshot.sh"

for required in "$METRICS" "$SNAPSHOT"; do
  [[ -x "$required" || -f "$required" ]] || {
    echo "ERROR: missing observability prerequisite: $required" >&2
    exit 1
  }
done

metrics_rc=0
bash "$METRICS" || metrics_rc=$?

# Severity exit codes 0, 2, and 3 are valid generated states.
# Any other code means metrics generation itself failed.
case "$metrics_rc" in
  0|2|3)
    ;;
  *)
    echo "ERROR: severity metrics generation failed (exit=$metrics_rc)." >&2
    exit "$metrics_rc"
    ;;
esac

bash "$SNAPSHOT"

case "$metrics_rc" in
  0)
    echo "Observability refresh complete: healthy"
    ;;
  2)
    echo "Observability refresh complete: warning"
    ;;
  3)
    echo "Observability refresh complete: critical"
    ;;
esac

# A warning/critical severity is data, not a refresh failure.
exit 0
