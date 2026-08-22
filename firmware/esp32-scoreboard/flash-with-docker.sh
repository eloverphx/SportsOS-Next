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
