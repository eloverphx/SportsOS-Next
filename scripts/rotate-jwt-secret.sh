#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
ENV_FILE="${SPORTSOS_ENV_FILE:-${ROOT}/.env}"
APPLY="${SPORTSOS_APPLY_ROTATION:-0}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.security-backups/jwt-${STAMP}"

cd "$ROOT"

[[ -f "$ENV_FILE" ]] || {
  echo "ERROR: environment file not found: $ENV_FILE" >&2
  exit 1
}

grep -q '^JWT_SECRET=' "$ENV_FILE" || {
  echo "ERROR: JWT_SECRET is not present in $ENV_FILE" >&2
  exit 1
}

if [[ "$APPLY" != "1" ]]; then
  echo "JWT rotation preflight PASSED."
  echo
  echo "No credential was changed."
  echo
  echo "To rotate JWT_SECRET:"
  echo "  SPORTSOS_APPLY_ROTATION=1 bash scripts/rotate-jwt-secret.sh"
  echo
  echo "Expected effect:"
  echo "  - existing JWT sessions/tokens become invalid"
  echo "  - API container is recreated"
  echo "  - users must sign in again"
  exit 0
fi

mkdir -p "$BACKUP_DIR"
cp -a "$ENV_FILE" "$BACKUP_DIR/.env.before-jwt-rotation"

NEW_SECRET="$(
  node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"
)"

[[ "${#NEW_SECRET}" -ge 32 ]] || {
  echo "ERROR: generated JWT secret is unexpectedly short." >&2
  exit 1
}

node - "$ENV_FILE" "$NEW_SECRET" <<'NODE'
const fs = require("fs");
const file = process.argv[2];
const secret = process.argv[3];

let source = fs.readFileSync(file, "utf8");

if (!/^JWT_SECRET=.*$/m.test(source)) {
  throw new Error("JWT_SECRET entry not found.");
}

source = source.replace(
  /^JWT_SECRET=.*$/m,
  `JWT_SECRET=${secret}`,
);

fs.writeFileSync(
  file,
  source,
  {
    mode: 0o600,
  },
);
NODE

unset NEW_SECRET

echo "JWT_SECRET updated without printing the new value."
echo "Backup:"
echo "  $BACKUP_DIR/.env.before-jwt-rotation"
echo

docker compose up -d --force-recreate api dashboard

echo
echo "Waiting for API health..."

for attempt in $(seq 1 30); do
  if node -e "
    fetch('http://127.0.0.1:4001/health')
      .then(r => process.exit(r.ok ? 0 : 1))
      .catch(() => process.exit(1))
  "; then
    echo "API is healthy."
    break
  fi

  if [[ "$attempt" == "30" ]]; then
    echo "ERROR: API did not become healthy after JWT rotation." >&2
    echo "Restore the backed-up .env if rollback is required." >&2
    exit 1
  fi

  sleep 2
done

echo
echo "Running release smoke test..."
bash scripts/release-smoke-test.sh || {
  echo
  echo "WARNING: smoke test reported a failure."
  echo "If the only remaining failures are known MySQL/MinIO password-quality gates,"
  echo "the JWT rotation itself may still have succeeded."
  exit 1
}

echo
echo "JWT secret rotation completed successfully."
echo "Existing JWT sessions/tokens should now be treated as invalid."
