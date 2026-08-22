#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10.4-registration-test-path-repair"
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
  exit 1
fi

cd "$ROOT"

TEST="apps/api/test/scoreboard-device-gateway-10.4.test.ts"

[[ -f "$TEST" ]] || {
  echo "ERROR: required test missing: $TEST" >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$TEST")"

cp -a "$TEST" "$BACKUP_DIR/$TEST"

REG_FILE=""

for preferred in \
  "apps/api/src/app.ts" \
  "apps/api/src/server.ts" \
  "apps/api/src/index.ts" \
  "apps/api/src/routes/index.ts"
do
  if [[ -f "$preferred" ]] && grep -q "scoreboardDevicesRoutes" "$preferred"; then
    REG_FILE="$preferred"
    break
  fi
done

if [[ -z "$REG_FILE" ]]; then
  mapfile -t MATCHES < <(
    grep -RIl \
      --include='*.ts' \
      "scoreboardDevicesRoutes" \
      apps/api/src 2>/dev/null || true
  )

  for file in "${MATCHES[@]}"; do
    if [[ "$file" != "apps/api/src/routes/scoreboardDevices.ts" ]]; then
      REG_FILE="$file"
      break
    fi
  done
fi

if [[ -z "$REG_FILE" ]]; then
  echo "ERROR: could not find the API file that registers scoreboardDevicesRoutes." >&2
  echo "No test changes were made." >&2
  exit 1
fi

echo "Discovered registration file:"
echo "  $REG_FILE"

REG_FILE="$REG_FILE" node <<'NODE'
const fs = require("fs");
const path = require("path");

const testFile =
  "apps/api/test/scoreboard-device-gateway-10.4.test.ts";

const regFile = process.env.REG_FILE;

if (!regFile) {
  throw new Error("REG_FILE missing.");
}

let text = fs.readFileSync(testFile, "utf8");

const testDir =
  path.dirname(
    path.resolve(testFile),
  );

let relative =
  path.relative(
    testDir,
    path.resolve(regFile),
  )
  .replaceAll("\\", "/");

if (!relative.startsWith(".")) {
  relative = `./${relative}`;
}

const oldBlock = /it\("registers the device routes in the discovered API file",\s*\(\)\s*=>\s*\{[\s\S]*?\n\s*\}\);/;

if (!oldBlock.test(text)) {
  throw new Error(
    "Could not locate the registration-path test block.",
  );
}

const replacement = `it("registers the device routes in the discovered API file", () => {
    const source = fs.readFileSync(
      new URL(
        "${relative}",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "scoreboardDevicesRoutes",
    );
  });`;

text = text.replace(
  oldBlock,
  replacement,
);

fs.writeFileSync(
  testFile,
  text,
);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 10.4 test path repair installed"
echo "============================================================"
echo
echo "Fixed:"
echo "  - registration test now targets the actual discovered API file"
echo "  - no production gateway code changed"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo "  docker compose up -d --build api"
