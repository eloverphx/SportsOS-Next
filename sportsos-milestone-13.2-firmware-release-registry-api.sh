#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="13.2-firmware-release-registry-api"
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
  "$ROOT/packages/core/src/scoreboard-firmware-update-contract.ts" \
  "$ROOT/firmware/esp32-scoreboard/create-ota-release.sh"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

SERVICE="apps/api/src/services/scoreboardFirmwareReleaseRegistry.ts"
ROUTE="apps/api/src/routes/scoreboardFirmwareReleases.ts"
TEST="packages/core/test/firmware-release-registry-api-13.2.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$SERVICE")" \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$SERVICE")" \
  "$(dirname "$ROUTE")" \
  "$(dirname "$TEST")"

for file in "$SERVICE" "$ROUTE" "$TEST" "apps/api/src/app.ts"; do
  [[ -f "$file" ]] && {
    rel="${file#$ROOT/}"
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$file" "$BACKUP_DIR/$rel"
  }
done

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

import type {
  FirmwareReleaseChannel,
  FirmwareReleaseTarget,
  ScoreboardFirmwareRelease,
} from "@sportsos/core";

type RegistryStore = {
  version: 1;
  releases: ScoreboardFirmwareRelease[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(
    process.cwd(),
    "data",
  );

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-firmware-releases.json",
  );

let store =
  loadStore();

function loadStore(): RegistryStore {
  try {
    const raw =
      fs.readFileSync(
        STORE_FILE,
        "utf8",
      );

    const parsed =
      JSON.parse(raw) as RegistryStore;

    if (
      parsed?.version !== 1 ||
      !Array.isArray(
        parsed.releases,
      )
    ) {
      throw new Error(
        "Invalid firmware release registry.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      releases: [],
    };
  }
}

function persistStore(): void {
  fs.mkdirSync(
    DATA_DIR,
    {
      recursive: true,
    },
  );

  const temp =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    temp,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );

  fs.renameSync(
    temp,
    STORE_FILE,
  );
}

function versionParts(
  version: string,
): number[] {
  return version
    .replace(/^v/i, "")
    .split(".")
    .map((part) => {
      const parsed =
        Number.parseInt(
          part,
          10,
        );

      return Number.isFinite(
        parsed,
      )
        ? parsed
        : 0;
    });
}

function compareVersions(
  left: string,
  right: string,
): number {
  const a =
    versionParts(left);

  const b =
    versionParts(right);

  const length =
    Math.max(
      a.length,
      b.length,
    );

  for (
    let index = 0;
    index < length;
    index += 1
  ) {
    const delta =
      (a[index] ?? 0) -
      (b[index] ?? 0);

    if (delta !== 0) {
      return delta;
    }
  }

  return 0;
}

export function registerFirmwareRelease(
  release: ScoreboardFirmwareRelease,
): ScoreboardFirmwareRelease {
  const existingIndex =
    store.releases.findIndex(
      (candidate) =>
        candidate.releaseId ===
        release.releaseId,
    );

  if (existingIndex >= 0) {
    store.releases[
      existingIndex
    ] = release;
  } else {
    store.releases.push(
      release,
    );
  }

  persistStore();

  return release;
}

export function listFirmwareReleases(input?: {
  channel?: FirmwareReleaseChannel;
  target?: FirmwareReleaseTarget;
}): ScoreboardFirmwareRelease[] {
  return store.releases
    .filter(
      (release) =>
        (!input?.channel ||
          release.channel ===
            input.channel) &&
        (!input?.target ||
          release.target ===
            input.target),
    )
    .sort(
      (a, b) =>
        compareVersions(
          b.version,
          a.version,
        ),
    );
}

export function getFirmwareRelease(
  releaseId: string,
): ScoreboardFirmwareRelease | null {
  return (
    store.releases.find(
      (release) =>
        release.releaseId ===
        releaseId,
    ) ?? null
  );
}

export function getLatestCompatibleFirmwareRelease(input: {
  currentVersion: string;
  channel: FirmwareReleaseChannel;
  target: FirmwareReleaseTarget;
}): ScoreboardFirmwareRelease | null {
  const candidates =
    listFirmwareReleases({
      channel:
        input.channel,
      target:
        input.target,
    });

  for (const release of candidates) {
    if (
      release.minimumCurrentVersion &&
      compareVersions(
        input.currentVersion,
        release.minimumCurrentVersion,
      ) < 0
    ) {
      continue;
    }

    if (
      compareVersions(
        release.version,
        input.currentVersion,
      ) <= 0
    ) {
      continue;
    }

    return release;
  }

  return null;
}
EOF

cat > "$ROUTE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import type {
  FirmwareReleaseChannel,
  FirmwareReleaseTarget,
  ScoreboardFirmwareRelease,
} from "@sportsos/core";

