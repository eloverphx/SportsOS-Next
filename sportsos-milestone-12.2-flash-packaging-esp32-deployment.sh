#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="12.2-flash-packaging-esp32-deployment"
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
  "$ROOT/firmware/esp32-scoreboard/platformio.ini" \
  "$ROOT/firmware/esp32-scoreboard/build-in-docker.sh"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

FW_DIR="firmware/esp32-scoreboard"
BUILD_DIR="$FW_DIR/.pio/build/esp32dev"
FIRMWARE_BIN="$BUILD_DIR/firmware.bin"
FIRMWARE_ELF="$BUILD_DIR/firmware.elf"
BOOTLOADER_BIN="$BUILD_DIR/bootloader.bin"
PARTITIONS_BIN="$BUILD_DIR/partitions.bin"
BOOT_APP0_BIN="$BUILD_DIR/boot_app0.bin"

if [[ ! -f "$FIRMWARE_BIN" ]]; then
  echo "ERROR: compiled firmware is missing:" >&2
  echo "  $FIRMWARE_BIN" >&2
  echo >&2
  echo "Run this first:" >&2
  echo "  bash firmware/esp32-scoreboard/build-in-docker.sh" >&2
  echo >&2
  echo "Repository was not modified." >&2
  exit 1
fi

RELEASE_ROOT="$FW_DIR/releases"
PACKAGE_DIR="$RELEASE_ROOT/esp32dev-${STAMP}"
FLASH_SCRIPT="$FW_DIR/flash-with-docker.sh"
MANIFEST="$FW_DIR/FLASH-MANIFEST.md"
README="$FW_DIR/README.md"
TEST="packages/core/test/esp32-flash-packaging-12.2.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$FLASH_SCRIPT")" \
  "$BACKUP_DIR/$(dirname "$MANIFEST")" \
  "$BACKUP_DIR/$(dirname "$README")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$PACKAGE_DIR" \
  "$(dirname "$TEST")"

for file in "$FLASH_SCRIPT" "$MANIFEST" "$README" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cp -a "$FIRMWARE_BIN" "$PACKAGE_DIR/firmware.bin"

if [[ -f "$FIRMWARE_ELF" ]]; then
  cp -a "$FIRMWARE_ELF" "$PACKAGE_DIR/firmware.elf"
fi

if [[ -f "$BOOTLOADER_BIN" ]]; then
  cp -a "$BOOTLOADER_BIN" "$PACKAGE_DIR/bootloader.bin"
fi

if [[ -f "$PARTITIONS_BIN" ]]; then
  cp -a "$PARTITIONS_BIN" "$PACKAGE_DIR/partitions.bin"
fi

if [[ -f "$BOOT_APP0_BIN" ]]; then
  cp -a "$BOOT_APP0_BIN" "$PACKAGE_DIR/boot_app0.bin"
fi

