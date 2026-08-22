#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="13.5-esp32-ota-download-integrity-verification"
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
  "$ROOT/firmware/esp32-scoreboard/include/FirmwareUpdateClient.h" \
  "$ROOT/firmware/esp32-scoreboard/include/FirmwareUpdateContract.h" \
  "$ROOT/firmware/esp32-scoreboard/src/FirmwareUpdateClient.cpp" \
  "$ROOT/firmware/esp32-scoreboard/src/main.cpp" \
  "$ROOT/firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

DL_H="firmware/esp32-scoreboard/include/FirmwareUpdateDownloader.h"
DL_CPP="firmware/esp32-scoreboard/src/FirmwareUpdateDownloader.cpp"
CLIENT_H="firmware/esp32-scoreboard/include/FirmwareUpdateClient.h"
CLIENT_CPP="firmware/esp32-scoreboard/src/FirmwareUpdateClient.cpp"
SIM="firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js"
SIM_TEST="firmware/esp32-scoreboard/simulator/test/ota-download-integrity.test.js"
README="firmware/esp32-scoreboard/README.md"
TEST="packages/core/test/esp32-ota-download-integrity-verification-13.5.test.ts"

for file in "$DL_H" "$DL_CPP" "$CLIENT_H" "$CLIENT_CPP" "$SIM" "$SIM_TEST" "$README" "$TEST"; do
  if [[ -f "$file" ]]; then
    rel="${file#$ROOT/}"
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$file" "$BACKUP_DIR/$rel"
  fi
done

mkdir -p \
  "$(dirname "$DL_H")" \
  "$(dirname "$DL_CPP")" \
  "$(dirname "$SIM_TEST")" \
  "$(dirname "$TEST")"

cat > "$DL_H" <<'EOF'
#pragma once

#include <Arduino.h>

#include "FirmwareUpdateContract.h"

namespace sportsos {

enum class FirmwareDownloadResult : uint8_t {
  Success = 0,
  TransportError,
  HttpError,
  SizeMismatch,
  WriteError,
  Sha256Mismatch,
  FinalizeError,
};

struct FirmwareDownloadProgress {
  FirmwareUpdateState state;
  uint32_t bytesReceived;
  uint32_t totalBytes;
  uint8_t progressPercent;
  FirmwareDownloadResult result;
};

class FirmwareUpdateDownloader {
 public:
  FirmwareUpdateDownloader();

  FirmwareDownloadResult downloadAndStage(
      const char* apiBaseUrl,
      const FirmwareUpdateOffer& offer);

  const FirmwareDownloadProgress& progress() const;

 private:
  FirmwareDownloadProgress progress_;

  void resetProgress(
      uint32_t expectedSize);

  static String absoluteUrl(
      const char* apiBaseUrl,
      const char* firmwareUrl);

  static String bytesToHex(
      const uint8_t* bytes,
      size_t length);
};

}  // namespace sportsos
EOF

cat > "$DL_CPP" <<'EOF'
#include "FirmwareUpdateDownloader.h"

#include <HTTPClient.h>
#include <Update.h>
#include <WiFiClient.h>
#include <mbedtls/sha256.h>

