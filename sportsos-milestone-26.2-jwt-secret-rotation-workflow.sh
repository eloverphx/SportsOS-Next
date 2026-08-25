#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-26.2-jwt-rotation-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

ROTATE="scripts/rotate-jwt-secret.sh"
TEST="packages/core/test/jwt-secret-rotation-26.2.test.ts"
DOC="docs/PRODUCTION-SECURITY-HARDENING.md"

for required in \
  ".git" \
  "docker-compose.yml" \
  ".env" \
  "scripts/release-smoke-test.sh" \
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
EOF

chmod +x "$ROTATE"

cat >> "$DOC" <<'EOF'

## Milestone 26.2 — JWT secret rotation workflow

SportsOS now includes an explicit JWT rotation helper:

```text
scripts/rotate-jwt-secret.sh
```

Default execution is **preflight only**:

```bash
bash scripts/rotate-jwt-secret.sh
```

No secret is changed unless the operator explicitly runs:

```bash
SPORTSOS_APPLY_ROTATION=1 \
  bash scripts/rotate-jwt-secret.sh
```

The rotation workflow:

1. verifies `.env` and `JWT_SECRET`
2. creates a timestamped backup of the environment file
3. generates a cryptographically random replacement secret
4. updates `JWT_SECRET` without printing the new value
5. recreates API/dashboard containers
6. waits for API health
7. runs the release smoke test

Security effect:

```text
existing JWT sessions/tokens become invalid
users must sign in again
```

The new secret is not printed to stdout or written into logs by the rotation helper.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 26.2 JWT secret rotation workflow", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/rotate-jwt-secret.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("defaults to preflight-only behavior",()=> {
    expect(script).toContain(
      'APPLY="${SPORTSOS_APPLY_ROTATION:-0}"',
    );

    expect(script).toContain(
      "No credential was changed.",
    );
  });

  it("requires explicit rotation opt-in",()=> {
    expect(script).toContain(
      "SPORTSOS_APPLY_ROTATION=1",
    );
  });

  it("backs up environment before rotation",()=> {
    expect(script).toContain(
      ".env.before-jwt-rotation",
    );
  });

  it("generates a cryptographically random secret",()=> {
    expect(script).toContain(
      "randomBytes(48)",
    );
  });

  it("does not print the generated secret",()=> {
    expect(script).not.toContain(
      'echo "$NEW_SECRET"',
    );
  });

  it("recreates application containers and checks health",()=> {
    expect(script).toContain(
      "docker compose up -d --force-recreate api dashboard",
    );

    expect(script).toContain(
      "127.0.0.1:4001/health",
    );
  });

  it("documents session invalidation",()=> {
    expect(script).toContain(
      "Existing JWT sessions/tokens",
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 26.2 installed"
echo "============================================================"
echo "Added:"
echo "  - JWT rotation preflight"
echo "  - explicit apply gate"
echo "  - cryptographically random replacement secret"
echo "  - timestamped .env backup"
echo "  - no secret value printed"
echo "  - API/dashboard recreation"
echo "  - API health verification"
echo "  - session invalidation documentation"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Install verification:"
echo "  npm run typecheck && npm test"
echo
echo "JWT rotation PREVIEW only:"
echo "  bash scripts/rotate-jwt-secret.sh"
echo
echo "Do not apply the rotation until ready to invalidate active sessions."
echo
echo "Next after green:"
echo "  Milestone 26.3 - MySQL Credential Rotation Workflow"
