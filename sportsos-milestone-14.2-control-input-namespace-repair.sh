#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="14.2-control-input-namespace-repair"
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
  "$ROOT/firmware/esp32-scoreboard/src/main.cpp" \
  "$ROOT/firmware/esp32-scoreboard/include/ScoreboardControlInput.h" \
  "$ROOT/firmware/esp32-scoreboard/include/GpioButtonInput.h"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

MAIN="firmware/esp32-scoreboard/src/main.cpp"
TEST="packages/core/test/gpio-button-control-input-namespace-14.2-repair.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$MAIN")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$TEST")"

cp -a "$MAIN" "$BACKUP_DIR/$MAIN"
[[ -f "$TEST" ]] && cp -a "$TEST" "$BACKUP_DIR/$TEST"

node <<'NODE'
const fs = require("fs");

const file =
  "firmware/esp32-scoreboard/src/main.cpp";

let text =
  fs.readFileSync(file, "utf8");

const requiredUsings = [
  "using sportsos::ScoreboardControlInput;",
  "using sportsos::ScoreboardControlInputType;",
];

for (const line of requiredUsings) {
  if (text.includes(line)) {
    continue;
  }

  const matches =
    [...text.matchAll(/^using sportsos::.*?;$/gm)];

  if (matches.length === 0) {
    throw new Error(
      `Unable to locate sportsos using declarations for ${line}`,
    );
  }

  const last =
    matches[matches.length - 1];

  const insertAt =
    last.index +
    last[0].length;

  text =
    text.slice(0, insertAt) +
    "\n" +
    line +
    text.slice(insertAt);
}

if (
  !text.includes(
    "using sportsos::ScoreboardControlInput;",
  ) ||
  !text.includes(
    "using sportsos::ScoreboardControlInputType;",
  )
) {
  throw new Error(
    "Required control-input namespace aliases were not installed.",
  );
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.2 control-input namespace repair", () => {
  const main = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/main.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  it("imports ScoreboardControlInput into main namespace", () => {
    expect(main).toContain(
      "using sportsos::ScoreboardControlInput;",
    );
  });

  it("imports ScoreboardControlInputType into main namespace", () => {
    expect(main).toContain(
      "using sportsos::ScoreboardControlInputType;",
    );
  });

  it("keeps GPIO button mappings on the shared control contract", () => {
    expect(main).toContain(
      "ScoreboardControlInputType::ScoreHomeIncrement",
    );

    expect(main).toContain(
      "ScoreboardControlInput::typeText",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 14.2 namespace repair installed"
echo "============================================================"
echo
echo "Repair:"
echo "  - adds ScoreboardControlInput namespace alias"
echo "  - adds ScoreboardControlInputType namespace alias"
echo "  - leaves GPIO button/debounce logic unchanged"
echo "  - adds focused regression coverage"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then retry real firmware compile:"
echo "  bash firmware/esp32-scoreboard/build-in-docker.sh"