namespace sportsos {

FirmwareUpdateDownloader::FirmwareUpdateDownloader() {
  resetProgress(0);
}

FirmwareDownloadResult
FirmwareUpdateDownloader::downloadAndStage(
    const char* apiBaseUrl,
    const FirmwareUpdateOffer& offer) {
  resetProgress(
      offer.firmwareSizeBytes);

  if (
      !FirmwareUpdateContract::validateOffer(
          offer)
  ) {
    progress_.state =
        FirmwareUpdateState::Failed;
    progress_.result =
        FirmwareDownloadResult::SizeMismatch;

    return progress_.result;
  }

  HTTPClient http;

  const String url =
      absoluteUrl(
          apiBaseUrl,
          offer.firmwareUrl);

  if (!http.begin(url)) {
    progress_.state =
        FirmwareUpdateState::Failed;
    progress_.result =
        FirmwareDownloadResult::TransportError;

    return progress_.result;
  }

  const int status =
      http.GET();

  if (
      status < 200 ||
      status >= 300
  ) {
    http.end();

    progress_.state =
        FirmwareUpdateState::Failed;
    progress_.result =
        FirmwareDownloadResult::HttpError;

    return progress_.result;
  }

  const int contentLength =
      http.getSize();

  if (
      contentLength > 0 &&
      static_cast<uint32_t>(
          contentLength) !=
          offer.firmwareSizeBytes
  ) {
    http.end();

    progress_.state =
        FirmwareUpdateState::Failed;
    progress_.result =
        FirmwareDownloadResult::SizeMismatch;

    return progress_.result;
  }

  if (
      !Update.begin(
          offer.firmwareSizeBytes)
  ) {
    http.end();

    progress_.state =
        FirmwareUpdateState::Failed;
    progress_.result =
        FirmwareDownloadResult::WriteError;

    return progress_.result;
  }

  progress_.state =
      FirmwareUpdateState::Downloading;

  WiFiClient* stream =
      http.getStreamPtr();

  mbedtls_sha256_context
      sha256;

  mbedtls_sha256_init(
      &sha256);

  mbedtls_sha256_starts_ret(
      &sha256,
      0);

  uint8_t buffer[1024];

  while (
      http.connected() &&
      progress_.bytesReceived <
          offer.firmwareSizeBytes
  ) {
    const size_t available =
        stream->available();

    if (available == 0) {
      delay(1);
      continue;
    }

    const size_t remaining =
        offer.firmwareSizeBytes -
        progress_.bytesReceived;

    const size_t toRead =
        min(
            sizeof(buffer),
            min(
                available,
                remaining));

    const int read =
        stream->readBytes(
            buffer,
            toRead);

    if (read <= 0) {
      Update.abort();
      http.end();
      mbedtls_sha256_free(
          &sha256);

      progress_.state =
          FirmwareUpdateState::Failed;
      progress_.result =
          FirmwareDownloadResult::TransportError;

      return progress_.result;
    }

    mbedtls_sha256_update_ret(
        &sha256,
        buffer,
        static_cast<size_t>(
            read));

    const size_t written =
        Update.write(
            buffer,
            static_cast<size_t>(
                read));

    if (
        written !=
        static_cast<size_t>(
            read)
    ) {
      Update.abort();
      http.end();
      mbedtls_sha256_free(
          &sha256);

      progress_.state =
          FirmwareUpdateState::Failed;
      progress_.result =
          FirmwareDownloadResult::WriteError;

      return progress_.result;
    }

    progress_.bytesReceived +=
        static_cast<uint32_t>(
            read);

    progress_.progressPercent =
        static_cast<uint8_t>(
            (
                progress_.bytesReceived *
                100ULL
            ) /
            offer.firmwareSizeBytes);
  }

  http.end();

  if (
      progress_.bytesReceived !=
      offer.firmwareSizeBytes
  ) {
    Update.abort();
    mbedtls_sha256_free(
        &sha256);

    progress_.state =
        FirmwareUpdateState::Failed;
    progress_.result =
        FirmwareDownloadResult::SizeMismatch;

    return progress_.result;
  }

  progress_.state =
      FirmwareUpdateState::Verifying;

  uint8_t digest[32];

  mbedtls_sha256_finish_ret(
      &sha256,
      digest);

  mbedtls_sha256_free(
      &sha256);

  const String actualSha256 =
      bytesToHex(
          digest,
          sizeof(digest));

  if (
      !actualSha256.equalsIgnoreCase(
          offer.firmwareSha256)
  ) {
    Update.abort();

    progress_.state =
        FirmwareUpdateState::Failed;
    progress_.result =
        FirmwareDownloadResult::Sha256Mismatch;

    return progress_.result;
  }

  progress_.state =
      FirmwareUpdateState::ReadyToInstall;

  /*
   * Update.end(true) is deliberately the final operation.
   * The OTA partition is not finalized/selected until after both
   * byte-count and SHA-256 verification succeed.
   */
  if (!Update.end(true)) {
    Update.abort();

    progress_.state =
        FirmwareUpdateState::Failed;
    progress_.result =
        FirmwareDownloadResult::FinalizeError;

    return progress_.result;
  }

  progress_.progressPercent =
      100;
  progress_.result =
      FirmwareDownloadResult::Success;

  return progress_.result;
}

const FirmwareDownloadProgress&
FirmwareUpdateDownloader::progress() const {
  return progress_;
}

void FirmwareUpdateDownloader::resetProgress(
    uint32_t expectedSize) {
  progress_ = {
      FirmwareUpdateState::Idle,
      0,
      expectedSize,
      0,
      FirmwareDownloadResult::Success,
  };
}

String FirmwareUpdateDownloader::absoluteUrl(
    const char* apiBaseUrl,
    const char* firmwareUrl) {
  const String candidate =
      firmwareUrl;

  if (
      candidate.startsWith(
          "http://") ||
      candidate.startsWith(
          "https://")
  ) {
    return candidate;
  }

  String base =
      apiBaseUrl;

  if (
      base.endsWith("/") &&
      candidate.startsWith("/")
  ) {
    base.remove(
        base.length() - 1);
  } else if (
      !base.endsWith("/") &&
      !candidate.startsWith("/")
  ) {
    base += "/";
  }

  return
      base +
      candidate;
}

String FirmwareUpdateDownloader::bytesToHex(
    const uint8_t* bytes,
    size_t length) {
  static const char* HEX =
      "0123456789abcdef";

  String result;

  result.reserve(
      length * 2);

  for (
      size_t index = 0;
      index < length;
      index += 1
  ) {
    result +=
        HEX[
            (
                bytes[index] >>
                4
            ) &
            0x0F];

    result +=
        HEX[
            bytes[index] &
            0x0F];
  }

  return result;
}

}  // namespace sportsos
EOF

