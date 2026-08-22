#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="13.9-device-offer-rollout-scope-repair"
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
  "$ROOT/apps/api/src/services/scoreboardFirmwareRollouts.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

ROUTE="apps/api/src/routes/scoreboardFirmwareReleases.ts"
TEST="packages/core/test/fleet-update-device-offer-scope-13.9-repair.test.ts"

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

const routeMarker =
  '"/scoreboard-firmware/device-offer"';

const routeStart =
  text.indexOf(routeMarker);

if (routeStart === -1) {
  throw new Error(
    "Unable to locate /scoreboard-firmware/device-offer route.",
  );
}

/*
 * Find the route call's balanced parenthesis/block region so we patch only
 * this handler and do not accidentally insert rollout logic into /latest.
 */
let scanStart =
  text.lastIndexOf(
    "app.get(",
    routeStart,
  );

if (scanStart === -1) {
  throw new Error(
    "Unable to locate app.get() for device-offer route.",
  );
}

let parenDepth = 0;
let routeEnd = -1;
let started = false;
let inString = null;
let escaped = false;

for (let i = scanStart; i < text.length; i += 1) {
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
    started = true;
  } else if (ch === ")") {
    parenDepth -= 1;

    if (
      started &&
      parenDepth === 0
    ) {
      const semi =
        text.indexOf(";", i);

      routeEnd =
        semi === -1
          ? i + 1
          : semi + 1;

      break;
    }
  }
}

if (routeEnd === -1) {
  throw new Error(
    "Unable to locate end of device-offer route.",
  );
}

let block =
  text.slice(
    scanStart,
    routeEnd,
  );

if (
  !block.includes(
    "findActiveRolloutForDevice",
  )
) {
  const verifiedGateEndCandidates = [
    `      if (
        !isVerifiedDevice(
          query.deviceId,
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Verified scoreboard device required.",
        });
      }`,
    `      if (!isVerifiedDevice(query.deviceId)) {
        return reply.code(403).send({
          success: false,
          error: "Verified scoreboard device required.",
        });
      }`,
  ];

  let inserted = false;

  for (const anchor of verifiedGateEndCandidates) {
    if (!block.includes(anchor)) {
      continue;
    }

    block =
      block.replace(
        anchor,
`${anchor}

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
      }`,
      );

    inserted = true;
    break;
  }

  if (!inserted) {
    const queryAnchor =
      "      const release =";

    const idx =
      block.indexOf(
        queryAnchor,
      );

    if (idx === -1) {
      throw new Error(
        "Unable to locate release selection in device-offer route.",
      );
    }

    const rolloutCode = `      const rollout =
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

`;

    block =
      block.slice(0, idx) +
      rolloutCode +
      block.slice(idx);
  }
}

/*
 * Make sure rollout is declared before first use in this route.
 */
const declaration =
  block.indexOf(
    "const rollout =",
  );

const firstUse =
  block.indexOf(
    "rollout.releaseId",
  );

if (
  declaration === -1 ||
  firstUse === -1 ||
  declaration > firstUse
) {
  throw new Error(
    "Rollout declaration is missing or appears after rollout.releaseId use.",
  );
}

/*
 * Ensure the active rollout service import is present.
 */
const importLine =
  'import { findActiveRolloutForDevice } from "../services/scoreboardFirmwareRollouts.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate imports in scoreboardFirmwareReleases.ts.",
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

text =
  text.slice(0, scanStart) +
  block +
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

describe("Milestone 13.9 device-offer rollout scope repair", () => {
  const source = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardFirmwareReleases.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("imports active rollout lookup", () => {
    expect(source).toContain(
      "findActiveRolloutForDevice",
    );
  });

  it("declares rollout before rollout.releaseId is used", () => {
    const routeStart =
      source.indexOf(
        '"/scoreboard-firmware/device-offer"',
      );

    expect(routeStart).toBeGreaterThan(
      -1,
    );

    const route =
      source.slice(routeStart);

    const declaration =
      route.indexOf(
        "const rollout =",
      );

    const releaseUse =
      route.indexOf(
        "rollout.releaseId",
      );

    expect(declaration).toBeGreaterThan(
      -1,
    );

    expect(releaseUse).toBeGreaterThan(
      declaration,
    );
  });

  it("returns no update when device has no active rollout", () => {
    const routeStart =
      source.indexOf(
        '"/scoreboard-firmware/device-offer"',
      );

    const route =
      source.slice(routeStart);

    expect(route).toContain(
      "if (!rollout)",
    );

    expect(route).toContain(
      "updateAvailable: false",
    );

    expect(route).toContain(
      "rollout: null",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 13.9 rollout scope repair installed"
echo "============================================================"
echo
echo "Repair:"
echo "  - scopes active rollout lookup inside /device-offer"
echo "  - guarantees rollout is declared before release lookup"
echo "  - preserves verified-device gate"
echo "  - preserves no-active-rollout => no-update behavior"
echo "  - adds focused regression coverage"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then rebuild:"
echo "  docker compose up -d --build api dashboard"
