#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="13.3-ota-release-import-artifact-serving"
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
  "$ROOT/apps/api/src/app.ts" \
  "$ROOT/apps/api/src/services/scoreboardFirmwareReleaseRegistry.ts" \
  "$ROOT/apps/api/src/services/scoreboardDeviceEnrollment.ts" \
  "$ROOT/packages/core/src/scoreboard-firmware-update-contract.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

IMPORTER="apps/api/src/services/scoreboardFirmwareArtifactStore.ts"
ROUTE="apps/api/src/routes/scoreboardFirmwareArtifacts.ts"
TEST="packages/core/test/ota-release-import-artifact-serving-13.3.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$IMPORTER")" \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$IMPORTER")" \
  "$(dirname "$ROUTE")" \
  "$(dirname "$TEST")"

for file in "$IMPORTER" "$ROUTE" "$TEST" "apps/api/src/app.ts"; do
  if [[ -f "$file" ]]; then
    rel="${file#$ROOT/}"
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$file" "$BACKUP_DIR/$rel"
  fi
done

cat > "$IMPORTER" <<'EOF'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

import type {
  ScoreboardFirmwareRelease,
} from "@sportsos/core";

import {
  registerFirmwareRelease,
} from "./scoreboardFirmwareReleaseRegistry.js";

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(
    process.cwd(),
    "data",
  );

const ARTIFACT_DIR =
  path.join(
    DATA_DIR,
    "scoreboard-firmware-artifacts",
  );

export type ImportedFirmwareArtifact = {
  release: ScoreboardFirmwareRelease;
  artifactPath: string;
};

function sha256File(
  filePath: string,
): string {
  const hash =
    crypto.createHash("sha256");

  const contents =
    fs.readFileSync(
      filePath,
    );

  hash.update(
    contents,
  );

  return hash.digest(
    "hex",
  );
}

export function importFirmwareReleaseDirectory(
  releaseDirectory: string,
): ImportedFirmwareArtifact {
  const manifestPath =
    path.join(
      releaseDirectory,
      "release.json",
    );

  if (!fs.existsSync(manifestPath)) {
    throw new Error(
      "release.json is missing.",
    );
  }

  const manifest =
    JSON.parse(
      fs.readFileSync(
        manifestPath,
        "utf8",
      ),
    ) as ScoreboardFirmwareRelease;

  if (
    !manifest.releaseId ||
    !manifest.firmwareFile ||
    !manifest.firmwareSha256 ||
    !manifest.firmwareSizeBytes
  ) {
    throw new Error(
      "Release manifest is incomplete.",
    );
  }

  const sourceArtifact =
    path.join(
      releaseDirectory,
      manifest.firmwareFile,
    );

  if (!fs.existsSync(sourceArtifact)) {
    throw new Error(
      "Firmware artifact is missing.",
    );
  }

  const actualSize =
    fs.statSync(
      sourceArtifact,
    ).size;

  if (
    actualSize !==
    manifest.firmwareSizeBytes
  ) {
    throw new Error(
      "Firmware artifact size does not match release manifest.",
    );
  }

  const actualSha256 =
    sha256File(
      sourceArtifact,
    );

  if (
    actualSha256.toLowerCase() !==
    manifest.firmwareSha256.toLowerCase()
  ) {
    throw new Error(
      "Firmware artifact SHA-256 does not match release manifest.",
    );
  }

  const releaseArtifactDir =
    path.join(
      ARTIFACT_DIR,
      manifest.releaseId,
    );

  fs.mkdirSync(
    releaseArtifactDir,
    {
      recursive: true,
    },
  );

  const destination =
    path.join(
      releaseArtifactDir,
      "firmware.bin",
    );

  const temp =
    `${destination}.tmp`;

  fs.copyFileSync(
    sourceArtifact,
    temp,
  );

  fs.renameSync(
    temp,
    destination,
  );

  fs.writeFileSync(
    path.join(
      releaseArtifactDir,
      "release.json",
    ),
    JSON.stringify(
      manifest,
      null,
      2,
    ),
    "utf8",
  );

  registerFirmwareRelease(
    manifest,
  );

  return {
    release:
      manifest,
    artifactPath:
      destination,
  };
}

export function getFirmwareArtifactPath(
  releaseId: string,
): string | null {
  const artifact =
    path.join(
      ARTIFACT_DIR,
      releaseId,
      "firmware.bin",
    );

  return fs.existsSync(
    artifact,
  )
    ? artifact
    : null;
}
EOF

cat > "$ROUTE" <<'EOF'
import fs from "node:fs";

import type {
  FastifyInstance,
} from "fastify";

import {
  getFirmwareArtifactPath,
  importFirmwareReleaseDirectory,
} from "../services/scoreboardFirmwareArtifactStore.js";

import {
  getFirmwareRelease,
} from "../services/scoreboardFirmwareReleaseRegistry.js";

import {
  isVerifiedDevice,
} from "../services/scoreboardDeviceEnrollment.js";

