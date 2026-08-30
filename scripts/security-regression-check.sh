#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
API_URL="${SPORTSOS_API_URL:-http://127.0.0.1:4001}"

cd "$ROOT"

echo "============================================================"
echo " SportsOS Security Regression Check"
echo "============================================================"

failures=0

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1"
  failures=$((failures + 1))
}

headers="$(
  node - "$API_URL" <<'NODE'
const base = process.argv[2];

fetch(`${base}/health`)
  .then((response) => {
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

    process.exit(
      response.ok
        ? 0
        : 1,
    );
  })
  .catch(() => process.exit(1));
NODE
)"

for expected in \
  "x-content-type-options:nosniff" \
  "x-frame-options:DENY" \
  "referrer-policy:no-referrer" \
  "permissions-policy:camera=(), microphone=(), geolocation=()"
do
  if grep -Fqi "$expected" <<< "$headers"; then
    pass "$expected"
  else
    fail "$expected"
  fi
done

status="$(
  node - "$API_URL" <<'NODE'
const base = process.argv[2];

fetch(
  `${base}/broadcast-coordinator/security-telemetry`,
  {
    method:
      "POST",
  },
)
  .then(
    (response) =>
      console.log(
        response.status,
      ),
  )
  .catch(() => {
    console.log(
      "000",
    );
  });
NODE
)"

if [[ "$status" == "404" || "$status" == "405" ]]; then
  pass "security telemetry rejects POST"
else
  fail "security telemetry POST returned ${status}"
fi

if git check-ignore -q .env; then
  pass ".env ignored"
else
  fail ".env not ignored"
fi

if [[ -z "$(git ls-files --error-unmatch .env 2>/dev/null || true)" ]]; then
  pass ".env untracked"
else
  fail ".env tracked"
fi

echo
echo "============================================================"

if (( failures > 0 )); then
  echo "Security regression check FAILED: ${failures} check(s) failed."
  exit 1
fi

echo "Security regression check PASSED."
