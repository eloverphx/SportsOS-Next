#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
ALLOW_SECRET_GATE_FAILURE="${SPORTSOS_ALLOW_SECRET_GATE_FAILURE:-0}"

cd "$ROOT"

echo "============================================================"
echo " SportsOS Staging -> Production Acceptance Rehearsal"
echo "============================================================"
echo

step() {
  local name="$1"
  shift

  echo
  echo "------------------------------------------------------------"
  echo "$name"
  echo "------------------------------------------------------------"

  "$@"
}

step \
  "1. Typecheck + unit tests" \
  bash -c \
  "npm run typecheck && npm test"

step \
  "2. Build and start API + dashboard" \
  docker compose up -d --build api dashboard

step \
  "3. Container status" \
  docker compose ps

step \
  "4. Release readiness diagnostics" \
  bash scripts/release-readiness-diagnostics.sh

if [[ "$ALLOW_SECRET_GATE_FAILURE" == "1" ]]; then
  echo
  echo "Secret gate bypass enabled for rehearsal only."
  echo "Smoke-test failure caused solely by secret quality may be tolerated."
  echo

  set +e
  bash scripts/release-smoke-test.sh
  smoke_rc=$?
  set -e

  if (( smoke_rc != 0 )); then
    echo
    echo "Smoke test returned non-zero."

    node <<'NODE'
fetch("http://127.0.0.1:4001/broadcast-coordinator/secret-environment-validation")
  .then(async (response) => {
    const json = await response.json();

    const checks =
      json?.data?.checks ??
      [];

    const failing =
      checks.filter(
        (check) =>
          check.required &&
          !check.ok,
      );

    const onlySecretQuality =
      failing.length > 0 &&
      failing.every(
        (check) =>
          [
            "jwt:quality",
            "mysql-password:quality",
            "minio-password:quality",
          ].includes(
            check.id,
          ),
      );

    if (!onlySecretQuality) {
      console.error(
        "Smoke failure is not limited to approved rehearsal-only secret-quality blockers.",
      );
      process.exit(1);
    }

    console.log(
      "Rehearsal continues because the only remaining blockers are known secret-quality checks.",
    );
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
NODE
  fi
else
  step \
    "5. Release smoke test" \
    bash scripts/release-smoke-test.sh
fi

step \
  "6. Docker E2E" \
  npm run test:e2e:docker

step \
  "7. Release artifact" \
  bash scripts/generate-release-artifact.sh

echo
echo "============================================================"
echo " Rehearsal completed successfully."
echo "============================================================"
echo
echo "This rehearsal does not deploy to production."
