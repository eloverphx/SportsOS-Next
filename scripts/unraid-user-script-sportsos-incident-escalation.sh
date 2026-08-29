#!/usr/bin/env bash
set -euo pipefail

ROOT="/mnt/user/appdata/SportsOS-Next"
RUNNER="$ROOT/scripts/run-production-operations.sh"

[[ -x "$RUNNER" || -f "$RUNNER" ]] || {
  echo "ERROR: SportsOS production operations runner missing: $RUNNER" >&2
  exit 1
}

# SPORTSOS_M35_3_INCIDENT_ESCALATION_WRAPPER
#
# This wrapper intentionally does not set:
#   SPORTSOS_INCIDENT_ESCALATION_WEBHOOK_URL
#   SPORTSOS_INCIDENT_ESCALATION_DRY_RUN
#
# Delivery configuration remains environment-controlled.
# The runner/escalation engine itself provides locking and repeat cooldown.

cd "$ROOT"
exec bash "$RUNNER" incident-escalation
