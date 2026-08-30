#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
API_URL="${SPORTSOS_API_URL:-http://127.0.0.1:4001}"
DASHBOARD_URL="${SPORTSOS_DASHBOARD_URL:-http://127.0.0.1:4000}"

cd "$ROOT"

failures=0

check() {
  local name="$1"
  shift

  if "$@"; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name"
    failures=$((failures + 1))
  fi
}

json_ready() {
  local url="$1"
  node - "$url" <<'NODE'
const url = process.argv[2];

fetch(url)
  .then(async (response) => {
    if (!response.ok) {
      process.exit(1);
    }

    const json = await response.json();

    const ready =
      json?.data?.ready;

    process.exit(
      ready === true
        ? 0
        : 1,
    );
  })
  .catch(() => process.exit(1));
NODE
}

http_ok() {
  local url="$1"

  node - "$url" <<'NODE'
const url = process.argv[2];

fetch(url)
  .then((response) => {
    process.exit(
      response.ok
        ? 0
        : 1,
    );
  })
  .catch(() => process.exit(1));
NODE
}

container_healthy() {
  local container="$1"

  docker inspect \
    --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
    "$container" 2>/dev/null |
    grep -Eq '^(healthy|running)$'
}

echo "============================================================"
echo " SportsOS Release Smoke Test"
echo "============================================================"
echo

check \
  "API container healthy" \
  container_healthy \
  sportsos_api

check \
  "Dashboard container running" \
  container_healthy \
  sportsos_dashboard

check \
  "API /health" \
  http_ok \
  "${API_URL}/health"

check \
  "Dashboard reachable" \
  http_ok \
  "${DASHBOARD_URL}/"

check \
  "Release readiness" \
  json_ready \
  "${API_URL}/broadcast-coordinator/release-readiness"

check \
  "Data migration readiness" \
  json_ready \
  "${API_URL}/broadcast-coordinator/data-migration-readiness"

check \
  "Secret/environment validation" \
  json_ready \
  "${API_URL}/broadcast-coordinator/secret-environment-validation"

echo
echo "============================================================"

if (( failures > 0 )); then
  echo "Smoke test FAILED: ${failures} check(s) failed."
  exit 1
fi

echo "Smoke test PASSED."
