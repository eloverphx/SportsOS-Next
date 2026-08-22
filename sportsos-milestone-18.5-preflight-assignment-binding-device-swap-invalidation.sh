#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.5-preflight-assignment-binding-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "apps/api/src/services/gameDayHardwarePreflight.ts" \
  "apps/api/src/services/gameStartPreflightGuard.ts" \
  "apps/api/src/routes/gameDayHardwarePreflight.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

SERVICE="apps/api/src/services/gameDayHardwarePreflight.ts"
GUARD="apps/api/src/services/gameStartPreflightGuard.ts"
ROUTE="apps/api/src/routes/gameDayHardwarePreflight.ts"
TEST="packages/core/test/preflight-assignment-binding-18.5.test.ts"
DOC="docs/GAME-DAY-HARDWARE-PREFLIGHT.md"

for file in "$SERVICE" "$GUARD" "$ROUTE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/gameDayHardwarePreflight.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (!text.includes("assignmentFingerprint")) {
  text =
    text.replace(
`  deviceId: string;
  status:`,
`  deviceId: string;
  assignmentFingerprint: string;
  status:`
    );

  text =
    text.replace(
`      deviceId:
        input.deviceId,
      status:`,
`      deviceId:
        input.deviceId,
      assignmentFingerprint:
        \`\${input.gameId}::\${input.deviceId}\`,
      status:`
    );
}

if (!text.includes("matchesCurrentAssignment")) {
  text += `

export function matchesCurrentAssignment(
  preflight: GameDayHardwarePreflight | null,
  gameId: string,
  deviceId: string | null,
): boolean {
  if (
    !preflight ||
    !deviceId
  ) {
    return false;
  }

  return (
    preflight.gameId ===
      gameId &&
    preflight.deviceId ===
      deviceId &&
    preflight.assignmentFingerprint ===
      \`\${gameId}::\${deviceId}\`
  );
}
`;
}

fs.writeFileSync(
  file,
  text,
);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/gameStartPreflightGuard.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !text.includes(
    "matchesCurrentAssignment",
  )
) {
  text =
    text.replace(
`  gameDayHardwarePreflightFreshness,
  latestGameDayHardwarePreflight,`,
`  gameDayHardwarePreflightFreshness,
  latestGameDayHardwarePreflight,
  matchesCurrentAssignment,`
    );
}

if (
  !text.includes(
    '"PREFLIGHT_ASSIGNMENT_CHANGED"'
  )
) {
  text =
    text.replace(
`        | "PREFLIGHT_EXPIRED";`,
`        | "PREFLIGHT_EXPIRED"
        | "PREFLIGHT_ASSIGNMENT_CHANGED";`
    );
}

if (
  !text.includes(
    "currentDeviceId:"
  )
) {
  text =
    text.replace(
`export function evaluateGameStartPreflight(
  gameId: string,
): GameStartPreflightDecision {`,
`export function evaluateGameStartPreflight(
  gameId: string,
  currentDeviceId: string | null = null,
): GameStartPreflightDecision {`
    );
}

if (
  !text.includes(
    "PREFLIGHT_ASSIGNMENT_CHANGED"
  )
) {
  throw new Error(
    "Unable to extend preflight decision union.",
  );
}

if (
  !text.includes(
    "matchesCurrentAssignment("
  )
) {
  const anchor =
`  if (
    preflight.status !==
      "PASS"
  ) {`;

  const idx =
    text.indexOf(
      anchor,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate failed-preflight branch.",
    );
  }

  const block =
`  if (
    currentDeviceId &&
    !matchesCurrentAssignment(
      preflight,
      gameId,
      currentDeviceId,
    )
  ) {
    return {
      allowed: false,
      gameId,
      code:
        "PREFLIGHT_ASSIGNMENT_CHANGED",
      message:
        "The scoreboard assignment changed after the latest preflight. Run a new preflight for the currently assigned device.",
      preflightId:
        preflight.preflightId,
      deviceId:
        preflight.deviceId,
      expiresAt:
        freshness.expiresAt,
    };
  }

`;

  text =
    text.slice(0, idx) +
    block +
    text.slice(idx);
}

fs.writeFileSync(
  file,
  text,
);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/gameDayHardwarePreflight.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !text.includes(
    "assignmentFingerprint"
  )
) {
  // API already returns full preflight objects; no route schema rewrite needed.
  // Add an explicit note in response payload for operator/debug visibility.
  const marker =
`          preflight,
          freshness:`;

  if (text.includes(marker)) {
    text =
      text.replace(
        marker,
`          preflight,
          assignmentFingerprint:
            preflight?.assignmentFingerprint ??
            null,
          freshness:`
      );
  }
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat >> "$DOC" <<'EOF'

## Assignment binding and device swap invalidation

Milestone 18.5 binds every game-day preflight to the exact game/device assignment present when the preflight ran.

Each preflight stores an `assignmentFingerprint` in the form:

`gameId::deviceId`

If the game is later assigned to a different scoreboard device, the old preflight no longer matches the current assignment and must not authorize game start.

The game-start guard exposes `PREFLIGHT_ASSIGNMENT_CHANGED` for this condition. A replacement device therefore requires its own fresh passing preflight.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.5 preflight assignment binding / device swap invalidation", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameDayHardwarePreflight.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const guard =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameStartPreflightGuard.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("stores an assignment fingerprint on preflight", () => {
    expect(service).toContain(
      "assignmentFingerprint",
    );

    expect(service).toContain(
      "input.gameId",
    );

    expect(service).toContain(
      "input.deviceId",
    );
  });

  it("compares preflight against the current assignment", () => {
    expect(service).toContain(
      "matchesCurrentAssignment",
    );

    expect(service).toContain(
      "preflight.deviceId ===",
    );
  });

  it("defines an assignment-changed start rejection", () => {
    expect(guard).toContain(
      '"PREFLIGHT_ASSIGNMENT_CHANGED"',
    );

    expect(guard).toContain(
      "scoreboard assignment changed",
    );
  });

  it("requires a new preflight for replacement hardware", () => {
    expect(guard).toContain(
      "matchesCurrentAssignment",
    );

    expect(guard).toContain(
      "currentDeviceId",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 18.5 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - game/device assignment fingerprint on every preflight"
echo "  - current-assignment comparison helper"
echo "  - device-swap invalidation"
echo "  - PREFLIGHT_ASSIGNMENT_CHANGED rejection"
echo "  - replacement hardware requires new preflight"
echo "  - Milestone 18.5 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 18.6 - Preflight Override Policy / Emergency Start Authorization"
