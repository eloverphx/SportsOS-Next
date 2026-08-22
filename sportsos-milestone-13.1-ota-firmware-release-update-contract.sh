#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="13.1-ota-firmware-release-update-contract"
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
  "$ROOT/firmware/esp32-scoreboard/.pio/build/esp32dev/firmware.bin" \
  "$ROOT/firmware/esp32-scoreboard/DEPLOYMENT-READINESS-CHECKLIST.md" \
  "$ROOT/apps/api/src/services/scoreboardDeviceEnrollment.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

CORE="$ROOT/packages/core/src/scoreboard-firmware-update-contract.ts"
CORE_INDEX="$ROOT/packages/core/src/index.ts"
FW_H="$ROOT/firmware/esp32-scoreboard/include/FirmwareUpdateContract.h"
FW_CPP="$ROOT/firmware/esp32-scoreboard/src/FirmwareUpdateContract.cpp"
RELEASE_SCRIPT="$ROOT/firmware/esp32-scoreboard/create-ota-release.sh"
README="$ROOT/firmware/esp32-scoreboard/README.md"
TEST="$ROOT/packages/core/test/ota-firmware-release-update-contract-13.1.test.ts"

mkdir -p \
  "$BACKUP_DIR/packages/core/src" \
  "$BACKUP_DIR/packages/core/test" \
  "$BACKUP_DIR/firmware/esp32-scoreboard/include" \
  "$BACKUP_DIR/firmware/esp32-scoreboard/src" \
  "$(dirname "$CORE")" \
  "$(dirname "$TEST")" \
  "$(dirname "$FW_H")" \
  "$(dirname "$FW_CPP")"

for file in "$CORE" "$CORE_INDEX" "$FW_H" "$FW_CPP" "$RELEASE_SCRIPT" "$README" "$TEST"; do
  if [[ -f "$file" ]]; then
    rel="${file#$ROOT/}"
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$file" "$BACKUP_DIR/$rel"
  fi
done

cat > "$CORE" <<'EOF'
export const SCOREBOARD_FIRMWARE_UPDATE_PROTOCOL_VERSION =
  1 as const;

export type FirmwareReleaseChannel =
  | "stable"
  | "beta"
  | "development";

export type FirmwareReleaseTarget =
  "esp32dev";

export type ScoreboardFirmwareRelease = {
  protocolVersion:
    typeof SCOREBOARD_FIRMWARE_UPDATE_PROTOCOL_VERSION;
  releaseId: string;
  version: string;
  channel: FirmwareReleaseChannel;
  target: FirmwareReleaseTarget;
  createdAt: string;
  firmwareFile: string;
  firmwareSha256: string;
  firmwareSizeBytes: number;
  minimumCurrentVersion: string | null;
  mandatory: boolean;
};

export type ScoreboardFirmwareUpdateOffer = {
  deviceId: string;
  currentVersion: string;
  release: ScoreboardFirmwareRelease;
};

export type ScoreboardFirmwareUpdateStatus =
  | "IDLE"
  | "AVAILABLE"
  | "DOWNLOADING"
  | "VERIFYING"
  | "READY_TO_INSTALL"
  | "INSTALLING"
  | "REBOOTING"
  | "SUCCEEDED"
  | "FAILED";

export type ScoreboardFirmwareUpdateReport = {
  deviceId: string;
  releaseId: string;
  previousVersion: string;
  targetVersion: string;
  status: ScoreboardFirmwareUpdateStatus;
  progressPercent: number | null;
  error: string | null;
  reportedAt: string;
};

export function isTerminalFirmwareUpdateStatus(
  status: ScoreboardFirmwareUpdateStatus,
): boolean {
  return (
    status === "SUCCEEDED" ||
    status === "FAILED"
  );
}
EOF

if ! grep -q 'scoreboard-firmware-update-contract.js' "$CORE_INDEX"; then
  printf '\nexport * from "./scoreboard-firmware-update-contract.js";\n' >> "$CORE_INDEX"
fi

cat > "$FW_H" <<'EOF'
#pragma once

#include <Arduino.h>

namespace sportsos {

constexpr uint8_t
FIRMWARE_UPDATE_PROTOCOL_VERSION = 1;

enum class FirmwareUpdateState : uint8_t {
  Idle = 0,
  Available,
  Downloading,
  Verifying,
  ReadyToInstall,
  Installing,
  Rebooting,
  Succeeded,
  Failed,
};

struct FirmwareUpdateOffer {
  char releaseId[64];
  char version[32];
  char firmwareUrl[256];
  char firmwareSha256[65];
  uint32_t firmwareSizeBytes;
  bool mandatory;
};

struct FirmwareUpdateProgress {
  FirmwareUpdateState state;
  uint8_t progressPercent;
  char error[128];
};

class FirmwareUpdateContract {
 public:
  static bool validateOffer(
      const FirmwareUpdateOffer& offer);

  static const char* stateText(
      FirmwareUpdateState state);
};

}  // namespace sportsos
EOF

cat > "$FW_CPP" <<'EOF'
#include "FirmwareUpdateContract.h"

#include <string.h>

