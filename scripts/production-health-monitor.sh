#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
REPORT_DIR="${SPORTSOS_HEALTH_REPORT_DIR:-${ROOT}/data/operations-health}"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="${REPORT_DIR}/health-${STAMP}.txt"
LATEST="${REPORT_DIR}/latest.txt"

cd "$ROOT"

mkdir -p "$REPORT_DIR"
chmod 700 "$REPORT_DIR"
umask 077

failures=0

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1"
  failures=$((failures + 1))
}

check_container() {
  local service="$1"
  local container="$2"

  status="$(
    docker inspect \
      --format='{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' \
      "$container" \
      2>/dev/null || true
  )"

  if grep -Eq '^running (healthy|no-healthcheck)$' <<< "$status"; then
    pass "container:${service} ${status}"
  else
    fail "container:${service} ${status:-missing}"
  fi
}

{
  echo "============================================================"
  echo " SportsOS Production Health Monitor"
  echo "============================================================"
  echo "Captured: $(date -Iseconds)"
  echo

  echo "=== Release ==="
  echo "Commit: $(git rev-parse HEAD)"
  echo "Release: $(git describe --tags --always --dirty 2>/dev/null || true)"
  echo

  echo "=== Containers ==="

  check_container api sportsos_api
  check_container dashboard sportsos_dashboard
  check_container mysql sportsos_mysql
  check_container redis sportsos_redis
  check_container mqtt sportsos_mqtt
  check_container minio sportsos_minio

  echo
  echo "=== Local API ==="

  LOCAL_RESULT="$(
    node - <<'NODE'
try {
  const response = await fetch("http://127.0.0.1:4001/health");
  const json = await response.json();

  console.log(
    JSON.stringify({
      status: response.status,
      services:
        json?.services ??
        json?.data?.services ??
        {},
    }),
  );
} catch (error) {
  console.log(
    JSON.stringify({
      error:
        error instanceof Error
          ? error.message
          : String(error),
    }),
  );
}
NODE
  )"

  echo "$LOCAL_RESULT"

  if node - "$LOCAL_RESULT" <<'NODE'
const data = JSON.parse(process.argv[2]);
const services = data.services ?? {};

const allOnline =
  Object.values(services).length > 0 &&
  Object.values(services).every(
    (value) => value === "online",
  );

process.exit(
  data.status === 200 &&
  !data.error &&
  allOnline
    ? 0
    : 1,
);
NODE
  then
    pass "local-api health and dependencies"
  else
    fail "local-api health and dependencies"
  fi

  echo
  echo "=== Public Dashboard / API ==="

  if bash scripts/external-health-check.sh; then
    pass "external-health"
  else
    fail "external-health"
  fi

  echo
  echo "=== External Realtime ==="

  if bash scripts/external-realtime-check.sh; then
    pass "external-realtime"
  else
    fail "external-realtime"
  fi

  echo
  echo "=== Disk Space ==="

  USE_PERCENT="$(
    df -P "$ROOT" |
      awk 'NR==2 {gsub("%","",$5); print $5}'
  )"

  echo "Filesystem usage: ${USE_PERCENT}%"

  if [[ "$USE_PERCENT" -lt 90 ]]; then
    pass "disk-usage below 90%"
  else
    fail "disk-usage ${USE_PERCENT}%"
  fi

  echo
  echo "============================================================"

  if (( failures > 0 )); then
    echo "Production health monitor FAILED: ${failures} check(s) failed."
  else
    echo "Production health monitor PASSED."
  fi
} | tee "$REPORT"

chmod 600 "$REPORT"
cp -f "$REPORT" "$LATEST"
chmod 600 "$LATEST"

echo
echo "Report:"
echo "  $REPORT"
echo "Latest:"
echo "  $LATEST"

if (( failures > 0 )); then
  exit 1
fi
