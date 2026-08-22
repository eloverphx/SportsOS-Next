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
  echo "Expected: $EXPECTED_REAL" >&2
  echo "Received: $ROOT_REAL" >&2
  exit 1
fi

cd "$ROOT"

FW_DIR="firmware/esp32-scoreboard"
IMAGE="sportsos-platformio:12.1"

echo "============================================================"
echo " SportsOS ESP32 containerized firmware build"
echo "============================================================"
echo
echo "Building PlatformIO toolchain image..."
docker build \
  -f "$FW_DIR/Dockerfile.platformio" \
  -t "$IMAGE" \
  "$FW_DIR"

echo
echo "Compiling firmware..."
docker run --rm \
  -v "$ROOT/$FW_DIR:/workspace" \
  -v sportsos_platformio_core:/platformio \
  -w /workspace \
  "$IMAGE" \
  run

echo
echo "Firmware build completed."
echo
echo "Expected artifacts:"
echo "  $FW_DIR/.pio/build/esp32dev/firmware.bin"
echo "  $FW_DIR/.pio/build/esp32dev/firmware.elf"
