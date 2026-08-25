#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-26.3-mysql-rotation-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

ROTATE="scripts/rotate-mysql-password.sh"
TEST="packages/core/test/mysql-credential-rotation-26.3.test.ts"
DOC="docs/PRODUCTION-SECURITY-HARDENING.md"

for required in \
  ".git" \
  ".env" \
  "docker-compose.yml" \
  "scripts/release-smoke-test.sh" \
  "scripts/release-readiness-diagnostics.sh" \
  "apps/api/src/services/credentialRotationReadiness.ts" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$ROTATE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$ROTATE")" "$(dirname "$TEST")"

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

for name in MYSQL_USER MYSQL_PASSWORD MYSQL_DATABASE MYSQL_ROOT_PASSWORD; do
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
MYSQL_ROOT_PASSWORD="$(
  awk -F= '/^MYSQL_ROOT_PASSWORD=/{print substr($0,index($0,"=")+1); exit}' "$ENV_FILE"
)"
CURRENT_PASSWORD="$(
  awk -F= '/^MYSQL_PASSWORD=/{print substr($0,index($0,"=")+1); exit}' "$ENV_FILE"
)"

[[ "$MYSQL_USER" != "root" ]] || {
  echo "ERROR: refusing to rotate application credentials for MySQL root." >&2
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

echo "Checking MySQL administrative credential..."

if ! docker exec \
  -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" \
  sportsos_mysql \
  mysql \
  -uroot \
  -Nse "SELECT 1" >/dev/null 2>&1
then
  echo "ERROR: MYSQL_ROOT_PASSWORD in .env does not authenticate as MySQL root." >&2
  echo "No credential was changed." >&2
  exit 1
fi

echo "MySQL administrative credential is valid."

if [[ "$APPLY" != "1" ]]; then
  echo
  echo "MySQL rotation preflight PASSED."
  echo
  echo "No credential was changed."
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

echo "Updating MySQL application account..."

docker exec \
  -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" \
  -e SPORTSOS_NEW_PASSWORD="$NEW_PASSWORD" \
  -e SPORTSOS_MYSQL_USER="$MYSQL_USER" \
  sportsos_mysql \
  sh -lc '
    mysql -uroot <<SQL
ALTER USER '\''${SPORTSOS_MYSQL_USER}'\''@'\''%'\'' IDENTIFIED BY '\''${SPORTSOS_NEW_PASSWORD}'\'';
FLUSH PRIVILEGES;
SQL
  '

echo "MySQL account updated."

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

echo "Verifying new MySQL application credential before API restart..."

if ! docker exec \
  -e MYSQL_PWD="$NEW_PASSWORD" \
  sportsos_mysql \
  mysql \
  "-u${MYSQL_USER}" \
  "$MYSQL_DATABASE" \
  -Nse "SELECT 1" >/dev/null 2>&1
then
  echo "ERROR: new MySQL credential failed verification." >&2
  echo "Restoring old MySQL account password and .env..." >&2

  docker exec \
    -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" \
    -e SPORTSOS_OLD_PASSWORD="$CURRENT_PASSWORD" \
    -e SPORTSOS_MYSQL_USER="$MYSQL_USER" \
    sportsos_mysql \
    sh -lc '
      mysql -uroot <<SQL
ALTER USER '\''${SPORTSOS_MYSQL_USER}'\''@'\''%'\'' IDENTIFIED BY '\''${SPORTSOS_OLD_PASSWORD}'\'';
FLUSH PRIVILEGES;
SQL
    '

  cp -a "$BACKUP_DIR/.env.before-mysql-rotation" "$ENV_FILE"
  chmod 600 "$ENV_FILE"

  exit 1
fi

unset NEW_PASSWORD
unset CURRENT_PASSWORD
unset MYSQL_ROOT_PASSWORD

echo "New MySQL credential verified."

echo
echo "Recreating API only..."

docker compose up -d --force-recreate api

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
    echo "ERROR: API did not become healthy after MySQL rotation." >&2
    echo "Use the backup at:" >&2
    echo "  $BACKUP_DIR/.env.before-mysql-rotation" >&2
    exit 1
  fi

  sleep 2
done

echo
echo "Recreating dependent services..."

docker compose up -d dashboard scoreboard-simulator

echo
echo "Running readiness diagnostics..."
bash scripts/release-readiness-diagnostics.sh

echo
echo "Running release smoke test..."
bash scripts/release-smoke-test.sh || {
  echo
  echo "WARNING: smoke test still has a blocking failure."
  echo "Inspect diagnostics before declaring rotation complete."
  exit 1
}

echo
echo "MySQL credential rotation completed successfully."
EOF

chmod +x "$ROTATE"

cat >> "$DOC" <<'EOF'

## Milestone 26.3 — MySQL credential rotation workflow

SportsOS now includes a coordinated MySQL application-password rotation helper:

```text
scripts/rotate-mysql-password.sh
```

Default behavior is preflight-only:

```bash
bash scripts/rotate-mysql-password.sh
```

The preflight verifies the current application credential, MySQL root/admin credential, dedicated non-root application user, and required environment settings.

Rotation requires explicit opt-in:

```bash
SPORTSOS_APPLY_ROTATION=1 \
  bash scripts/rotate-mysql-password.sh
```

The workflow updates the actual MySQL account first, updates `.env` with the exact same value, verifies the new credential before restarting the API, and rolls back the database password plus `.env` if immediate verification fails.

The new password is never printed.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 26.3 MySQL credential rotation workflow", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/rotate-mysql-password.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("defaults to preflight only",()=> {
    expect(script).toContain(
      'APPLY="${SPORTSOS_APPLY_ROTATION:-0}"',
    );
    expect(script).toContain(
      "No credential was changed.",
    );
  });

  it("validates current application credential before changing anything",()=> {
    expect(script).toContain(
      "current MYSQL_PASSWORD in .env does not authenticate successfully",
    );
    expect(script).toContain(
      'mysql "-u${MYSQL_USER}"',
    );
  });

  it("validates administrative credential",()=> {
    expect(script).toContain(
      "MYSQL_ROOT_PASSWORD in .env does not authenticate as MySQL root",
    );
  });

  it("updates database account before environment file",()=> {
    const alterIndex =
      script.indexOf(
        "ALTER USER",
      );
    const envIndex =
      script.indexOf(
        "MYSQL_PASSWORD updated in .env",
      );

    expect(alterIndex).toBeGreaterThan(-1);
    expect(envIndex).toBeGreaterThan(alterIndex);
  });

  it("verifies new database credential before API restart",()=> {
    const verifyIndex =
      script.indexOf(
        "Verifying new MySQL application credential",
      );
    const apiIndex =
      script.indexOf(
        "docker compose up -d --force-recreate api",
      );

    expect(verifyIndex).toBeGreaterThan(-1);
    expect(apiIndex).toBeGreaterThan(verifyIndex);
  });

  it("contains automatic rollback for failed immediate credential verification",()=> {
    expect(script).toContain(
      "Restoring old MySQL account password and .env",
    );
  });

  it("does not print the new password",()=> {
    expect(script).not.toContain(
      'echo "$NEW_PASSWORD"',
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 26.3 installed"
echo "============================================================"
echo "Added:"
echo "  - MySQL credential rotation preflight"
echo "  - current credential verification"
echo "  - MySQL root credential verification"
echo "  - coordinated DB + .env password change"
echo "  - immediate new-credential verification"
echo "  - automatic rollback on verification failure"
echo "  - staged API/dependent-service restart"
echo "  - no password value printed"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then PREVIEW ONLY:"
echo "  bash scripts/rotate-mysql-password.sh"
echo
echo "Do NOT apply rotation unless the preflight passes."
echo
echo "Next after green:"
echo "  Milestone 26.4 - MinIO Credential Rotation Workflow"
