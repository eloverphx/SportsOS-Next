#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="12.1-containerized-esp32-firmware-build-toolchain"
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
  "$ROOT/firmware/esp32-scoreboard/src/main.cpp"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

command -v docker >/dev/null 2>&1 || {
  echo "ERROR: docker is required for Milestone 12.1." >&2
  exit 1
}

cd "$ROOT"

FW_DIR="firmware/esp32-scoreboard"
DOCKERFILE="$FW_DIR/Dockerfile.platformio"
BUILD_SCRIPT="$FW_DIR/build-in-docker.sh"
README="$FW_DIR/README.md"
TEST="packages/core/test/containerized-platformio-build-12.1.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$DOCKERFILE")" \
  "$BACKUP_DIR/$(dirname "$BUILD_SCRIPT")" \
  "$BACKUP_DIR/$(dirname "$README")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$DOCKERFILE")" \
  "$(dirname "$BUILD_SCRIPT")" \
  "$(dirname "$TEST")"

for file in "$DOCKERFILE" "$BUILD_SCRIPT" "$README" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$DOCKERFILE" <<'EOF'
FROM python:3.12-slim

ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PLATFORMIO_CORE_DIR=/platformio

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      git \
      build-essential \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir platformio

WORKDIR /workspace

ENTRYPOINT ["platformio"]
EOF

cat > "$BUILD_SCRIPT" <<'EOF'
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
EOF

chmod +x "$BUILD_SCRIPT"

cat >> "$README" <<'EOF'

## Milestone 12.1 — Containerized PlatformIO build toolchain

PlatformIO no longer needs to be installed directly on the Unraid host.

Run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash firmware/esp32-scoreboard/build-in-docker.sh
```

The script:

1. builds a small local Docker image containing PlatformIO
2. mounts the firmware directory into the container
3. persists PlatformIO toolchain/cache data in the Docker volume `sportsos_platformio_core`
4. compiles the `esp32dev` firmware target
5. leaves build artifacts in `firmware/esp32-scoreboard/.pio/build/esp32dev`

Expected firmware binary:

`firmware/esp32-scoreboard/.pio/build/esp32dev/firmware.bin`

This approach keeps the Unraid host clean and makes the firmware build reproducible.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.1 containerized PlatformIO toolchain", () => {
  it("defines a reproducible PlatformIO Docker image", () => {
    const dockerfile = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/Dockerfile.platformio",
        import.meta.url,
      ),
      "utf8",
    );

    expect(dockerfile).toContain(
      "pip install --no-cache-dir platformio",
    );

    expect(dockerfile).toContain(
      'ENTRYPOINT ["platformio"]',
    );
  });

  it("builds firmware without host PlatformIO", () => {
    const script = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/build-in-docker.sh",
        import.meta.url,
      ),
      "utf8",
    );

    expect(script).toContain(
      "docker build",
    );

    expect(script).toContain(
      "docker run --rm",
    );

    expect(script).toContain(
      "sportsos_platformio_core",
    );
  });

  it("retains the canonical-root safety guard", () => {
    const script = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/build-in-docker.sh",
        import.meta.url,
      ),
      "utf8",
    );

    expect(script).toContain(
      "/mnt/user/appdata/SportsOS-Next",
    );

    expect(script).toContain(
      "refusing to run outside canonical SportsOS-Next root",
    );
  });

  it("documents the compiled firmware binary path", () => {
    const readme = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/README.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(readme).toContain(
      ".pio/build/esp32dev/firmware.bin",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 12.1 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - Dockerized PlatformIO toolchain"
echo "  - reproducible ESP32 firmware build"
echo "  - persistent PlatformIO Docker cache"
echo "  - no host PlatformIO installation required"
echo "  - firmware.bin / firmware.elf artifact path"
echo "  - Milestone 12.1 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run repository validation:"
echo "  npm run typecheck && npm test"
echo
echo "Then compile actual ESP32 firmware:"
echo "  bash firmware/esp32-scoreboard/build-in-docker.sh"
echo
echo "Next after green build:"
echo "  Milestone 12.2 - Firmware Compile Repair / Flash Packaging"
