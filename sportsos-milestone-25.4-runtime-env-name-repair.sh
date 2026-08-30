#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
REL_SERVICE="apps/api/src/services/secretEnvironmentValidation.ts"
SERVICE="${ROOT}/${REL_SERVICE}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-25.4-runtime-env-name-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

[[ -f "$SERVICE" ]] || {
  echo "ERROR: missing $SERVICE" >&2
  exit 1
}

mkdir -p "$BACKUP/$(dirname "$REL_SERVICE")"
cp -a "$REL_SERVICE" "$BACKUP/$REL_SERVICE"

node <<'NODE'
const fs = require("fs");

const file =
  "/mnt/user/appdata/SportsOS-Next/apps/api/src/services/secretEnvironmentValidation.ts";

let s =
  fs.readFileSync(
    file,
    "utf8",
  );

s = s.replace(
  /env\.MINIO_ROOT_PASSWORD/g,
  "env.MINIO_SECRET_KEY",
);

s = s.replace(
  /env\.SPORTSOS_DASHBOARD_URL/g,
  "env.DASHBOARD_ORIGIN",
);

s = s.replace(
  /env\.SPORTSOS_API_URL/g,
  "env.PUBLIC_API_URL",
);

s = s.replace(
  /env\.MINIO_ROOT_USER/g,
  "env.MINIO_ACCESS_KEY",
);

s = s.replace(
  /SPORTSOS_DASHBOARD_URL must be a valid http\(s\) URL\./g,
  "DASHBOARD_ORIGIN must be a valid http(s) URL.",
);

s = s.replace(
  /SPORTSOS_API_URL must be a valid http\(s\) URL\./g,
  "PUBLIC_API_URL must be a valid http(s) URL.",
);

s = s.replace(
  /MINIO_ROOT_USER must be configured\./g,
  "MINIO_ACCESS_KEY must be configured.",
);

if (
  s.includes(
    "SPORTSOS_DASHBOARD_URL",
  ) ||
  s.includes(
    "SPORTSOS_API_URL",
  ) ||
  s.includes(
    "MINIO_ROOT_USER",
  ) ||
  s.includes(
    "MINIO_ROOT_PASSWORD",
  )
) {
  throw new Error(
    "Legacy compose-time environment names remain after repair.",
  );
}

fs.writeFileSync(
  file,
  s,
);

console.log(
  "25.4 repaired to validate actual API runtime environment names.",
);
NODE

TEST="packages/core/test/secret-environment-validation-25.4.test.ts"

if [[ -f "$TEST" ]]; then
  mkdir -p "$BACKUP/$(dirname "$TEST")"
  cp -a "$TEST" "$BACKUP/$TEST"

  node <<'NODE'
const fs = require("fs");
const file =
  "packages/core/test/secret-environment-validation-25.4.test.ts";

let s =
  fs.readFileSync(
    file,
    "utf8",
  );

s = s.replace(
  /MINIO_ROOT_PASSWORD:/g,
  "MINIO_SECRET_KEY:",
);

s = s.replace(
  /SPORTSOS_DASHBOARD_URL:/g,
  "DASHBOARD_ORIGIN:",
);

s = s.replace(
  /SPORTSOS_API_URL:/g,
  "PUBLIC_API_URL:",
);

s = s.replace(
  /MINIO_ROOT_USER:/g,
  "MINIO_ACCESS_KEY:",
);

s = s.replace(
  /goodEnv\.MINIO_ROOT_PASSWORD/g,
  "goodEnv.MINIO_SECRET_KEY",
);

s = s.replace(
  /SPORTSOS_API_URL:/g,
  "PUBLIC_API_URL:",
);

fs.writeFileSync(
  file,
  s,
);
NODE
fi

echo
echo "============================================================"
echo " SportsOS Milestone 25.4 runtime env-name repair installed"
echo "============================================================"
echo "Fixed validation names:"
echo "  SPORTSOS_DASHBOARD_URL -> DASHBOARD_ORIGIN"
echo "  SPORTSOS_API_URL       -> PUBLIC_API_URL"
echo "  MINIO_ROOT_USER        -> MINIO_ACCESS_KEY"
echo "  MINIO_ROOT_PASSWORD    -> MINIO_SECRET_KEY"
echo
echo "Secret-strength requirements remain unchanged."
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo "  docker compose up -d --build api dashboard"
echo "  bash scripts/release-readiness-diagnostics.sh"
echo "  bash scripts/release-smoke-test.sh"
