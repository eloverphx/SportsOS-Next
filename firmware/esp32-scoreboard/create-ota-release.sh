#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" || "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  exit 1
fi

VERSION="${1:-}"
CHANNEL="${2:-stable}"
MANDATORY="${3:-false}"

if [[ -z "$VERSION" ]]; then
  echo "Usage:"
  echo "  bash firmware/esp32-scoreboard/create-ota-release.sh VERSION [stable|beta|development] [true|false]"
  exit 1
fi

case "$CHANNEL" in
  stable|beta|development) ;;
  *)
    echo "ERROR: invalid channel: $CHANNEL" >&2
    exit 1
    ;;
esac

case "$MANDATORY" in
  true|false) ;;
  *)
    echo "ERROR: mandatory must be true or false." >&2
    exit 1
    ;;
esac

FW_DIR="$ROOT/firmware/esp32-scoreboard"
SOURCE="$FW_DIR/.pio/build/esp32dev/firmware.bin"

if [[ ! -f "$SOURCE" ]]; then
  echo "ERROR: compiled firmware missing: $SOURCE" >&2
  exit 1
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RELEASE_ID="esp32dev-${VERSION}-${STAMP}"
OUT="$FW_DIR/releases/ota/$RELEASE_ID"

mkdir -p "$OUT"

cp -a "$SOURCE" "$OUT/firmware.bin"

SHA256="$(sha256sum "$OUT/firmware.bin" | awk '{print $1}')"
SIZE="$(stat -c '%s' "$OUT/firmware.bin")"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$OUT/release.json" <<JSON
{
  "protocolVersion": 1,
  "releaseId": "$RELEASE_ID",
  "version": "$VERSION",
  "channel": "$CHANNEL",
  "target": "esp32dev",
  "createdAt": "$CREATED_AT",
  "firmwareFile": "firmware.bin",
  "firmwareSha256": "$SHA256",
  "firmwareSizeBytes": $SIZE,
  "minimumCurrentVersion": null,
  "mandatory": $MANDATORY
}
JSON

sha256sum \
  "$OUT/firmware.bin" \
  "$OUT/release.json" \
  > "$OUT/SHA256SUMS.txt"

echo "============================================================"
echo " SportsOS OTA firmware release created"
echo "============================================================"
echo
echo "Release:"
echo "  $OUT"
echo
echo "Release ID:"
echo "  $RELEASE_ID"
echo
echo "Firmware SHA-256:"
echo "  $SHA256"
echo
echo "Firmware size:"
echo "  $SIZE bytes"
