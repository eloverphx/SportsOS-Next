#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
STRICT_EXTERNAL="${SPORTSOS_REQUIRE_EXTERNAL_LIVE:-0}"

cd "$ROOT"

echo "============================================================"
echo " SportsOS Production Deployment Rehearsal"
echo "============================================================"
echo

step() {
  local title="$1"
  shift

  echo
  echo "------------------------------------------------------------"
  echo "$title"
  echo "------------------------------------------------------------"

  "$@"
}

soft_external_step() {
  local title="$1"
  shift

  echo
  echo "------------------------------------------------------------"
  echo "$title"
  echo "------------------------------------------------------------"

  if "$@"; then
    echo "PASS  $title"
    return 0
  fi

  if [[ "$STRICT_EXTERNAL" == "1" ]]; then
    echo "FAIL  $title"
    exit 1
  fi

  echo "BLOCKED  $title"
  echo "External HTTPS edge is not live/complete yet; continuing rehearsal."
}

step \
  "1. Typecheck + unit tests" \
  bash -c \
  "npm run typecheck && npm test"

step \
  "2. Build/recreate API + dashboard" \
  docker compose up -d --build api dashboard

step \
  "3. Local container status" \
  docker compose ps

step \
  "4. Local API health" \
  node -e \
  "fetch('http://127.0.0.1:4001/health').then(async r=>{console.log(r.status, await r.text()); process.exit(r.ok?0:1)}).catch(e=>{console.error(e);process.exit(1)})"

step \
  "5. Secret-source audit" \
  bash scripts/secret-source-audit.sh

step \
  "6. Security regression" \
  bash scripts/security-regression-check.sh

step \
  "7. Release smoke test" \
  bash scripts/release-smoke-test.sh

step \
  "8. Reverse proxy contract" \
  bash scripts/reverse-proxy-contract-check.sh

step \
  "9. E2E Docker suite" \
  npm run test:e2e:docker

soft_external_step \
  "10. TLS certificate validation" \
  bash scripts/tls-certificate-check.sh

soft_external_step \
  "11. External dashboard/API health" \
  bash scripts/external-health-check.sh

soft_external_step \
  "12. External realtime path" \
  bash scripts/external-realtime-check.sh

soft_external_step \
  "13. Public exposure audit" \
  bash scripts/public-exposure-audit.sh

echo
echo "------------------------------------------------------------"
echo "14. Deployment readiness endpoints"
echo "------------------------------------------------------------"

for endpoint in \
  /deployment/reverse-proxy-route-contract \
  /deployment/tls-certificate-readiness \
  /deployment/external-health-readiness \
  /deployment/external-realtime-readiness \
  /deployment/public-exposure-readiness
do
  echo
  echo "GET ${endpoint}"

  node - "$endpoint" <<'NODE'
const endpoint = process.argv[2];

try {
  const response =
    await fetch(
      `http://127.0.0.1:4001${endpoint}`,
    );

  const text =
    await response.text();

  console.log(
    `HTTP ${response.status}`,
  );

  console.log(
    text,
  );

  if (!response.ok) {
    process.exit(1);
  }
} catch (error) {
  console.error(error);
  process.exit(1);
}
NODE
done

echo
echo "============================================================"

if [[ "$STRICT_EXTERNAL" == "1" ]]; then
  echo "Production deployment rehearsal PASSED with external HTTPS required."
else
  echo "Production deployment rehearsal PASSED for local/tooling readiness."
  echo "External HTTPS checks may remain BLOCKED until public DNS/TLS/proxy cutover is live."
fi
