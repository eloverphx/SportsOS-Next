#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
ALERT_DIR="${SPORTSOS_ALERT_DIR:-${ROOT}/data/operations-alerts}"
STATE_FILE="${ALERT_DIR}/state.env"
LATEST_ALERT="${ALERT_DIR}/latest-alert.txt"
COOLDOWN_SECONDS="${SPORTSOS_ALERT_COOLDOWN_SECONDS:-1800}"
WEBHOOK_URL="${SPORTSOS_ALERT_WEBHOOK_URL:-}"

cd "$ROOT"

mkdir -p "$ALERT_DIR"
chmod 700 "$ALERT_DIR"
umask 077

if ! [[ "$COOLDOWN_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: SPORTSOS_ALERT_COOLDOWN_SECONDS must be an integer >= 0" >&2
  exit 1
fi

NOW_EPOCH="$(date +%s)"
NOW_ISO="$(date -Iseconds)"

LAST_HASH=""
LAST_SENT=0

if [[ -f "$STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE" || true
fi

TMP_REPORT="$(mktemp)"
trap 'rm -f "$TMP_REPORT"' EXIT

echo "============================================================"
echo " SportsOS Production Alert Check"
echo "============================================================"

set +e
bash scripts/production-health-monitor.sh >"$TMP_REPORT" 2>&1
HEALTH_RC=$?
set -e

cat "$TMP_REPORT"

if [[ "$HEALTH_RC" -eq 0 ]]; then
  cat > "$STATE_FILE" <<STATE
LAST_HASH=
LAST_SENT=0
STATE
  chmod 600 "$STATE_FILE"

  echo
  echo "PASS  health monitor is green; no alert generated."
  exit 0
fi

FAIL_LINES="$(
  grep '^FAIL  ' "$TMP_REPORT" || true
)"

if [[ -z "$FAIL_LINES" ]]; then
  FAIL_LINES="FAIL  production-health-monitor returned exit code ${HEALTH_RC}"
fi

ALERT_HASH="$(
  printf '%s\n' "$FAIL_LINES" |
    sha256sum |
    awk '{print $1}'
)"

AGE=$(( NOW_EPOCH - LAST_SENT ))

if [[ "$ALERT_HASH" == "$LAST_HASH" && "$AGE" -lt "$COOLDOWN_SECONDS" ]]; then
  echo
  echo "SUPPRESSED  duplicate alert within cooldown window."
  echo "Cooldown remaining: $(( COOLDOWN_SECONDS - AGE )) second(s)"
  exit 1
fi

{
  echo "SportsOS Production Alert"
  echo "Time: $NOW_ISO"
  echo "Release: $(git describe --tags --always --dirty 2>/dev/null || true)"
  echo
  echo "Failures:"
  printf '%s\n' "$FAIL_LINES"
} > "$LATEST_ALERT"

chmod 600 "$LATEST_ALERT"

if [[ -n "$WEBHOOK_URL" ]]; then
  PAYLOAD="$(
    node - "$LATEST_ALERT" <<'NODE'
const fs = require("fs");

const text =
  fs.readFileSync(
    process.argv[2],
    "utf8",
  );

console.log(
  JSON.stringify({
    text,
  }),
);
NODE
  )"

  if curl \
    --fail \
    --silent \
    --show-error \
    --max-time 15 \
    -H 'Content-Type: application/json' \
    --data "$PAYLOAD" \
    "$WEBHOOK_URL" \
    >/dev/null
  then
    echo
    echo "PASS  webhook alert delivered."
  else
    echo
    echo "WARN  webhook delivery failed; alert file was still recorded."
  fi
else
  echo
  echo "INFO  SPORTSOS_ALERT_WEBHOOK_URL not configured; alert recorded locally only."
fi

cat > "$STATE_FILE" <<STATE
LAST_HASH=$ALERT_HASH
LAST_SENT=$NOW_EPOCH
STATE

chmod 600 "$STATE_FILE"

echo
echo "Alert file:"
echo "  $LATEST_ALERT"

echo
echo "Production alert generated."
exit 1
