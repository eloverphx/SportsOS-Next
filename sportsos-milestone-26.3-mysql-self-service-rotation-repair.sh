#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
ROTATE="${ROOT}/scripts/rotate-mysql-password.sh"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-26.3-self-service-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

[[ -f "$ROTATE" ]] || {
  echo "ERROR: missing $ROTATE" >&2
  exit 1
}

mkdir -p "$BACKUP/scripts"
cp -a "$ROTATE" "$BACKUP/scripts/rotate-mysql-password.sh"

cat > "$ROTATE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
ENV_FILE="${SPORTSOS_ENV_FILE:-${ROOT}/.env}"
APPLY="${SPORTSOS_APPLY_ROTATION:-0}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.security-backups/mysql-${STAMP}"

cd "$ROOT"

[[ -f "$ENV_FILE" ]] || {
  echo "ERROR: environment file not found: $ENV_FILE" >&2
  exit 1
}

for name in MYSQL_USER MYSQL_PASSWORD MYSQL_DATABASE; do
  grep -q "^${name}=" "$ENV_FILE" || {
    echo "ERROR: ${name} is missing from $ENV_FILE" >&2
    exit 1
  }
done

MYSQL_USER="$(
  awk -F= '/^MYSQL_USER=/{print substr($0,index($0,"=")+1); exit}' "$ENV_FILE"
)"

MYSQL_DATABASE="$(
  awk -F= '/^MYSQL_DATABASE=/{print substr($0,index($0,"=")+1); exit}' "$ENV_FILE"
)"

CURRENT_PASSWORD="$(
  awk -F= '/^MYSQL_PASSWORD=/{print substr($0,index($0,"=")+1); exit}' "$ENV_FILE"
)"

[[ -n "$MYSQL_USER" ]] || {
  echo "ERROR: MYSQL_USER is empty." >&2
  exit 1
}

[[ "$MYSQL_USER" != "root" ]] || {
  echo "ERROR: refusing to rotate the root account with this helper." >&2
  exit 1
}

echo "Checking current application MySQL credentials..."

if ! docker exec \
  -e MYSQL_PWD="$CURRENT_PASSWORD" \
  sportsos_mysql \
  mysql \
  "-u${MYSQL_USER}" \
  "$MYSQL_DATABASE" \
  -Nse "SELECT 1" >/dev/null 2>&1
then
  echo "ERROR: current MYSQL_PASSWORD in .env does not authenticate successfully." >&2
  echo "No credential was changed." >&2
  exit 1
fi

echo "Current application MySQL credentials are valid."

CURRENT_ACCOUNT="$(
  docker exec \
    -e MYSQL_PWD="$CURRENT_PASSWORD" \
    sportsos_mysql \
    mysql \
    "-u${MYSQL_USER}" \
    "$MYSQL_DATABASE" \
    -Nse "SELECT CURRENT_USER()" 2>/dev/null
)"

[[ -n "$CURRENT_ACCOUNT" ]] || {
  echo "ERROR: unable to resolve CURRENT_USER()." >&2
  exit 1
}

echo "Authenticated MySQL account: ${CURRENT_ACCOUNT}"

echo "Checking self-service password rotation capability..."

GRANTS="$(
  docker exec \
    -e MYSQL_PWD="$CURRENT_PASSWORD" \
    sportsos_mysql \
    mysql \
    "-u${MYSQL_USER}" \
    "$MYSQL_DATABASE" \
    -Nse "SHOW GRANTS FOR CURRENT_USER()" 2>/dev/null || true
)"

[[ -n "$GRANTS" ]] || {
  echo "ERROR: unable to inspect grants for current application account." >&2
  echo "No credential was changed." >&2
  exit 1
}

echo "Current account is authenticated and can inspect its grants."

if [[ "$APPLY" != "1" ]]; then
  echo
  echo "MySQL self-service rotation preflight PASSED."
  echo
  echo "No credential was changed."
  echo
  echo "This workflow does not require MYSQL_ROOT_PASSWORD."
  echo
  echo "To perform rotation:"
  echo "  SPORTSOS_APPLY_ROTATION=1 bash scripts/rotate-mysql-password.sh"
  exit 0
fi