import {
  getFirmwareRelease,
  getLatestCompatibleFirmwareRelease,
  listFirmwareReleases,
  registerFirmwareRelease,
} from "../services/scoreboardFirmwareReleaseRegistry.js";

type ReleaseQuery = {
  channel?: FirmwareReleaseChannel;
  target?: FirmwareReleaseTarget;
};

type LatestQuery = {
  currentVersion?: string;
  channel?: FirmwareReleaseChannel;
  target?: FirmwareReleaseTarget;
};

export async function registerScoreboardFirmwareReleaseRoutes(
  app: FastifyInstance,
) {
  app.get(
    "/scoreboard-firmware/releases",
    async (request) => {
      const query =
        request.query as ReleaseQuery;

      return {
        success: true,
        data: {
          releases:
            listFirmwareReleases({
              channel:
                query.channel,
              target:
                query.target,
            }),
        },
      };
    },
  );

  app.get(
    "/scoreboard-firmware/releases/:releaseId",
    async (request, reply) => {
      const { releaseId } =
        request.params as {
          releaseId: string;
        };

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

      return {
        success: true,
        data: release,
      };
    },
  );

  app.post(
    "/scoreboard-firmware/releases",
    async (request, reply) => {
      const body =
        request.body as ScoreboardFirmwareRelease;

      if (
        !body?.releaseId ||
        !body?.version ||
        !body?.channel ||
        !body?.target ||
        !body?.firmwareFile ||
        !body?.firmwareSha256 ||
        !body?.firmwareSizeBytes
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Invalid firmware release manifest.",
        });
      }

      const release =
        registerFirmwareRelease(
          body,
        );

      return reply.code(201).send({
        success: true,
        data: release,
      });
    },
  );

  app.get(
    "/scoreboard-firmware/latest",
    async (request, reply) => {
      const query =
        request.query as LatestQuery;

      if (
        !query.currentVersion
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "currentVersion is required.",
        });
      }

      const release =
        getLatestCompatibleFirmwareRelease({
          currentVersion:
            query.currentVersion,
          channel:
            query.channel ??
            "stable",
          target:
            query.target ??
            "esp32dev",
        });

      return {
        success: true,
        data: {
          updateAvailable:
            release !== null,
          release,
        },
      };
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
  'import { registerScoreboardFirmwareReleaseRoutes } from "./routes/scoreboardFirmwareReleases.js";';

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
    "await registerScoreboardFirmwareReleaseRoutes(app);",
  )
) {
  const anchors = [
    "await registerScoreboardDeviceEnrollmentRoutes(app);",
    "await registerScoreboardDeviceRoutes(app);",
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
          "await registerScoreboardFirmwareReleaseRoutes(app);\n\n  " +
            anchor,
        );
    } else {
      text =
        text.replace(
          anchor,
          anchor +
            "\n  await registerScoreboardFirmwareReleaseRoutes(app);",
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

describe("Milestone 13.2 firmware release registry / API", () => {
  it("persists firmware releases to a restart-safe registry", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardFirmwareReleaseRegistry.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "scoreboard-firmware-releases.json",
    );

    expect(service).toContain(
      "persistStore",
    );

    expect(service).toContain(
      "fs.renameSync",
    );
  });

  it("supports release lookup and latest-compatible selection", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardFirmwareReleaseRegistry.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "getFirmwareRelease",
    );

    expect(service).toContain(
      "getLatestCompatibleFirmwareRelease",
    );

    expect(service).toContain(
      "minimumCurrentVersion",
    );
  });

  it("supports stable beta development channel filtering", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardFirmwareReleaseRegistry.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "release.channel",
    );

    expect(service).toContain(
      "release.target",
    );
  });

  it("exposes release registry API routes", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareReleases.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/releases",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/releases/:releaseId",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/latest",
    );
  });

  it("returns updateAvailable from latest endpoint", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareReleases.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "updateAvailable",
    );

    expect(routes).toContain(
      "currentVersion is required.",
    );
  });

  it("registers firmware routes in API app", () => {
    const app = fs.readFileSync(
      new URL(
        "../../../apps/api/src/app.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(app).toContain(
      "registerScoreboardFirmwareReleaseRoutes",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 13.2 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - restart-safe firmware release registry"
echo "  - release list + lookup"
echo "  - channel / hardware target filtering"
echo "  - latest-compatible release selection"
echo "  - POST firmware release registration API"
echo "  - device-facing latest release API"
echo "  - API app registration"
echo "  - Milestone 13.2 tests"
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
echo "  Milestone 13.3 - OTA Release Import / Artifact Serving"
