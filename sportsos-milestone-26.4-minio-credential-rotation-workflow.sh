#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-26.4-minio-rotation-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

ROTATE="scripts/rotate-minio-credentials.sh"
TEST="packages/core/test/minio-credential-rotation-26.4.test.ts"
DOC="docs/PRODUCTION-SECURITY-HARDENING.md"

for required in \
  ".git" \
  ".env" \
  "docker-compose.yml" \
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
BACKUP_DIR="${ROOT}/.security-backups/minio-${STAMP}"

cd "$ROOT"

[[ -f "$ENV_FILE" ]] || {
  echo "ERROR: environment file not found: $ENV_FILE" >&2
  exit 1
}

for name in MINIO_ROOT_USER MINIO_ROOT_PASSWORD; do
  grep -q "^${name}=" "$ENV_FILE" || {
    echo "ERROR: ${name} is missing from $ENV_FILE" >&2
    exit 1
  }
done

MINIO_USER="$(
  awk -F= '/^MINIO_ROOT_USER=/{print substr($0,index($0,"=")+1); exit}' "$ENV_FILE"
)"

CURRENT_SECRET="$(
  awk -F= '/^MINIO_ROOT_PASSWORD=/{print substr($0,index($0,"=")+1); exit}' "$ENV_FILE"
)"

[[ -n "$MINIO_USER" ]] || {
  echo "ERROR: MINIO_ROOT_USER is empty." >&2
  exit 1
}

[[ -n "$CURRENT_SECRET" ]] || {
  echo "ERROR: MINIO_ROOT_PASSWORD is empty." >&2
  exit 1
}

echo "Checking current MinIO credentials..."

if ! docker exec \
  -e MC_HOST_sportsos="http://${MINIO_USER}:${CURRENT_SECRET}@127.0.0.1:9000" \
  sportsos_minio \
  sh -lc '
    if command -v mc >/dev/null 2>&1; then
      mc ready sportsos >/dev/null 2>&1
    else
      exit 42
    fi
  '
then
  rc=$?

  if [[ "$rc" == "42" ]]; then
    echo "ERROR: MinIO client (mc) is not available in the MinIO container." >&2
    echo "No credential was changed." >&2
    exit 1
  fi

  echo "ERROR: current MinIO credentials do not authenticate successfully." >&2
  echo "No credential was changed." >&2
  exit 1
fi

echo "Current MinIO credentials are valid."

if [[ "$APPLY" != "1" ]]; then
  echo
  echo "MinIO credential rotation preflight PASSED."
  echo
  echo "No credential was changed."
  echo
  echo "Important:"
  echo "  MinIO root credentials are bootstrap credentials."
  echo "  Rotating them safely requires container recreation with the new values."
  echo
  echo "To perform rotation:"
  echo "  SPORTSOS_APPLY_ROTATION=1 bash scripts/rotate-minio-credentials.sh"
  exit 0
fi

mkdir -p "$BACKUP_DIR"
cp -a "$ENV_FILE" "$BACKUP_DIR/.env.before-minio-rotation"

NEW_SECRET="$(
  node -e "console.log(require('crypto').randomBytes(36).toString('base64url'))"
)"

[[ "${#NEW_SECRET}" -ge 12 ]] || {
  echo "ERROR: generated MinIO secret is unexpectedly short." >&2
  exit 1
}

node - "$ENV_FILE" "$NEW_SECRET" <<'NODE'
const fs = require("fs");

const file = process.argv[2];
const secret = process.argv[3];

let source = fs.readFileSync(file, "utf8");

if (!/^MINIO_ROOT_PASSWORD=.*$/m.test(source)) {
  throw new Error("MINIO_ROOT_PASSWORD entry not found.");
}

source = source.replace(
  /^MINIO_ROOT_PASSWORD=.*$/m,
  `MINIO_ROOT_PASSWORD=${secret}`,
);

fs.writeFileSync(
  file,
  source,
  {
    mode: 0o600,
  },
);
NODE

echo "MINIO_ROOT_PASSWORD updated in .env without printing the new value."

echo
echo "Recreating MinIO with the new root credential..."

docker compose up -d --force-recreate minio

echo "Waiting for MinIO health..."

healthy=0

for attempt in $(seq 1 45); do
  status="$(
    docker inspect sportsos_minio \
      --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
      2>/dev/null || true
  )"

  if [[ "$status" == "healthy" ]]; then
    healthy=1
    break
  fi

  sleep 2
done

if [[ "$healthy" != "1" ]]; then
  echo "ERROR: MinIO did not become healthy after credential rotation." >&2
  echo "Environment backup:" >&2
  echo "  $BACKUP_DIR/.env.before-minio-rotation" >&2
  exit 1
