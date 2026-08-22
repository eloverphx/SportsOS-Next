#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="13.9-device-offer-handler-replacement-repair"
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
  "$ROOT/apps/api/src/services/scoreboardFirmwareRollouts.ts" \
  "$ROOT/apps/api/src/services/scoreboardFirmwareReleaseRegistry.ts" \
  "$ROOT/apps/api/src/services/scoreboardDeviceEnrollment.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

ROUTE="apps/api/src/routes/scoreboardFirmwareReleases.ts"
TEST="packages/core/test/fleet-update-device-offer-handler-13.9-repair.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$TEST")"

cp -a "$ROUTE" "$BACKUP_DIR/$ROUTE"
[[ -f "$TEST" ]] && cp -a "$TEST" "$BACKUP_DIR/$TEST"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardFirmwareReleases.ts";

let text =
  fs.readFileSync(file, "utf8");

const requiredImports = [
  {
    line:
      'import { findActiveRolloutForDevice } from "../services/scoreboardFirmwareRollouts.js";',
    anchor:
      '../services/scoreboardFirmwareReleaseRegistry.js";',
  },
  {
    line:
      'import { isVerifiedDevice } from "../services/scoreboardDeviceEnrollment.js";',
    anchor:
      '../services/scoreboardFirmwareReleaseRegistry.js";',
  },
];

for (const item of requiredImports) {
  if (text.includes(item.line)) {
    continue;
  }

  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      `Unable to locate import block for ${item.line}`,
    );
  }

  text =
    text.replace(
      imports[0],
      imports[0] +
        item.line +
        "\n",
    );
}

const routeMarker =
  '"/scoreboard-firmware/device-offer"';

const markerIndex =
  text.indexOf(routeMarker);

if (markerIndex === -1) {
  throw new Error(
    "Unable to locate device-offer route marker.",
  );
}

const appGetStart =
  text.lastIndexOf(
    "app.get(",
    markerIndex,
  );

if (appGetStart === -1) {
  throw new Error(
    "Unable to locate app.get() start for device-offer route.",
  );
}

/*
 * Find the end of this exact app.get(...) call using balanced delimiters.
 * This ignores string contents sufficiently for our TypeScript route body.
 */
let parenDepth = 0;
let braceDepth = 0;
let bracketDepth = 0;
let inString = null;
let escaped = false;
let routeCallStarted = false;
let routeEnd = -1;

for (let i = appGetStart; i < text.length; i += 1) {
  const ch = text[i];

  if (inString) {
    if (escaped) {
      escaped = false;
      continue;
    }

    if (ch === "\\") {
      escaped = true;
      continue;
    }

    if (ch === inString) {
      inString = null;
    }

    continue;
  }

  if (
    ch === '"' ||
    ch === "'" ||
    ch === "`"
  ) {
    inString = ch;
    continue;
  }

  if (ch === "(") {
    parenDepth += 1;
    routeCallStarted = true;
  } else if (ch === ")") {
    parenDepth -= 1;
  } else if (ch === "{") {
    braceDepth += 1;
  } else if (ch === "}") {
    braceDepth -= 1;
  } else if (ch === "[") {
    bracketDepth += 1;
  } else if (ch === "]") {
    bracketDepth -= 1;
  }

  if (
    routeCallStarted &&
    parenDepth === 0 &&
    braceDepth === 0 &&
    bracketDepth === 0 &&
    i > markerIndex
  ) {
    let j = i + 1;

    while (
      j < text.length &&
      /\s/.test(text[j])
    ) {
      j += 1;
    }

    if (text[j] === ";") {
      routeEnd = j + 1;
      break;
    }
  }
}

if (routeEnd === -1) {
  throw new Error(
    "Unable to locate end of device-offer app.get() call.",
  );
}

const replacement = `app.get(
    "/scoreboard-firmware/device-offer",
    async (request, reply) => {
      const query =
        request.query as {
          deviceId?: string;
          currentVersion?: string;
          channel?: FirmwareReleaseChannel;
          target?: FirmwareReleaseTarget;
        };

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
        \`/scoreboard-firmware/releases/\${encodeURIComponent(
          release.releaseId,
        )}/artifact?deviceId=\${encodeURIComponent(
          query.deviceId,
        )}\`;

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
  );`;

text =
  text.slice(0, appGetStart) +
  replacement +
  text.slice(routeEnd);

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.9 device-offer handler replacement repair", () => {
  const source = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardFirmwareReleases.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const routeStart =
    source.indexOf(
      '"/scoreboard-firmware/device-offer"',
    );

  const route =
    source.slice(
      routeStart,
    );

  it("declares rollout before rollout.releaseId", () => {
    expect(routeStart).toBeGreaterThan(
      -1,
    );

    const declaration =
      route.indexOf(
        "const rollout =",
      );

    const firstUse =
      route.indexOf(
        "rollout.releaseId",
      );

    expect(declaration).toBeGreaterThan(
      -1,
    );

    expect(firstUse).toBeGreaterThan(
      declaration,
    );
  });

  it("requires verified devices", () => {
    expect(route).toContain(
      "isVerifiedDevice",
    );

    expect(route).toContain(
      "Verified scoreboard device required.",
    );
  });

  it("returns no offer without an active rollout", () => {
    expect(route).toContain(
      "findActiveRolloutForDevice",
    );

    expect(route).toContain(
      "rollout: null",
    );

    expect(route).toContain(
      "updateAvailable: false",
    );
  });

  it("selects the rollout release directly", () => {
    expect(route).toContain(
      "getFirmwareRelease",
    );

    expect(route).toContain(
      "rollout.releaseId",
    );
  });

  it("returns device-bound artifact URL when update is available", () => {
    expect(route).toContain(
      "artifactUrl",
    );

    expect(route).toContain(
      "deviceId=",
    );

    expect(route).toContain(
      "updateAvailable: true",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 13.9 handler replacement repair"
echo "============================================================"
echo
echo "Repair:"
echo "  - replaces the complete /device-offer handler"
echo "  - active rollout lookup is guaranteed in handler scope"
echo "  - verified-device gate preserved"
echo "  - rollout release selected directly"
echo "  - no rollout => no update"
echo "  - channel / target checks preserved"
echo "  - current version => no update"
echo "  - device-bound artifact URL preserved"
echo "  - focused regression test added"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then rebuild:"
echo "  docker compose up -d --build api dashboard"
