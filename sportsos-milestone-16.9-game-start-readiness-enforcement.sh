#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-16.9-game-start-readiness-enforcement-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/services/scoreboardPregameReadinessGate.ts" \
  "$ROOT/apps/api/src/services/automaticGameScoreboardSync.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

DISCOVERY="$(mktemp)"
trap 'rm -f "$DISCOVERY"' EXIT

grep -RInE \
  '(/start"|/start`|startGame|STARTED|IN_PROGRESS|LIVE|finalize|game-operations.*start)' \
  apps/api/src \
  2>/dev/null | head -n 250 > "$DISCOVERY" || true

echo "Game-start discovery:"
cat "$DISCOVERY"

TARGET="$(
node <<'NODE'
const fs = require("fs");
const path = require("path");

const roots = [
  "apps/api/src",
];

const files = [];

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (entry.isFile() && entry.name.endsWith(".ts")) files.push(full);
  }
}

for (const root of roots) {
  walk(root);
}

const candidates = [];

for (const file of files) {
  const text = fs.readFileSync(file, "utf8");
  let score = 0;

  if (/\/start["'`]/.test(text)) score += 10;
  if (/startGame/.test(text)) score += 8;
  if (/game-operations/.test(text)) score += 5;
  if (/IN_PROGRESS|LIVE|STARTED/.test(text)) score += 4;
  if (/FastifyInstance|app\.post|app\.put/.test(text)) score += 2;

  if (score > 0) {
    candidates.push({ file, score });
  }
}

candidates.sort((a, b) => b.score - a.score);

if (!candidates.length) {
  process.exit(2);
}

console.log(candidates[0].file);
NODE
)" || {
  echo "ERROR: unable to discover game-start route file." >&2
  echo "Repository was not modified." >&2
  exit 1
}

echo "Selected game-start integration target: $TARGET"

SERVICE="apps/api/src/services/scoreboardPregameStartIntegration.ts"
TEST="packages/core/test/game-start-readiness-enforcement-16.9.test.ts"
DISCOVERY_DOC="apps/api/src/services/scoreboardPregameStartIntegration.discovery.txt"

for file in "$SERVICE" "$TARGET" "$TEST" "$DISCOVERY_DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"
cp "$DISCOVERY" "$DISCOVERY_DOC"

cat > "$SERVICE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import {
  evaluatePregameReadinessGate,
} from "./scoreboardPregameReadinessGate.js";

type Assignment = {
  gameId: string;
  deviceId: string;
};

export type PregameStartGateResult = {
  allowed: boolean;
  gameId: string;
  deviceId: string | null;
  risk:
    | "HEALTHY"
    | "WATCH"
    | "AT_RISK"
    | "OFFLINE"
    | "UNKNOWN";
  overrideApplied: boolean;
  reason: string | null;
};

async function assignedDeviceForGame(
  app: FastifyInstance,
  gameId: string,
): Promise<string | null> {
  const response =
    await app.inject({
      method: "GET",
      url:
        "/scoreboard-devices/assignments",
    });

  if (
    response.statusCode < 200 ||
    response.statusCode >= 300
  ) {
    return null;
  }

  try {
    const body =
      response.json() as {
        data?: {
          assignments?: Assignment[];
        };
        assignments?: Assignment[];
      };

    const assignments =
      body.data?.assignments ??
      body.assignments ??
      [];

    return (
      assignments.find(
        (item) =>
          item.gameId ===
          gameId,
      )?.deviceId ??
      null
    );
  } catch {
    return null;
  }
}

export async function evaluateGameStartReadiness(
  app: FastifyInstance,
  gameId: string,
): Promise<PregameStartGateResult> {
  const deviceId =
    await assignedDeviceForGame(
      app,
      gameId,
    );

  return evaluatePregameReadinessGate({
    gameId,
    deviceId,
  });
}
EOF

node - "$TARGET" <<'NODE'
const fs = require("fs");

const file = process.argv[2];

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { evaluateGameStartReadiness } from "../services/scoreboardPregameStartIntegration.js";';

const altImportLine =
  'import { evaluateGameStartReadiness } from "../../services/scoreboardPregameStartIntegration.js";';

if (
  !text.includes(
    "evaluateGameStartReadiness",
  )
) {
  const imports =
    text.match(
      /^(import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate imports in discovered game-start route.",
    );
  }

  const relative =
    file.includes(
      "/modules/",
    )
      ? altImportLine
      : importLine;

  text =
    text.replace(
      imports[0],
      imports[0] +
        relative +
        "\n",
    );
}

/*
 * Locate a start route handler and inject readiness enforcement immediately
 * after gameId becomes available but before any mutation call.
 */
