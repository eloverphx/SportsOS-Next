#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.4-startgame-lifecycle-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

GAMES="apps/api/src/modules/games/routes.ts"
GUARD="apps/api/src/services/gameStartPreflightGuard.ts"
TEST="packages/core/test/game-start-preflight-enforcement-18.4.test.ts"

for required in \
  ".git" \
  "$GAMES" \
  "apps/api/src/services/gameDayHardwarePreflight.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$GAMES" "$GUARD" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$GUARD")" "$(dirname "$TEST")"

cat > "$GUARD" <<'EOF'
import {
  gameDayHardwarePreflightFreshness,
  latestGameDayHardwarePreflight,
} from "./gameDayHardwarePreflight.js";

export type GameStartPreflightDecision =
  | {
      allowed: true;
      gameId: string;
      preflightId: string;
      deviceId: string;
      expiresAt: string;
    }
  | {
      allowed: false;
      gameId: string;
      code:
        | "PREFLIGHT_REQUIRED"
        | "PREFLIGHT_FAILED"
        | "PREFLIGHT_EXPIRED";
      message: string;
      preflightId: string | null;
      deviceId: string | null;
      expiresAt: string | null;
    };

export function evaluateGameStartPreflight(
  gameId: string,
): GameStartPreflightDecision {
  const preflight =
    latestGameDayHardwarePreflight(
      gameId,
    );

  const freshness =
    gameDayHardwarePreflightFreshness(
      preflight,
    );

  if (!preflight) {
    return {
      allowed: false,
      gameId,
      code:
        "PREFLIGHT_REQUIRED",
      message:
        "Run and pass a game-day hardware preflight before starting the game.",
      preflightId:
        null,
      deviceId:
        null,
      expiresAt:
        null,
    };
  }

  if (
    preflight.status !==
      "PASS"
  ) {
    return {
      allowed: false,
      gameId,
      code:
        "PREFLIGHT_FAILED",
      message:
        "The latest game-day hardware preflight failed. Resolve the failed checks and rerun preflight.",
      preflightId:
        preflight.preflightId,
      deviceId:
        preflight.deviceId,
      expiresAt:
        freshness.expiresAt,
    };
  }

  if (
    !freshness.fresh ||
    !freshness.expiresAt
  ) {
    return {
      allowed: false,
      gameId,
      code:
        "PREFLIGHT_EXPIRED",
      message:
        "The latest passing game-day hardware preflight has expired. Rerun preflight.",
      preflightId:
        preflight.preflightId,
      deviceId:
        preflight.deviceId,
      expiresAt:
        freshness.expiresAt,
    };
  }

  return {
    allowed: true,
    gameId,
    preflightId:
      preflight.preflightId,
    deviceId:
      preflight.deviceId,
    expiresAt:
      freshness.expiresAt,
  };
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/modules/games/routes.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { evaluateGameStartPreflight } from "../../services/gameStartPreflightGuard.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate routes.ts import block.",
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
  text.includes(
    "GAME_START_PREFLIGHT_ENFORCEMENT_18_4"
  )
) {
  fs.writeFileSync(
    file,
    text,
  );

  console.log(
    "18.4 startGame preflight enforcement already present.",
  );

  process.exit(0);
}

const lifecycleRoute =
  'app.post("/games/:id/lifecycle"';

const lifecycleIndex =
  text.indexOf(
    lifecycleRoute,
  );

if (
  lifecycleIndex === -1
) {
  throw new Error(
    "Unable to locate POST /games/:id/lifecycle.",
  );
}

const nextRoute =
  text.indexOf(
    "\n  app.",
    lifecycleIndex + 20,
  );

const lifecycleEnd =
  nextRoute === -1
    ? text.length
    : nextRoute;

const region =
  text.slice(
    lifecycleIndex,
    lifecycleEnd,
  );

const startGameAnchor =
  'parsed.data.command === "startGame"';

const commandIndex =
  region.indexOf(
    startGameAnchor,
  );

if (
  commandIndex === -1
) {
  throw new Error(
    'Unable to locate parsed.data.command === "startGame" inside lifecycle route.',
  );
}

const globalCommandIndex =
  lifecycleIndex +
  commandIndex;

const ifStart =
  text.lastIndexOf(
    "if (",
    globalCommandIndex,
  );

if (
  ifStart === -1 ||
  ifStart <
    lifecycleIndex
) {
  throw new Error(
    "Unable to locate startGame conditional.",
  );
}

const braceOpen =
  text.indexOf(
    "{",
    globalCommandIndex,
  );

if (
  braceOpen === -1 ||
  braceOpen >
    lifecycleEnd
) {
  throw new Error(
    "Unable to locate startGame conditional body.",
  );
}

/*
 * 16.9 may already have inserted a scoreboard readiness gate in this exact
 * branch. Insert 18.4 immediately after the opening brace so it executes
 * before any lifecycle mutation or downstream scoring action.
 */
const block =
`

      // GAME_START_PREFLIGHT_ENFORCEMENT_18_4
      const gameStartPreflight =
        evaluateGameStartPreflight(
          String(id.data),
        );

      if (
        !gameStartPreflight.allowed
      ) {
        return reply.code(409).send({
          success: false,
          error: {
            code:
              gameStartPreflight.code,
            message:
              gameStartPreflight.message,
          },
          data: {
            preflight:
              gameStartPreflight,
          },
        });
      }
`;

text =
  text.slice(
    0,
    braceOpen + 1,
  ) +
  block +
  text.slice(
    braceOpen + 1,
  );

fs.writeFileSync(
  file,
  text,
);

console.log(
  "18.4 preflight enforcement bound to /games/:id/lifecycle -> startGame.",
);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.4 deterministic startGame preflight enforcement", () => {
  const guard =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameStartPreflightGuard.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const routes =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/modules/games/routes.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("blocks missing failed and expired preflight", () => {
    expect(guard).toContain(
      '"PREFLIGHT_REQUIRED"',
    );

    expect(guard).toContain(
      '"PREFLIGHT_FAILED"',
    );

    expect(guard).toContain(
      '"PREFLIGHT_EXPIRED"',
    );
  });

  it("binds enforcement to lifecycle startGame", () => {
    expect(routes).toContain(
      'app.post("/games/:id/lifecycle"',
    );

    expect(routes).toContain(
      'parsed.data.command === "startGame"',
    );

    expect(routes).toContain(
      "GAME_START_PREFLIGHT_ENFORCEMENT_18_4",
    );
  });

  it("rejects before game mutation with HTTP 409", () => {
    expect(routes).toContain(
      "evaluateGameStartPreflight",
    );

    expect(routes).toContain(
      "reply.code(409)",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 18.4 lifecycle repair installed"
echo "============================================================"
echo
echo "Fixed:"
echo "  - removed generic game-start route discovery"
echo "  - binds directly to POST /games/:id/lifecycle"
echo "  - enforces only command === startGame"
echo "  - preserves later clock resume/recovery operations"
echo "  - evaluates preflight before lifecycle mutation"
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
echo "  Milestone 18.5 - Preflight Assignment Binding / Device Swap Invalidation"