node <<'NODE'
const fs = require("fs");

const headerFile =
  "firmware/esp32-scoreboard/include/FirmwareUpdateClient.h";

let header =
  fs.readFileSync(
    headerFile,
    "utf8",
  );

if (
  !header.includes(
    '#include "FirmwareUpdateDownloader.h"',
  )
) {
  header =
    header.replace(
      '#include "FirmwareUpdateContract.h"',
      '#include "FirmwareUpdateContract.h"\n#include "FirmwareUpdateDownloader.h"',
    );
}

if (
  !header.includes(
    "stageAvailableUpdate()",
  )
) {
  header =
    header.replace(
`  const FirmwareUpdateOffer& offer() const;`,
`  const FirmwareUpdateOffer& offer() const;

  FirmwareDownloadResult stageAvailableUpdate();

  const FirmwareDownloadProgress&
  downloadProgress() const;`,
    );
}

if (
  !header.includes(
    "FirmwareUpdateDownloader downloader_;",
  )
) {
  header =
    header.replace(
`  FirmwareUpdateOffer offer_;
  unsigned long lastCheckMs_;`,
`  FirmwareUpdateOffer offer_;
  unsigned long lastCheckMs_;
  FirmwareUpdateDownloader downloader_;`,
    );
}

fs.writeFileSync(
  headerFile,
  header,
);

const sourceFile =
  "firmware/esp32-scoreboard/src/FirmwareUpdateClient.cpp";

let source =
  fs.readFileSync(
    sourceFile,
    "utf8",
  );

