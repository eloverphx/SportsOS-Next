#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.4-game-start-preflight-enforcement-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}
cd "$ROOT"

for required in \
  ".git" \
  "apps/api/src/services/gameDayHardwarePreflight.ts" \
  "apps/api/src/modules/games/routes.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

GUARD="apps/api/src/services/gameStartPreflightGuard.ts"
GAMES="apps/api/src/modules/games/routes.ts"
TEST="packages/core/test/game-start-preflight-enforcement-18.4.test.ts"
DOC="docs/GAME-DAY-HARDWARE-PREFLIGHT.md"
DISCOVERY="apps/api/src/modules/games/game-start-route-18.4.discovery.txt"

for file in "$GUARD" "$GAMES" "$TEST" "$DOC" "$DISCOVERY"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done
mkdir -p "$(dirname "$GUARD")" "$(dirname "$TEST")"

grep -n -C 8 -E 'start|START|clock|running|LIVE|IN_PROGRESS' "$GAMES" \
  > "$DISCOVERY" || true

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
    latestGameDayHardwarePreflight(gameId);

  const freshness =
    gameDayHardwarePreflightFreshness(preflight);

  if (!preflight) {
    return {
      allowed: false,
      gameId,
      code: "PREFLIGHT_REQUIRED",
      message:
        "Run and pass a game-day hardware preflight before starting the game.",
      preflightId: null,
      deviceId: null,
      expiresAt: null,
    };
  }

  if (preflight.status !== "PASS") {
    return {
      allowed: false,
      gameId,
      code: "PREFLIGHT_FAILED",
      message:
        "The latest game-day hardware preflight failed. Resolve the failed checks and rerun preflight.",
      preflightId: preflight.preflightId,
      deviceId: preflight.deviceId,
      expiresAt: freshness.expiresAt,
    };
  }

  if (!freshness.fresh || !freshness.expiresAt) {
    return {
      allowed: false,
      gameId,
      code: "PREFLIGHT_EXPIRED",
      message:
        "The latest passing game-day hardware preflight has expired. Rerun preflight.",
      preflightId: preflight.preflightId,
      deviceId: preflight.deviceId,
      expiresAt: freshness.expiresAt,
    };
  }

  return {
    allowed: true,
    gameId,
    preflightId: preflight.preflightId,
    deviceId: preflight.deviceId,
    expiresAt: freshness.expiresAt,
  };
}
EOF

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/modules/games/routes.ts";
let text = fs.readFileSync(file, "utf8");

const importLine =
  'import { evaluateGameStartPreflight } from "../../services/gameStartPreflightGuard.js";';

if (!text.includes(importLine)) {
  const imports = text.match(/^(?:import[\s\S]*?;\n)+/);
  if (!imports) throw new Error("Unable to locate game route imports.");
  text = text.replace(imports[0], imports[0] + importLine + "\n");
}

if (text.includes("GAME_START_PREFLIGHT_ENFORCEMENT_18_4")) {
  fs.writeFileSync(file, text);
  process.exit(0);
}

const patterns = [
  /(?:app|fastify)\.(?:post|patch|put)\(\s*["'`]([^"'`]*\/start)["'`]/gi,
  /(?:app|fastify)\.(?:post|patch|put)\(\s*["'`]([^"'`]*start[^"'`]*)["'`]/gi,
];

let match;
for (const pattern of patterns) {
  const found = pattern.exec(text);
  if (found) {
    match = found;
    break;
  }
}

if (!match) {
  throw new Error(
    "Unable to discover authoritative game-start route. Inspect game-start-route-18.4.discovery.txt."
  );
}

const handlerArrow = text.indexOf("=>", match.index);
const bodyOpen = text.indexOf("{", handlerArrow);

if (handlerArrow < 0 || bodyOpen < 0 || bodyOpen > handlerArrow + 500) {
  throw new Error("Unable to locate game-start handler body.");
}

const nearby = text.slice(bodyOpen, bodyOpen + 5000);
const candidates = ["params.gameId", "request.params.gameId", "gameId"];
const expression = candidates.find((item) => nearby.includes(item));

if (!expression) {
  throw new Error("Unable to identify gameId expression in game-start handler.");
}

const guard = `
      // GAME_START_PREFLIGHT_ENFORCEMENT_18_4
      const gameStartPreflight =
        evaluateGameStartPreflight(
          String(${expression}),
        );

      if (!gameStartPreflight.allowed) {
        return reply.code(409).send({
          success: false,
          error: {
            code: gameStartPreflight.code,
            message: gameStartPreflight.message,
          },
          data: {
            preflight: gameStartPreflight,
          },
        });
      }

`;

text =
  text.slice(0, bodyOpen + 1) +
  guard +
  text.slice(bodyOpen + 1);

fs.writeFileSync(file, text);
NODE

cat >> "$DOC" <<'EOF'

## Game-start preflight enforcement

Milestone 18.4 blocks the authoritative game-start path when no preflight exists (`PREFLIGHT_REQUIRED`), the latest preflight failed (`PREFLIGHT_FAILED`), or the latest passing preflight expired (`PREFLIGHT_EXPIRED`).

Only a fresh PASS allows game start. Blocked starts return HTTP 409 and do not mutate game state. There is no automatic bypass; failed or expired readiness must be corrected and rerun.
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 18.4 game-start preflight enforcement", () => {
  const guard = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/gameStartPreflightGuard.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const routes = fs.readFileSync(
    new URL(
      "../../../apps/api/src/modules/games/routes.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("blocks missing, failed, and expired preflight", () => {
    expect(guard).toContain('"PREFLIGHT_REQUIRED"');
    expect(guard).toContain('"PREFLIGHT_FAILED"');
    expect(guard).toContain('"PREFLIGHT_EXPIRED"');
  });

  it("allows only fresh passing preflight", () => {
    expect(guard).toContain("freshness.fresh");
    expect(guard).toContain("allowed: true");
  });

  it("enforces the guard in the game-start route", () => {
    expect(routes).toContain("GAME_START_PREFLIGHT_ENFORCEMENT_18_4");
    expect(routes).toContain("evaluateGameStartPreflight");
    expect(routes).toContain("reply.code(409)");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 18.4 installed"
echo "============================================================"
echo "Added:"
echo "  - authoritative game-start preflight guard"
echo "  - PREFLIGHT_REQUIRED / FAILED / EXPIRED"
echo "  - fresh PASS start authorization"
echo "  - HTTP 409 machine-readable rejection"
echo "  - no automatic bypass"
echo "  - Milestone 18.4 regression tests"
echo
echo "Discovery: $DISCOVERY"
echo "Backup: $BACKUP"
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