mkdir -p "$BACKUP_DIR"
cp -a "$ENV_FILE" "$BACKUP_DIR/.env.before-mysql-rotation"

NEW_PASSWORD="$(
  node -e "console.log(require('crypto').randomBytes(36).toString('base64url'))"
)"

[[ "${#NEW_PASSWORD}" -ge 12 ]] || {
  echo "ERROR: generated MySQL password is unexpectedly short." >&2
  exit 1
}

echo "Changing password for the authenticated SportsOS MySQL account..."

docker exec \
  -e MYSQL_PWD="$CURRENT_PASSWORD" \
  -e SPORTSOS_NEW_PASSWORD="$NEW_PASSWORD" \
  sportsos_mysql \
  sh -lc '
    mysql "-u${MYSQL_USER:-sportsos}" "${MYSQL_DATABASE:-sportsos}" \
      -e "ALTER USER USER() IDENTIFIED BY '\''${SPORTSOS_NEW_PASSWORD}'\'';"
  ' \
  MYSQL_USER="$MYSQL_USER" \
  MYSQL_DATABASE="$MYSQL_DATABASE"

node - "$ENV_FILE" "$NEW_PASSWORD" <<'NODE'
const fs = require("fs");

const file = process.argv[2];
const password = process.argv[3];

let source = fs.readFileSync(file, "utf8");

if (!/^MYSQL_PASSWORD=.*$/m.test(source)) {
  throw new Error("MYSQL_PASSWORD entry not found.");
}

source = source.replace(
  /^MYSQL_PASSWORD=.*$/m,
  `MYSQL_PASSWORD=${password}`,
);

fs.writeFileSync(
  file,
  source,
  {
    mode: 0o600,
  },
);
NODE

echo "MYSQL_PASSWORD updated in .env without printing the new value."

echo "Verifying the new credential before restarting SportsOS..."

if ! docker exec \
  -e MYSQL_PWD="$NEW_PASSWORD" \
  sportsos_mysql \
  mysql \
  "-u${MYSQL_USER}" \
  "$MYSQL_DATABASE" \
  -Nse "SELECT 1" >/dev/null 2>&1
then
  echo "ERROR: new MySQL credential failed verification." >&2
  echo "The API has not been restarted." >&2
  echo "Environment backup:" >&2
  echo "  $BACKUP_DIR/.env.before-mysql-rotation" >&2
  exit 1
fi

echo "New MySQL credential verified successfully."

unset NEW_PASSWORD
unset CURRENT_PASSWORD

echo
echo "Recreating API..."

docker compose up -d --force-recreate api

echo "Waiting for API health..."

healthy=0

for attempt in $(seq 1 45); do
  if node -e "
    fetch('http://127.0.0.1:4001/health')
      .then(r => process.exit(r.ok ? 0 : 1))
      .catch(() => process.exit(1))
  "; then
    healthy=1
    break
  fi

  sleep 2
done

if [[ "$healthy" != "1" ]]; then
  echo "ERROR: API did not become healthy after MySQL rotation." >&2
  echo "Inspect:" >&2
  echo "  docker compose logs --tail=120 api" >&2
  exit 1
fi

echo "API is healthy."

docker compose up -d dashboard scoreboard-simulator

echo
echo "Running release readiness diagnostics..."
bash scripts/release-readiness-diagnostics.sh

echo
echo "MySQL credential rotation completed."
echo "Run the full smoke/E2E suite after the other known secret gates are handled."
EOF

chmod +x "$ROTATE"

echo "============================================================"
echo " SportsOS 26.3 MySQL self-service rotation repair installed"
echo "============================================================"
echo
echo "Changed:"
echo "  - removed MYSQL_ROOT_PASSWORD prerequisite"
echo "  - validates current SportsOS MySQL login"
echo "  - resolves CURRENT_USER()"
echo "  - uses authenticated account to rotate its own password"
echo "  - verifies new password before API restart"
echo "  - keeps .env backup"
echo "  - waits up to 90 seconds for API health"
echo
echo "Original script backup:"
echo "  $BACKUP/scripts/rotate-mysql-password.sh"
echo
echo "Next:"
echo "  bash scripts/rotate-mysql-password.sh"
echo
echo "Run preflight only first."