if (
  !source.includes(
    "FirmwareUpdateClient::stageAvailableUpdate",
  )
) {
  const anchor =
`const FirmwareUpdateOffer&
FirmwareUpdateClient::offer() const {
  return offer_;
}`;

  if (!source.includes(anchor)) {
    throw new Error(
      "Unable to locate FirmwareUpdateClient::offer implementation.",
    );
  }

  source =
    source.replace(
      anchor,
`${anchor}

FirmwareDownloadResult
FirmwareUpdateClient::stageAvailableUpdate() {
  if (!updateAvailable()) {
    return
        FirmwareDownloadResult::TransportError;
  }

  return
      downloader_.downloadAndStage(
          config_.apiBaseUrl,
          offer_);
}

const FirmwareDownloadProgress&
FirmwareUpdateClient::downloadProgress() const {
  return downloader_.progress();
}`,
    );
}

fs.writeFileSync(
  sourceFile,
  source,
);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js";

let text =
  fs.readFileSync(file, "utf8");

if (
  !text.includes(
    "function verifyFirmwareDownload",
  )
) {
  const anchor =
    "module.exports = {";

  if (!text.includes(anchor)) {
    throw new Error(
      "Simulator export anchor missing.",
    );
  }

  const helper = `
function verifyFirmwareDownload({
  expectedSize,
  actualSize,
  expectedSha256,
  actualSha256,
}) {
  if (
    !Number.isFinite(expectedSize) ||
    expectedSize <= 0 ||
    actualSize !== expectedSize
  ) {
    return {
      ok: false,
      state: "FAILED",
      reason: "SIZE_MISMATCH",
    };
  }

  if (
    typeof expectedSha256 !== "string" ||
    expectedSha256.length !== 64 ||
    typeof actualSha256 !== "string" ||
    actualSha256.toLowerCase() !==
      expectedSha256.toLowerCase()
  ) {
    return {
      ok: false,
      state: "FAILED",
      reason: "SHA256_MISMATCH",
    };
  }

  return {
    ok: true,
    state: "READY_TO_INSTALL",
    reason: null,
  };
}

`;

  text =
    text.replace(
      anchor,
      helper +
        anchor,
    );

  const exportEnd =
    text.lastIndexOf("};");

  if (exportEnd === -1) {
    throw new Error(
      "Simulator export object end missing.",
    );
  }

  const before =
    text.slice(0, exportEnd);

  const after =
    text.slice(exportEnd);

  if (
    !before.includes(
      "verifyFirmwareDownload,",
    )
  ) {
    text =
      before.replace(
        /(\n\s*)$/,
        "$1  verifyFirmwareDownload,\n",
      ) +
      after;
  }
}

fs.writeFileSync(file, text);
NODE

cat > "$SIM_TEST" <<'EOF'
"use strict";

const test =
  require("node:test");

const assert =
  require("node:assert/strict");

const {
  verifyFirmwareDownload,
} = require(
  "../firmware-behavior-simulator.js",
);

const SHA =
  "a".repeat(64);

test(
  "13.5 accepts matching firmware size and SHA-256",
  () => {
    const result =
      verifyFirmwareDownload({
        expectedSize: 1000,
        actualSize: 1000,
        expectedSha256: SHA,
        actualSha256: SHA,
      });

    assert.equal(
      result.ok,
      true,
    );

    assert.equal(
      result.state,
      "READY_TO_INSTALL",
    );
  },
);

test(
  "13.5 rejects incomplete firmware download",
  () => {
    const result =
      verifyFirmwareDownload({
        expectedSize: 1000,
        actualSize: 999,
        expectedSha256: SHA,
        actualSha256: SHA,
      });

    assert.equal(
      result.ok,
      false,
    );

    assert.equal(
      result.reason,
      "SIZE_MISMATCH",
    );
  },
);