fi

echo "MinIO is healthy."

echo "Verifying new MinIO credential..."

if ! docker exec \
  -e MC_HOST_sportsos="http://${MINIO_USER}:${NEW_SECRET}@127.0.0.1:9000" \
  sportsos_minio \
  sh -lc '
    mc ready sportsos >/dev/null 2>&1
  '
then
  echo "ERROR: new MinIO credential failed authentication." >&2
  echo "Environment backup:" >&2
  echo "  $BACKUP_DIR/.env.before-minio-rotation" >&2
  exit 1
fi

echo "New MinIO credential verified."

unset NEW_SECRET
unset CURRENT_SECRET

echo
echo "Recreating API after MinIO verification..."

docker compose up -d --force-recreate api

echo "Waiting for API health..."

api_healthy=0

for attempt in $(seq 1 45); do
  if node -e "
    fetch('http://127.0.0.1:4001/health')
      .then(r => process.exit(r.ok ? 0 : 1))
      .catch(() => process.exit(1))
  "; then
    api_healthy=1
    break
  fi

  sleep 2
done

if [[ "$api_healthy" != "1" ]]; then
  echo "ERROR: API did not become healthy after MinIO rotation." >&2
  echo "Inspect:" >&2
  echo "  docker compose logs --tail=120 api" >&2
  exit 1
fi

echo "API is healthy."

docker compose up -d dashboard scoreboard-simulator

echo
echo "Running readiness diagnostics..."
bash scripts/release-readiness-diagnostics.sh

echo
echo "MinIO credential rotation completed."
EOF

chmod +x "$ROTATE"

cat >> "$DOC" <<'EOF'

## Milestone 26.4 — MinIO credential rotation workflow

SportsOS now includes a coordinated MinIO credential rotation helper:

```text
scripts/rotate-minio-credentials.sh
```

Default execution is preflight-only:

```bash
bash scripts/rotate-minio-credentials.sh
```

The preflight validates the current MinIO access/secret pair using `mc` from inside the MinIO container.

Rotation requires explicit opt-in:

```bash
SPORTSOS_APPLY_ROTATION=1 \
  bash scripts/rotate-minio-credentials.sh
```

The workflow:

1. validates current MinIO credentials
2. backs up `.env`
3. generates a strong replacement secret
4. updates `.env` without printing the value
5. recreates MinIO with the new root credential
6. waits for MinIO health
7. verifies the new credential with `mc`
8. recreates the API
9. waits for API health
10. restores dependent services
11. runs readiness diagnostics

The new secret is never printed.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 26.4 MinIO credential rotation workflow", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/rotate-minio-credentials.sh",
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

  it("validates current MinIO credentials first",()=> {
    expect(script).toContain(
      "Checking current MinIO credentials",
    );

    expect(script).toContain(
      "MC_HOST_sportsos",
    );

    expect(script).toContain(
      "mc ready sportsos",
    );
  });

  it("backs up environment before rotation",()=> {
    expect(script).toContain(
      ".env.before-minio-rotation",
    );
  });

  it("recreates MinIO before API",()=> {
    const minioIndex =
      script.indexOf(
        "docker compose up -d --force-recreate minio",
      );

    const apiIndex =
      script.indexOf(
        "docker compose up -d --force-recreate api",
      );

    expect(minioIndex).toBeGreaterThan(-1);
    expect(apiIndex).toBeGreaterThan(minioIndex);
  });

  it("verifies new MinIO credential before API recreation",()=> {
    const verifyIndex =
      script.indexOf(
        "Verifying new MinIO credential",
      );

    const apiIndex =
      script.indexOf(
        "docker compose up -d --force-recreate api",
      );

    expect(verifyIndex).toBeGreaterThan(-1);
    expect(apiIndex).toBeGreaterThan(verifyIndex);
  });

  it("does not print the new secret",()=> {
    expect(script).not.toContain(
      'echo "$NEW_SECRET"',
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 26.4 installed"
echo "============================================================"
echo "Added:"
echo "  - MinIO credential rotation preflight"
echo "  - current credential verification"
echo "  - explicit apply gate"
echo "  - strong secret generation"
echo "  - .env backup"
echo "  - MinIO recreation + health wait"
echo "  - new credential verification"
echo "  - staged API/dependent-service restart"
echo "  - no secret value printed"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then PREVIEW ONLY:"
echo "  bash scripts/rotate-minio-credentials.sh"
echo
echo "Do NOT apply rotation unless preflight passes."
echo
echo "Next after green:"
echo "  Milestone 26.5 - Secret File / Environment Source Hardening"
