#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
ENV_FILE="${SPORTSOS_ENV_FILE:-${ROOT}/.env}"

cd "$ROOT"

get_env() {
  local name="$1"
  awk -v key="$name" '
    index($0, key "=") == 1 {
      print substr($0, length(key) + 2)
      exit
    }
  ' "$ENV_FILE"
}

API="$(get_env PUBLIC_API_URL)"
DASHBOARD="$(get_env DASHBOARD_ORIGIN)"

echo "============================================================"
echo " SportsOS External Health Verification"
echo "============================================================"
echo "Dashboard target: ${DASHBOARD}"
echo "API health target: ${API}/health"
echo

node - "$DASHBOARD" "${API}/health" <<'NODE'
const [dashboard, apiHealth] = process.argv.slice(2);

for (const [label, url] of [
  ["dashboard", dashboard],
  ["api-health", apiHealth],
]) {
  try {
    const response = await fetch(url, { redirect: "manual" });
    console.log(`${label}: HTTP ${response.status}`);

    if (response.status < 200 || response.status >= 400) {
      process.exitCode = 1;
    } else {
      console.log(`PASS  ${label} reachable`);
    }
  } catch {
    console.error(`FAIL  ${label} unreachable`);
    process.exitCode = 1;
  }
}
NODE