test(
  "13.5 rejects firmware with invalid SHA-256",
  () => {
    const result =
      verifyFirmwareDownload({
        expectedSize: 1000,
        actualSize: 1000,
        expectedSha256: SHA,
        actualSha256:
          "b".repeat(64),
      });

    assert.equal(
      result.ok,
      false,
    );

    assert.equal(
      result.reason,
      "SHA256_MISMATCH",
    );
  },
);
EOF

cat >> "$README" <<'EOF'

## Milestone 13.5 — ESP32 OTA download / integrity verification

The ESP32 can now stage an offered firmware release into the OTA update partition.

The staging flow is:

1. download the device-bound artifact URL
2. verify HTTP success
3. verify declared byte count
4. stream bytes into the inactive OTA partition
5. calculate SHA-256 while streaming
6. verify the final byte count
7. verify SHA-256 against the release manifest
8. finalize the OTA partition only after integrity validation succeeds

If byte count or SHA-256 verification fails, the update is aborted and the OTA partition is not finalized for boot.

The firmware is **not rebooted automatically in Milestone 13.5**. Reboot/install policy is added in the next milestone.

`FirmwareUpdateClient::stageAvailableUpdate()` exposes staging to the runtime while keeping update discovery and binary transfer as separate operations.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.5 ESP32 OTA download / integrity verification", () => {
  it("defines a firmware update downloader", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/FirmwareUpdateDownloader.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "FirmwareUpdateDownloader",
    );

    expect(header).toContain(
      "FirmwareDownloadResult",
    );
  });

  it("streams firmware into the ESP32 Update partition", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareUpdateDownloader.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "Update.begin",
    );

    expect(source).toContain(
      "Update.write",
    );

    expect(source).toContain(
      "Update.abort",
    );
  });

  it("calculates SHA-256 while downloading", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareUpdateDownloader.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "mbedtls_sha256_update_ret",
    );

    expect(source).toContain(
      "mbedtls_sha256_finish_ret",
    );

    expect(source).toContain(
      "equalsIgnoreCase",
    );
  });

  it("verifies total firmware size", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareUpdateDownloader.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "offer.firmwareSizeBytes",
    );

    expect(source).toContain(
      "SizeMismatch",
    );
  });

  it("finalizes the OTA partition only after SHA verification", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareUpdateDownloader.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    const shaCheck =
      source.indexOf(
        "equalsIgnoreCase",
      );

    const finalize =
      source.indexOf(
        "Update.end(true)",
      );

    expect(shaCheck).toBeGreaterThan(
      -1,
    );

    expect(finalize).toBeGreaterThan(
      shaCheck,
    );
  });

  it("exposes staging through FirmwareUpdateClient", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/FirmwareUpdateClient.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "stageAvailableUpdate",
    );

    expect(source).toContain(
      "downloadAndStage",
    );
  });

  it("adds host simulator download-integrity behavior", () => {
    const simulator = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js",
        import.meta.url,
      ),
      "utf8",
    );

    expect(simulator).toContain(
      "verifyFirmwareDownload",
    );

    expect(simulator).toContain(
      "SHA256_MISMATCH",
    );

    expect(simulator).toContain(
      "READY_TO_INSTALL",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 13.5 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - ESP32 OTA binary downloader"
echo "  - streaming OTA partition writes"
echo "  - HTTP / byte-count validation"
echo "  - streaming SHA-256 calculation"
echo "  - SHA-256 manifest verification"
echo "  - abort-on-integrity-failure behavior"
echo "  - OTA finalization only after successful validation"
echo "  - FirmwareUpdateClient staging API"
echo "  - host simulator integrity coverage"
echo "  - Milestone 13.5 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then firmware simulator:"
echo "  node --test firmware/esp32-scoreboard/simulator/test/*.test.js"
echo
echo "Then verify real firmware compile:"
echo "  bash firmware/esp32-scoreboard/build-in-docker.sh"
echo
echo "Next after green:"
echo "  Milestone 13.6 - Controlled OTA Install / Reboot / Recovery Policy"