namespace sportsos {

bool FirmwareUpdateContract::validateOffer(
    const FirmwareUpdateOffer& offer) {
  if (
      offer.releaseId[0] == '\0' ||
      offer.version[0] == '\0' ||
      offer.firmwareUrl[0] == '\0'
  ) {
    return false;
  }

  if (
      strlen(
          offer.firmwareSha256) != 64
  ) {
    return false;
  }

  if (
      offer.firmwareSizeBytes == 0
  ) {
    return false;
  }

  return true;
}

const char*
FirmwareUpdateContract::stateText(
    FirmwareUpdateState state) {
  switch (state) {
    case FirmwareUpdateState::Idle:
      return "IDLE";
    case FirmwareUpdateState::Available:
      return "AVAILABLE";
    case FirmwareUpdateState::Downloading:
      return "DOWNLOADING";
    case FirmwareUpdateState::Verifying:
      return "VERIFYING";
    case FirmwareUpdateState::ReadyToInstall:
      return "READY_TO_INSTALL";
    case FirmwareUpdateState::Installing:
      return "INSTALLING";
    case FirmwareUpdateState::Rebooting:
      return "REBOOTING";
    case FirmwareUpdateState::Succeeded:
      return "SUCCEEDED";
    case FirmwareUpdateState::Failed:
      return "FAILED";
    default:
      return "FAILED";
  }
}

}  // namespace sportsos
EOF

cat > "$RELEASE_SCRIPT" <<'EOF'
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
EOF

chmod +x "$RELEASE_SCRIPT"

cat >> "$README" <<'EOF'

## Milestone 13.1 — OTA firmware release / update contract

SportsOS now defines the shared contract for remotely managed scoreboard firmware updates.

Release channels:

- `stable`
- `beta`
- `development`

Firmware update states:

- `IDLE`
- `AVAILABLE`
- `DOWNLOADING`
- `VERIFYING`
- `READY_TO_INSTALL`
- `INSTALLING`
- `REBOOTING`
- `SUCCEEDED`
- `FAILED`

Every OTA release includes:

- release ID
- semantic firmware version
- target hardware profile
- release channel
- SHA-256 firmware digest
- firmware size
- mandatory/optional flag
- creation timestamp

Create a release from the currently compiled firmware with:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash firmware/esp32-scoreboard/create-ota-release.sh 0.13.1 stable false
```

Release bundles are written under:

`firmware/esp32-scoreboard/releases/ota/`

Milestone 13.1 defines the release/update contract only. It does not yet download or install firmware on devices.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  SCOREBOARD_FIRMWARE_UPDATE_PROTOCOL_VERSION,
  isTerminalFirmwareUpdateStatus,
} from "../src/scoreboard-firmware-update-contract.js";

describe("Milestone 13.1 OTA firmware release contract", () => {
  it("defines protocol version 1", () => {
    expect(
      SCOREBOARD_FIRMWARE_UPDATE_PROTOCOL_VERSION,
    ).toBe(1);
  });

  it("defines stable beta and development channels", () => {
    const source = fs.readFileSync(
      new URL(
        "../src/scoreboard-firmware-update-contract.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain('"stable"');
    expect(source).toContain('"beta"');
    expect(source).toContain('"development"');
  });

  it("defines the complete update lifecycle", () => {
    const source = fs.readFileSync(
      new URL(
        "../src/scoreboard-firmware-update-contract.ts",
        import.meta.url,
      ),
      "utf8",
    );

    for (const state of [
      "IDLE",
      "AVAILABLE",
      "DOWNLOADING",
      "VERIFYING",
      "READY_TO_INSTALL",
      "INSTALLING",
      "REBOOTING",
      "SUCCEEDED",
      "FAILED",
    ]) {
      expect(source).toContain(state);
    }
  });

  it("treats succeeded and failed as terminal states", () => {
    expect(
      isTerminalFirmwareUpdateStatus(
        "SUCCEEDED",
      ),
    ).toBe(true);

    expect(
      isTerminalFirmwareUpdateStatus(
        "FAILED",
      ),
    ).toBe(true);

    expect(
      isTerminalFirmwareUpdateStatus(
        "INSTALLING",
      ),
    ).toBe(false);
  });

  it("requires SHA-256 validation in firmware contract", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareUpdateContract.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "offer.firmwareSha256",
    );

    expect(source).toContain(
      "!= 64",
    );
  });

  it("adds a release packaging script", () => {
    const releaseScript = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/create-ota-release.sh",
        import.meta.url,
      ),
      "utf8",
    );

    expect(releaseScript).toContain(
      "release.json",
    );

    expect(releaseScript).toContain(
      "sha256sum",
    );

    expect(releaseScript).toContain(
      "releases/ota",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 13.1 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - shared OTA firmware update contract"
echo "  - stable / beta / development channels"
echo "  - complete update lifecycle states"
echo "  - ESP32-side update offer contract"
echo "  - SHA-256 + size validation requirements"
echo "  - reproducible OTA release packaging script"
echo "  - Milestone 13.1 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run repository validation:"
echo "  npm run typecheck && npm test"
echo
echo "Then create the first OTA release:"
echo "  bash firmware/esp32-scoreboard/create-ota-release.sh 0.13.1 stable false"
echo
echo "Next after green:"
echo "  Milestone 13.2 - Firmware Release Registry / API"