sha256sum "$PACKAGE_DIR"/*.bin > "$PACKAGE_DIR/SHA256SUMS.txt"

cat > "$PACKAGE_DIR/flash-layout.txt" <<'EOF'
SportsOS ESP32 flash layout

Common ESP32 Arduino / PlatformIO layout:

0x1000    bootloader.bin
0x8000    partitions.bin
0xE000    boot_app0.bin
0x10000   firmware.bin

Only files actually produced by the PlatformIO build are included in this package.
EOF

cat > "$MANIFEST" <<EOF
# SportsOS ESP32 Flash Manifest

Generated package:

\`$PACKAGE_DIR\`

## Primary application image

- Application: \`firmware.bin\`
- Default application offset: \`0x10000\`

## Full flash layout

When all PlatformIO-generated images are present:

- \`0x1000 bootloader.bin\`
- \`0x8000 partitions.bin\`
- \`0xE000 boot_app0.bin\`
- \`0x10000 firmware.bin\`

## Integrity

SHA-256 hashes are stored in:

\`$PACKAGE_DIR/SHA256SUMS.txt\`

## Build source

The package was created from:

\`$BUILD_DIR\`

Do not flash binaries from a different build directory or board profile into this package.
EOF

cat > "$FLASH_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"

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

PORT="${1:-}"

if [[ -z "$PORT" ]]; then
  echo "Usage:"
  echo "  bash firmware/esp32-scoreboard/flash-with-docker.sh /dev/ttyUSB0"
  echo
  echo "Common Linux device names:"
  echo "  /dev/ttyUSB0"
  echo "  /dev/ttyACM0"
  exit 1
fi

if [[ ! -e "$PORT" ]]; then
  echo "ERROR: serial device does not exist: $PORT" >&2
  exit 1
fi

FW_DIR="firmware/esp32-scoreboard"
IMAGE="sportsos-platformio:12.1"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "PlatformIO image not found; building it first..."
  docker build \
    -f "$FW_DIR/Dockerfile.platformio" \
    -t "$IMAGE" \
    "$FW_DIR"
fi

echo "Flashing SportsOS firmware through PlatformIO container..."
echo "Serial device: $PORT"

docker run --rm \
  --device="$PORT:$PORT" \
  -v "$ROOT/$FW_DIR:/workspace" \
  -v sportsos_platformio_core:/platformio \
  -w /workspace \
  "$IMAGE" \
  run \
  --target upload \
  --upload-port "$PORT"

echo
echo "Flash completed."
echo
echo "Next:"
echo "  Connect to SportsOS-Scoreboard-XXXXXX if provisioning mode appears."
EOF

chmod +x "$FLASH_SCRIPT"

cat >> "$README" <<'EOF'

## Milestone 12.2 — Flash packaging / ESP32 deployment

A successful PlatformIO build can now be packaged into a timestamped release under:

`firmware/esp32-scoreboard/releases/`

Each package contains:

- `firmware.bin`
- `firmware.elf` when available
- bootloader image when available
- partition table when available
- `boot_app0.bin` when available
- `SHA256SUMS.txt`
- `flash-layout.txt`

### Flash from Unraid without host PlatformIO

Connect the ESP32 USB serial device to the Unraid host and identify its device node.

Common examples:

- `/dev/ttyUSB0`
- `/dev/ttyACM0`

Then run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash firmware/esp32-scoreboard/flash-with-docker.sh /dev/ttyUSB0
```

The script uses the same Dockerized PlatformIO toolchain from Milestone 12.1.

Do not run the flash command until an actual ESP32 is connected and the correct serial device has been identified.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.2 ESP32 flash packaging", () => {
  it("defines a Docker-based flash workflow", () => {
    const script = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/flash-with-docker.sh",
        import.meta.url,
      ),
      "utf8",
    );

    expect(script).toContain(
      "--target upload",
    );

    expect(script).toContain(
      "--upload-port",
    );

    expect(script).toContain(
      "--device=",
    );
  });

  it("requires an explicit serial device", () => {
    const script = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/flash-with-docker.sh",
        import.meta.url,
      ),
      "utf8",
    );

    expect(script).toContain(
      "/dev/ttyUSB0",
    );

    expect(script).toContain(
      "serial device does not exist",
    );
  });

  it("documents the standard ESP32 flash offsets", () => {
    const manifest = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/FLASH-MANIFEST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(manifest).toContain(
      "0x1000",
    );

    expect(manifest).toContain(
      "0x8000",
    );

    expect(manifest).toContain(
      "0x10000",
    );
  });

  it("documents SHA-256 integrity checks", () => {
    const manifest = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/FLASH-MANIFEST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(manifest).toContain(
      "SHA256SUMS.txt",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 12.2 installed"
echo "============================================================"
echo
echo "Firmware package:"
echo "  $PACKAGE_DIR"
echo
echo "Included binaries:"
find "$PACKAGE_DIR" -maxdepth 1 -type f -printf "  %f\n" | sort
echo
echo "Added:"
echo "  - timestamped ESP32 release package"
echo "  - SHA-256 integrity file"
echo "  - flash layout manifest"
echo "  - Dockerized PlatformIO flash script"
echo "  - explicit serial-device requirement"
echo "  - Milestone 12.2 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run repository validation:"
echo "  npm run typecheck && npm test"
echo
echo "Do NOT flash until an ESP32 is connected."
echo
echo "When hardware is connected:"
echo "  ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || true"
echo
echo "Then, using the correct device:"
echo "  bash firmware/esp32-scoreboard/flash-with-docker.sh /dev/ttyUSB0"
echo
echo "Next:"
echo "  Milestone 12.3 - Device Enrollment / First-Boot Verification"
