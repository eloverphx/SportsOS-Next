#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10.1-core-nodenext-export-repair"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  exit 1
fi

cd "$ROOT"

INDEX="packages/core/src/index.ts"
TEST="packages/core/test/core-nodenext-exports-10.1-repair.test.ts"

[[ -f "$INDEX" ]] || {
  echo "ERROR: required file missing: $INDEX" >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$INDEX")" \
  "$BACKUP_DIR/$(dirname "$TEST")"

cp -a "$INDEX" "$BACKUP_DIR/$INDEX"
[[ -f "$TEST" ]] && cp -a "$TEST" "$BACKUP_DIR/$TEST"

node <<'NODE'
const fs = require("fs");

const file = "packages/core/src/index.ts";
let text = fs.readFileSync(file, "utf8");

text = text.replaceAll(
  'export * from "./scoreboard-device-contract";',
  'export * from "./scoreboard-device-contract.js";',
);

text = text.replaceAll(
  'export * from "./scoreboard-mqtt-contract";',
  'export * from "./scoreboard-mqtt-contract.js";',
);

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 10.1 NodeNext export repair", () => {
  it("uses explicit .js extension for the scoreboard device contract export", () => {
    const index = fs.readFileSync(
      new URL("../src/index.ts", import.meta.url),
      "utf8",
    );

    expect(index).toContain(
      'export * from "./scoreboard-device-contract.js";',
    );
  });

  it("uses explicit .js extension for the MQTT contract export when present", () => {
    const index = fs.readFileSync(
      new URL("../src/index.ts", import.meta.url),
      "utf8",
    );

    if (index.includes("scoreboard-mqtt-contract")) {
      expect(index).toContain(
        'export * from "./scoreboard-mqtt-contract.js";',
      );
    }
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next NodeNext export repair installed"
echo "============================================================"
echo
echo "Fixed:"
echo "  - scoreboard-device-contract export now ends in .js"
echo "  - scoreboard-mqtt-contract export also repaired if already present"
echo "  - regression test added"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
