#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="14.1-firmware-hex-macro-collision-repair"
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
  "$ROOT/firmware/esp32-scoreboard/src/FirmwareUpdateDownloader.cpp" \
  "$ROOT/firmware/esp32-scoreboard/build-in-docker.sh"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

SOURCE="firmware/esp32-scoreboard/src/FirmwareUpdateDownloader.cpp"
TEST="packages/core/test/firmware-update-downloader-hex-macro-14.1-repair.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$SOURCE")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$TEST")"

cp -a "$SOURCE" "$BACKUP_DIR/$SOURCE"
[[ -f "$TEST" ]] && cp -a "$TEST" "$BACKUP_DIR/$TEST"

node <<'NODE'
const fs = require("fs");

const file =
  "firmware/esp32-scoreboard/src/FirmwareUpdateDownloader.cpp";

let text =
  fs.readFileSync(file, "utf8");

const functionMarker =
  "FirmwareUpdateDownloader::bytesToHex";

const start =
  text.indexOf(functionMarker);

if (start === -1) {
  throw new Error(
    "Unable to locate FirmwareUpdateDownloader::bytesToHex().",
  );
}

const nextFunction =
  text.indexOf(
    "\n}",
    start,
  );

if (nextFunction === -1) {
  throw new Error(
    "Unable to locate end of bytesToHex().",
  );
}

let block =
  text.slice(
    start,
    nextFunction + 2,
  );

/*
 * Arduino Print.h defines HEX as a numeric macro.
 * Never use HEX as an identifier in firmware code.
 */
if (
  block.includes(
    "static const char* HEX"
  )
) {
  block =
    block.replace(
      /static const char\*\s+HEX\s*=/,
      "static const char* HEX_DIGITS =",
    );

  block =
    block.replace(
      /\bHEX\[/g,
      "HEX_DIGITS[",
    );
}

if (
  /\bHEX\s*=/.test(block) ||
  /\bHEX\[/.test(block)
) {
  throw new Error(
    "Arduino HEX macro collision remains in bytesToHex().",
  );
}

if (
  !block.includes(
    "HEX_DIGITS"
  )
) {
  throw new Error(
    "Expected HEX_DIGITS lookup table was not created.",
  );
}

text =
  text.slice(0, start) +
  block +
  text.slice(nextFunction + 2);

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("ESP32 FirmwareUpdateDownloader Arduino HEX macro repair", () => {
  const source = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/FirmwareUpdateDownloader.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  const marker =
    source.indexOf(
      "FirmwareUpdateDownloader::bytesToHex",
    );

  const block =
    source.slice(
      marker,
      source.indexOf(
        "\n}",
        marker,
      ) + 2,
    );

  it("does not declare HEX as an identifier", () => {
    expect(block).not.toMatch(
      /static const char\*\s+HEX\s*=/,
    );
  });

  it("uses a non-conflicting hexadecimal lookup table", () => {
    expect(block).toContain(
      "HEX_DIGITS",
    );

    expect(block).not.toContain(
      "HEX[",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next ESP32 HEX macro collision repair installed"
echo "============================================================"
echo
echo "Repair:"
echo "  - fixes Arduino Print.h HEX macro collision"
echo "  - renames OTA SHA-256 hex lookup table to HEX_DIGITS"
echo "  - preserves bytesToHex behavior"
echo "  - adds regression coverage"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then real firmware compile:"
echo "  bash firmware/esp32-scoreboard/build-in-docker.sh"
