#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
ENV_FILE="${SPORTSOS_ENV_FILE:-${ROOT}/.env}"

cd "$ROOT"

echo "============================================================"
echo " SportsOS Public Exposure Audit"
echo "============================================================"

[[ -f "$ENV_FILE" ]] || {
  echo "FAIL  environment file missing: $ENV_FILE" >&2
  exit 1
}

get_env() {
  local name="$1"

  awk -v key="$name" '
    index($0, key "=") == 1 {
      print substr($0, length(key) + 2)
      exit
    }
  ' "$ENV_FILE"
}

DASHBOARD_ORIGIN="$(get_env DASHBOARD_ORIGIN)"

BASE="$(
  node - "$DASHBOARD_ORIGIN" <<'NODE'
const raw = process.argv[2];

let url;

try {
  url = new URL(raw);
} catch {
  console.error(
    `FAIL invalid DASHBOARD_ORIGIN: ${raw || "(empty)"}`,
  );
  process.exit(1);
}

if (url.protocol !== "https:") {
  console.error(
    "FAIL DASHBOARD_ORIGIN must use https://",
  );
  process.exit(1);
}

console.log(url.origin);
NODE
)"

echo "Public base: $BASE"

failures=0

check_blocked_path() {
  local path="$1"

  status="$(
    node - "$BASE$path" <<'NODE'
const url = process.argv[2];

try {
  const response =
    await fetch(
      url,
      {
        redirect: "manual",
      },
    );

  console.log(response.status);
} catch {
  console.log("000");
}
NODE
  )"

  if [[ "$status" == "401" || "$status" == "403" || "$status" == "404" ]]; then
    echo "PASS  blocked/unavailable ${path} -> ${status}"
  else
    echo "FAIL  unexpected public surface ${path} -> ${status}"
    failures=$((failures + 1))
  fi
}

for path in \
  /admin \
  /debug \
  /internal \
  /metrics \
  /docs \
  /openapi \
  /swagger
do
  check_blocked_path "$path"
done

echo
echo "Checking external security headers..."

headers="$(
  node - "$BASE" <<'NODE'
const base = process.argv[2];

try {
  const response =
    await fetch(
      base,
      {
        redirect: "manual",
      },
    );

  for (
    const [
      key,
      value,
    ]
    of response.headers
  ) {
    console.log(
      `${key}:${value}`,
    );
  }
} catch {
  process.exit(1);
}
NODE
)" || {
  echo "FAIL  unable to fetch public dashboard headers"
  exit 1
}

for expected in \
  "strict-transport-security:" \
  "x-content-type-options:" \
  "x-frame-options:" \
  "referrer-policy:"
do
  if grep -Fqi "$expected" <<< "$headers"; then
    echo "PASS  header ${expected%:}"
  else
    echo "FAIL  missing header ${expected%:}"
    failures=$((failures + 1))
  fi
done

echo
echo "============================================================"

if (( failures > 0 )); then
  echo "Public exposure audit FAILED: ${failures} check(s) failed."
  exit 1
fi

echo "Public exposure audit PASSED."
