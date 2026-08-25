#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
APP="${ROOT}/apps/api/src/app.ts"
TEST="${ROOT}/apps/api/test/security-regression-26.9.test.ts"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-26.9-security-header-scope-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for file in "$APP" "$TEST"; do
  [[ -f "$file" ]] || {
    echo "ERROR: missing $file" >&2
    exit 1
  }
done

mkdir -p "$BACKUP/apps/api/src" "$BACKUP/apps/api/test"
cp -a "$APP" "$BACKUP/apps/api/src/app.ts"
cp -a "$TEST" "$BACKUP/apps/api/test/security-regression-26.9.test.ts"

node <<'NODE'
const fs = require("fs");

const appFile = "apps/api/src/app.ts";
let app = fs.readFileSync(appFile, "utf8");

app = app.replace(
  /await app\.register\(\s*securityHeadersPlugin,\s*\);/m,
  `await securityHeadersPlugin(
  app,
);`,
);

if (
  !app.includes(
    "await securityHeadersPlugin(",
  )
) {
  throw new Error(
    "Unable to convert securityHeadersPlugin to root-scope registration in app.ts",
  );
}

fs.writeFileSync(
  appFile,
  app,
);

const testFile =
  "apps/api/test/security-regression-26.9.test.ts";

let test =
  fs.readFileSync(
    testFile,
    "utf8",
  );

test = test.replace(
  /await app\.register\(\s*securityHeadersPlugin,\s*\);/m,
  `await securityHeadersPlugin(
    app,
  );`,
);

if (
  !test.includes(
    "await securityHeadersPlugin(",
  )
) {
  throw new Error(
    "Unable to convert isolated test app to root-scope security hook.",
  );
}

fs.writeFileSync(
  testFile,
  test,
);
NODE

echo "============================================================"
echo " SportsOS 26.9 security header scope repair installed"
echo "============================================================"
echo
echo "Fixed:"
echo "  - security hook now attaches to root Fastify instance"
echo "  - /health and sibling routes inherit security headers"
echo "  - isolated regression test uses same root-scope behavior"
echo "  - no database/startup dependency introduced"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  curl -I http://127.0.0.1:4001/health"
echo "  bash scripts/security-regression-check.sh"