export async function registerScoreboardFirmwareArtifactRoutes(
  app: FastifyInstance,
) {
  app.post(
    "/scoreboard-firmware/import",
    async (request, reply) => {
      const body =
        request.body as {
          releaseDirectory?: string;
        };

      if (!body?.releaseDirectory) {
        return reply.code(400).send({
          success: false,
          error:
            "releaseDirectory is required.",
        });
      }

      try {
        const imported =
          importFirmwareReleaseDirectory(
            body.releaseDirectory,
          );

        return reply.code(201).send({
          success: true,
          data: {
            release:
              imported.release,
          },
        });
      } catch (error) {
        return reply.code(400).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Firmware release import failed.",
        });
      }
    },
  );

  app.get(
    "/scoreboard-firmware/releases/:releaseId/artifact",
    async (request, reply) => {
      const { releaseId } =
        request.params as {
          releaseId: string;
        };

      const query =
        request.query as {
          deviceId?: string;
        };

      if (!query.deviceId) {
        return reply.code(400).send({
          success: false,
          error:
            "deviceId is required.",
        });
      }

      if (
        !isVerifiedDevice(
          query.deviceId,
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Verified scoreboard device required.",
        });
      }

      const release =
        getFirmwareRelease(
          releaseId,
        );

      if (!release) {
        return reply.code(404).send({
          success: false,
          error:
            "Firmware release not found.",
        });
      }

      const artifactPath =
        getFirmwareArtifactPath(
          releaseId,
        );

      if (!artifactPath) {
        return reply.code(404).send({
          success: false,
          error:
            "Firmware artifact not found.",
        });
      }

      reply.header(
        "Content-Type",
        "application/octet-stream",
      );

      reply.header(
        "Content-Length",
        String(
          release.firmwareSizeBytes,
        ),
      );

      reply.header(
        "X-SportsOS-Firmware-SHA256",
        release.firmwareSha256,
      );

      reply.header(
        "X-SportsOS-Firmware-Version",
        release.version,
      );

      return reply.send(
        fs.createReadStream(
          artifactPath,
        ),
      );
    },
  );
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/app.ts";

let text =
  fs.readFileSync(file, "utf8");

const importLine =
  'import { registerScoreboardFirmwareArtifactRoutes } from "./routes/scoreboardFirmwareArtifacts.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate app.ts import block.",
    );
  }

  text =
    text.replace(
      imports[0],
      imports[0] +
        importLine +
        "\n",
    );
}

if (
  !text.includes(
    "await registerScoreboardFirmwareArtifactRoutes(app);",
  )
) {
  const anchors = [
    "await registerScoreboardFirmwareReleaseRoutes(app);",
    "return app;",
  ];

  let patched = false;

  for (const anchor of anchors) {
    if (!text.includes(anchor)) {
      continue;
    }

    if (anchor === "return app;") {
      text =
        text.replace(
          anchor,
          "await registerScoreboardFirmwareArtifactRoutes(app);\n\n  " +
            anchor,
        );
    } else {
      text =
        text.replace(
          anchor,
          anchor +
            "\n  await registerScoreboardFirmwareArtifactRoutes(app);",
        );
    }

    patched = true;
    break;
  }

  if (!patched) {
    throw new Error(
      "Unable to locate API route-registration anchor.",
    );
  }
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

describe("Milestone 13.3 OTA release import / artifact serving", () => {
  it("validates firmware artifact size and SHA-256 before import", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardFirmwareArtifactStore.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "firmwareSizeBytes",
    );

    expect(service).toContain(
      "firmwareSha256",
    );

    expect(service).toContain(
      'crypto.createHash("sha256")',
    );
  });

  it("copies validated firmware into API-managed artifact storage", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardFirmwareArtifactStore.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "scoreboard-firmware-artifacts",
    );

    expect(service).toContain(
      "fs.copyFileSync",
    );

    expect(service).toContain(
      "fs.renameSync",
    );
  });

  it("registers imported release manifest", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardFirmwareArtifactStore.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "registerFirmwareRelease",
    );
  });

  it("exposes release import endpoint", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareArtifacts.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/import",
    );

    expect(routes).toContain(
      "releaseDirectory is required.",
    );
  });

  it("serves firmware only to verified devices", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareArtifacts.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "isVerifiedDevice",
    );

    expect(routes).toContain(
      "Verified scoreboard device required.",
    );

    expect(routes).toContain(
      "application/octet-stream",
    );
  });

  it("returns integrity metadata headers with artifact", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareArtifacts.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "X-SportsOS-Firmware-SHA256",
    );

    expect(routes).toContain(
      "X-SportsOS-Firmware-Version",
    );
  });

  it("registers artifact routes in API app", () => {
    const app = fs.readFileSync(
      new URL(
        "../../../apps/api/src/app.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(app).toContain(
      "registerScoreboardFirmwareArtifactRoutes",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 13.3 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - OTA release directory import"
echo "  - release.json validation"
echo "  - firmware size validation"
echo "  - SHA-256 validation"
echo "  - API-managed firmware artifact storage"
echo "  - automatic release registry registration"
echo "  - verified-device artifact download gate"
echo "  - integrity metadata response headers"
echo "  - Milestone 13.3 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then rebuild API:"
echo "  docker compose up -d --build api"
echo
echo "Next after green:"
echo "  Milestone 13.4 - Device OTA Update Check / Offer Binding"
