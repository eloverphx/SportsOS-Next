#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10-scoreboard-route-tests-repair"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  echo "Expected: $EXPECTED_REAL" >&2
  echo "Received: $ROOT_REAL" >&2
  exit 1
fi

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/test" \
  "$ROOT/apps/api/src"
do
  [[ -e "$required" ]] || {
    echo "ERROR: repository safety marker missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

TEST_GATEWAY="apps/api/test/scoreboard-device-gateway-10.4.test.ts"
TEST_DUP="apps/api/test/scoreboard-route-duplication-repair.test.ts"
CUSTOM_ROUTE="apps/api/src/routes/scoreboardDevices.ts"

for file in "$TEST_GATEWAY" "$TEST_DUP" "$CUSTOM_ROUTE"; do
  [[ -f "$file" ]] || {
    echo "ERROR: required file missing: $file" >&2
    exit 1
  }
done

mapfile -t CANONICAL_CANDIDATES < <(
  grep -RIl \
    --include='*.ts' \
    --exclude='scoreboardDevices.ts' \
    '"/scoreboard-devices"' \
    apps/api/src 2>/dev/null || true
)

if [[ "${#CANONICAL_CANDIDATES[@]}" -eq 0 ]]; then
  echo "ERROR: canonical scoreboard route source not found." >&2
  echo "No files were modified." >&2
  exit 1
fi

CANONICAL_ROUTE="${CANONICAL_CANDIDATES[0]}"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$TEST_GATEWAY")" \
  "$BACKUP_DIR/$(dirname "$TEST_DUP")"

cp -a "$TEST_GATEWAY" "$BACKUP_DIR/$TEST_GATEWAY"
cp -a "$TEST_DUP" "$BACKUP_DIR/$TEST_DUP"

CANONICAL_ROUTE="$CANONICAL_ROUTE" node <<'NODE'
const fs = require("fs");
const path = require("path");

const gatewayTest =
  "apps/api/test/scoreboard-device-gateway-10.4.test.ts";

let text =
  fs.readFileSync(gatewayTest, "utf8");

/*
 * The custom Milestone 10 route file no longer owns the base GET routes.
 * Update the old 10.4 assertion to validate only the gateway-specific
 * endpoints that remain in that file.
 */
text = text.replace(
  /expect\(route\)\.toContain\('\"\/scoreboard-devices\"'\);\s*/g,
  "",
);

text = text.replace(
  /expect\(route\)\.toContain\('\"\/scoreboard-devices\/:deviceId\"'\);\s*/g,
  "",
);

if (
  !text.includes(
    '"/scoreboard-devices/:deviceId/commands"',
  )
) {
  throw new Error(
    "10.4 gateway test does not appear to assert the commands endpoint.",
  );
}

fs.writeFileSync(
  gatewayTest,
  text,
);

const dupTest =
  "apps/api/test/scoreboard-route-duplication-repair.test.ts";

let dup =
  fs.readFileSync(dupTest, "utf8");

const canonical =
  process.env.CANONICAL_ROUTE;

if (!canonical) {
  throw new Error(
    "CANONICAL_ROUTE environment variable missing.",
  );
}

const testDir =
  path.dirname(
    path.resolve(dupTest),
  );

let relative =
  path.relative(
    testDir,
    path.resolve(canonical),
  )
    .replaceAll("\\", "/");

if (!relative.startsWith(".")) {
  relative = `./${relative}`;
}

dup = dup.replace(
  /new URL\(\s*"[^"]*scoreboard-devices\/routes\.ts",\s*import\.meta\.url,\s*\)/m,
  `new URL(\n        "${relative}",\n        import.meta.url,\n      )`,
);

fs.writeFileSync(
  dupTest,
  dup,
);
NODE

echo
echo "============================================================"
echo " SportsOS-Next scoreboard route test repair installed"
echo "============================================================"
echo
echo "Production code changed:"
echo "  NO"
echo
echo "Updated tests:"
echo "  - removed stale expectation that custom route owns GET /scoreboard-devices"
echo "  - removed stale expectation that custom route owns GET /scoreboard-devices/:deviceId"
echo "  - corrected canonical route test path"
echo
echo "Canonical route:"
echo "  $CANONICAL_ROUTE"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo "  docker compose up -d --build api"
echo "  docker compose ps api"
echo "  curl -i http://192.168.5.3:4001/health"
