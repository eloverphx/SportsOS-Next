#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="13.9-firmware-release-routes-canonical-rebuild"
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
  "$ROOT/apps/api/src/routes/scoreboardFirmwareReleases.ts" \
  "$ROOT/apps/api/src/services/scoreboardFirmwareReleaseRegistry.ts" \
  "$ROOT/apps/api/src/services/scoreboardFirmwareRollouts.ts" \
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

ROUTE="apps/api/src/routes/scoreboardFirmwareReleases.ts"
TEST="packages/core/test/firmware-release-routes-canonical-rebuild-13.9.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$TEST")"

cp -a "$ROUTE" "$BACKUP_DIR/$ROUTE"
[[ -f "$TEST" ]] && cp -a "$TEST" "$BACKUP_DIR/$TEST"

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

import {
  isVerifiedDevice,
} from "../services/scoreboardDeviceEnrollment.js";

import {
  findActiveRolloutForDevice,
} from "../services/scoreboardFirmwareRollouts.js";

type ReleaseQuery = {
  channel?: FirmwareReleaseChannel;
  target?: FirmwareReleaseTarget;
};

type LatestQuery = {
  currentVersion?: string;
  channel?: FirmwareReleaseChannel;
  target?: FirmwareReleaseTarget;
};

type DeviceOfferQuery = {
  deviceId?: string;
  currentVersion?: string;
  channel?: FirmwareReleaseChannel;
  target?: FirmwareReleaseTarget;
};

export async function registerScoreboardFirmwareReleaseRoutes(
  app: FastifyInstance,
) {
  /*
   * Operator/API release inventory.
   */
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

  /*
   * Single release lookup.
   */
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
        data:
          release,
      };
    },
  );

  /*
   * Register a validated release manifest.
   * Artifact validation/import remains owned by Milestone 13.3.
   */
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
        data:
          release,
      });
    },
  );

  /*
   * General compatibility lookup.
   *
   * This route is intentionally NOT rollout-aware. It answers:
   * "Does a newer compatible release exist?"
   *
   * Rollout authorization is enforced only by /device-offer.
   */
  app.get(
    "/scoreboard-firmware/latest",
    async (request, reply) => {
      const query =
        request.query as LatestQuery;

      if (!query.currentVersion) {
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

  /*
   * Device-facing OTA offer.
   *
   * A device receives an OTA offer only when:
   *  - it is verified
   *  - an ACTIVE rollout explicitly targets it
   *  - the rollout's release exists
   *  - channel and target match the device request
   *  - the device is not already on that version
   */
  app.get(
    "/scoreboard-firmware/device-offer",
    async (request, reply) => {
      const query =
        request.query as DeviceOfferQuery;

      if (
        !query.deviceId ||
        !query.currentVersion
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "deviceId and currentVersion are required.",
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

      const rollout =
        findActiveRolloutForDevice(
          query.deviceId,
        );

      if (!rollout) {
        return {
          success: true,
          data: {
            updateAvailable: false,
            offer: null,
            rollout: null,
          },
        };
      }

      const release =
        getFirmwareRelease(
          rollout.releaseId,
        );

      if (!release) {
        return {
          success: true,
          data: {
            updateAvailable: false,
            offer: null,
            rollout: {
              rolloutId:
                rollout.rolloutId,
              state:
                rollout.state,
            },
          },
        };
      }

      const requestedChannel =
        query.channel ??
        "stable";

      const requestedTarget =
        query.target ??
        "esp32dev";

      if (
        release.channel !==
          requestedChannel ||
        release.target !==
          requestedTarget
      ) {
        return {
          success: true,
          data: {
            updateAvailable: false,
            offer: null,
            rollout: {
              rolloutId:
                rollout.rolloutId,
              state:
                rollout.state,
            },
          },
        };
      }

      if (
        release.version ===
        query.currentVersion
      ) {
        return {
          success: true,
          data: {
            updateAvailable: false,
            offer: null,
            rollout: {
              rolloutId:
                rollout.rolloutId,
              state:
                rollout.state,
            },
          },
        };
      }

      const artifactUrl =
        `/scoreboard-firmware/releases/${encodeURIComponent(
          release.releaseId,
        )}/artifact?deviceId=${encodeURIComponent(
          query.deviceId,
        )}`;

      return {
        success: true,
        data: {
          updateAvailable: true,
          rollout: {
            rolloutId:
              rollout.rolloutId,
            state:
              rollout.state,
          },
          offer: {
            deviceId:
              query.deviceId,
            currentVersion:
              query.currentVersion,
            release,
            artifactUrl,
          },
        },
      };
    },
  );
}
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.9 canonical firmware release routes", () => {
  const source = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardFirmwareReleases.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("contains exactly one device-offer route", () => {
    const matches =
      source.match(
        /"\/scoreboard-firmware\/device-offer"/g,
      ) ?? [];

    expect(matches).toHaveLength(1);
  });

  it("keeps /latest independent from rollout state", () => {
    const latestStart =
      source.indexOf(
        '"/scoreboard-firmware/latest"',
      );

    const deviceOfferStart =
      source.indexOf(
        '"/scoreboard-firmware/device-offer"',
      );

    expect(latestStart).toBeGreaterThan(
      -1,
    );

    expect(deviceOfferStart).toBeGreaterThan(
      latestStart,
    );

    const latestBlock =
      source.slice(
        latestStart,
        deviceOfferStart,
      );

    expect(latestBlock).toContain(
      "getLatestCompatibleFirmwareRelease",
    );

    expect(latestBlock).not.toContain(
      "rollout.",
    );

    expect(latestBlock).not.toContain(
      "findActiveRolloutForDevice",
    );
  });

  it("declares rollout before all rollout uses in device-offer", () => {
    const start =
      source.indexOf(
        '"/scoreboard-firmware/device-offer"',
      );

    const route =
      source.slice(start);

    const declaration =
      route.indexOf(
        "const rollout =",
      );

    expect(declaration).toBeGreaterThan(
      -1,
    );

    for (const token of [
      "rollout.releaseId",
      "rollout.rolloutId",
      "rollout.state",
    ]) {
      const use =
        route.indexOf(token);

      expect(use).toBeGreaterThan(
        declaration,
      );
    }
  });

  it("preserves verified-device rollout gating", () => {
    expect(source).toContain(
      "isVerifiedDevice",
    );

    expect(source).toContain(
      "findActiveRolloutForDevice",
    );

    expect(source).toContain(
      "Verified scoreboard device required.",
    );
  });

  it("preserves the five intended release routes", () => {
    for (const route of [
      "/scoreboard-firmware/releases",
      "/scoreboard-firmware/releases/:releaseId",
      "/scoreboard-firmware/latest",
      "/scoreboard-firmware/device-offer",
    ]) {
      expect(source).toContain(route);
    }

    expect(source).toContain(
      "app.post(",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 13.9 canonical route rebuild"
echo "============================================================"
echo
echo "Repair:"
echo "  - fully rebuilds scoreboardFirmwareReleases.ts"
echo "  - removes all stray rollout references from /latest"
echo "  - preserves release list / lookup / registration"
echo "  - preserves general latest-compatible lookup"
echo "  - preserves verified rollout-aware device offers"
echo "  - guarantees rollout declaration is in correct scope"
echo "  - adds regression coverage against route contamination"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then rebuild:"
echo "  docker compose up -d --build api dashboard"
