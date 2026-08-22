#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="13.2-core-public-export-repair"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

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
  "$ROOT/packages/core/package.json" \
  "$ROOT/packages/core/src/index.ts" \
  "$ROOT/packages/core/src/scoreboard-firmware-update-contract.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

PKG="packages/core/package.json"
INDEX="packages/core/src/index.ts"
CONTRACT="packages/core/src/scoreboard-firmware-update-contract.ts"
TEST="packages/core/test/core-public-ota-export-13.2-repair.test.ts"

mkdir -p \
  "$BACKUP_DIR/packages/core/src" \
  "$BACKUP_DIR/packages/core/test" \
  "$BACKUP_DIR/packages/core"

cp -a "$PKG" "$BACKUP_DIR/$PKG"
cp -a "$INDEX" "$BACKUP_DIR/$INDEX"
[[ -f "$TEST" ]] && cp -a "$TEST" "$BACKUP_DIR/$TEST"

node <<'NODE'
const fs = require("fs");

const pkgFile = "packages/core/package.json";
const pkg = JSON.parse(fs.readFileSync(pkgFile, "utf8"));

/*
 * Preserve existing package structure, but make sure the package's
 * type/runtime entrypoints reference the built index rather than a stale
 * explicit export list or missing declaration surface.
 */
if (pkg.exports && typeof pkg.exports === "object") {
  if (pkg.exports["."] && typeof pkg.exports["."] === "object") {
    const root = pkg.exports["."];

    if (!root.types) {
      root.types = "./dist/index.d.ts";
    }

    if (!root.import) {
      root.import = "./dist/index.js";
    }

    if (!root.default) {
      root.default = "./dist/index.js";
    }
  }
}

if (!pkg.types) {
  pkg.types = "./dist/index.d.ts";
}

if (!pkg.main) {
  pkg.main = "./dist/index.js";
}

fs.writeFileSync(
  pkgFile,
  JSON.stringify(pkg, null, 2) + "\n",
);
NODE

if ! grep -q 'scoreboard-firmware-update-contract.js' "$INDEX"; then
  printf '\nexport * from "./scoreboard-firmware-update-contract.js";\n' >> "$INDEX"
fi

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.2 core OTA public export repair", () => {
  it("exports the OTA firmware contract from the core index", () => {
    const index = fs.readFileSync(
      new URL(
        "../src/index.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(index).toContain(
      'export * from "./scoreboard-firmware-update-contract.js";',
    );
  });

  it("publishes declaration entrypoint from the core package", () => {
    const pkg = JSON.parse(
      fs.readFileSync(
        new URL(
          "../package.json",
          import.meta.url,
        ),
        "utf8",
      ),
    );

    expect(pkg.types).toBe(
      "./dist/index.d.ts",
    );
  });

  it("keeps OTA contract source present", () => {
    const source = fs.readFileSync(
      new URL(
        "../src/scoreboard-firmware-update-contract.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "FirmwareReleaseChannel",
    );
    expect(source).toContain(
      "FirmwareReleaseTarget",
    );
    expect(source).toContain(
      "ScoreboardFirmwareRelease",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 13.2 core export repair installed"
echo "============================================================"
echo
echo "Repair:"
echo "  - confirms OTA contract export from packages/core/src/index.ts"
echo "  - ensures @sportsos/core publishes dist/index.d.ts"
echo "  - preserves existing package export structure"
echo "  - adds regression coverage"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run build --workspace @sportsos/core"
echo "  npm run typecheck && npm test"