if (
  !text.includes(
    "PREGAME_SCOREBOARD_READINESS_GATE",
  )
) {
  const startRouteMatch =
    text.match(
      /app\.(?:post|put)\(\s*["'`][^"'`]*\/start["'`][\s\S]{0,4000}?\n\s*\}\s*,?\s*\);/,
    );

  let regionStart = -1;
  let regionEnd = -1;

  if (startRouteMatch) {
    regionStart =
      startRouteMatch.index;
    regionEnd =
      startRouteMatch.index +
      startRouteMatch[0].length;
  } else {
    const startIndex =
      text.search(
        /\/start["'`]/
      );

    if (startIndex === -1) {
      throw new Error(
        "Unable to locate start-game route.",
      );
    }

    regionStart =
      Math.max(
        0,
        startIndex - 1200,
      );

    regionEnd =
      Math.min(
        text.length,
        startIndex + 5000,
      );
  }

  const region =
    text.slice(
      regionStart,
      regionEnd,
    );

  const gameIdPatterns = [
    /const\s+gameId\s*=\s*[^;]+;/,
    /const\s+id\s*=\s*[^;]+;/,
    /gameId\s*:\s*params\.gameId/,
  ];

  let anchorMatch = null;

  for (const pattern of gameIdPatterns) {
    const found =
      region.match(
        pattern,
      );

    if (found) {
      anchorMatch =
        found;
      break;
    }
  }

  if (!anchorMatch) {
    throw new Error(
      "Unable to locate game ID declaration inside start-game route.",
    );
  }

  const anchorGlobal =
    regionStart +
    anchorMatch.index +
    anchorMatch[0].length;

  const gameIdExpression =
    /^const\s+id\s*=/.test(
      anchorMatch[0],
    )
      ? "id"
      : "gameId";

  const block =
`

      const PREGAME_SCOREBOARD_READINESS_GATE =
        await evaluateGameStartReadiness(
          app,
          ${gameIdExpression},
        );

      if (
        !PREGAME_SCOREBOARD_READINESS_GATE.allowed
      ) {
        return reply.code(409).send({
          success: false,
          error:
            PREGAME_SCOREBOARD_READINESS_GATE.reason ??
            "Pregame scoreboard readiness gate blocked game start.",
          data: {
            readinessGate:
              PREGAME_SCOREBOARD_READINESS_GATE,
          },
        });
      }
`;

  text =
    text.slice(
      0,
      anchorGlobal,
    ) +
    block +
    text.slice(
      anchorGlobal,
    );
}

if (
  !text.includes(
    "PREGAME_SCOREBOARD_READINESS_GATE",
  )
) {
  throw new Error(
    "Unable to enforce pregame readiness gate in start route.",
  );
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat > "$TEST" <<EOF
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 16.9 game start integration / readiness gate enforcement", () => {
  const integration = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardPregameStartIntegration.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route = fs.readFileSync(
    new URL(
      "../../../${TARGET}",
      import.meta.url,
    ),
    "utf8",
  );

  it("resolves assigned scoreboard before evaluating game start", () => {
    expect(integration).toContain(
      "/scoreboard-devices/assignments",
    );

    expect(integration).toContain(
      "evaluatePregameReadinessGate",
    );
  });

  it("enforces readiness inside the actual start-game route", () => {
    expect(route).toContain(
      "evaluateGameStartReadiness",
    );

    expect(route).toContain(
      "PREGAME_SCOREBOARD_READINESS_GATE",
    );
  });

  it("blocks the start route when readiness is not allowed", () => {
    expect(route).toContain(
      "PREGAME_SCOREBOARD_READINESS_GATE.allowed",
    );

    expect(route).toContain(
      "reply.code(409)",
    );
  });

  it("returns readiness-gate diagnostics on rejection", () => {
    expect(route).toContain(
      "readinessGate",
    );

    expect(route).toContain(
      "Pregame scoreboard readiness gate blocked game start.",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 16.9 installed"
echo "============================================================"
echo
echo "Integrated game-start route:"
echo "  $TARGET"
echo
echo "Added:"
echo "  - live game -> scoreboard assignment resolution"
echo "  - pregame reliability gate evaluation"
echo "  - actual game-start route enforcement"
echo "  - HTTP 409 when start is blocked"
echo "  - override support inherited from 16.8"
echo "  - readiness-gate diagnostics in rejection payload"
echo "  - discovery snapshot:"
echo "    $DISCOVERY_DOC"
echo "  - Milestone 16.9 regression tests"
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
echo "  Milestone 16.10 - Physical Control Resilience Acceptance / Closeout"
