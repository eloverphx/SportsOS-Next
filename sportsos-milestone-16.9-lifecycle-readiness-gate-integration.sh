#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-16.9-lifecycle-readiness-gate-integration-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"
[[ "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

ROUTE="apps/api/src/modules/games/routes.ts"
GATE="apps/api/src/services/scoreboardPregameReadinessGate.ts"
SYNC="apps/api/src/services/automaticGameScoreboardSync.ts"
TEST="packages/core/test/game-start-readiness-enforcement-16.9.test.ts"

for required in ".git" "$ROUTE" "$GATE" "$SYNC"; do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

mkdir -p "$BACKUP/$(dirname "$ROUTE")"
cp -a "$ROUTE" "$BACKUP/$ROUTE"
for f in "$TEST"; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp -a "$f" "$BACKUP/$f"
  fi
done

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/modules/games/routes.ts";
let text = fs.readFileSync(file, "utf8");

if (text.includes("PREGAME_SCOREBOARD_READINESS_GATE_16_9")) {
  console.log("16.9 lifecycle readiness gate already present; leaving route unchanged.");
  process.exit(0);
}

const importLine =
  'import { evaluatePregameReadinessGate } from "../../services/scoreboardPregameReadinessGate.js";\n';

if (!text.includes("evaluatePregameReadinessGate")) {
  const imports = text.match(/^(?:import[\s\S]*?;\n)+/);
  if (!imports) throw new Error("Unable to locate routes.ts import block.");
  text = text.replace(imports[0], imports[0] + importLine);
}

const routeStart = text.indexOf('app.post("/games/:id/lifecycle"');
if (routeStart === -1) {
  throw new Error("Unable to locate /games/:id/lifecycle route.");
}

const routeEnd = text.indexOf('\n  });', routeStart);
if (routeEnd === -1) {
  throw new Error("Unable to locate lifecycle route end.");
}

const region = text.slice(routeStart, routeEnd);

const gameLookupPatterns = [
  /const game = await findGameById\(id\.data\);/,
  /const game =\s*await findGameById\(id\.data\);/
];

let lookup = null;
for (const pattern of gameLookupPatterns) {
  const match = region.match(pattern);
  if (match) {
    lookup = match;
    break;
  }
}
if (!lookup) {
  throw new Error(
    "Unable to locate lifecycle findGameById(id.data) lookup. " +
    "Repository was not modified."
  );
}

const globalAnchor =
  routeStart + lookup.index + lookup[0].length;

const block = `

    // PREGAME_SCOREBOARD_READINESS_GATE_16_9
    // Enforce only the explicit startGame lifecycle command. Other
    // startClock operations (period resume, recovery, etc.) remain unchanged.
    if (parsed.data.command === "startGame") {
      const assignmentsResponse = await app.inject({
        method: "GET",
        url: "/scoreboard-devices/assignments",
      });

      let assignedDeviceId: string | null = null;

      if (
        assignmentsResponse.statusCode >= 200 &&
        assignmentsResponse.statusCode < 300
      ) {
        try {
          const assignmentBody = assignmentsResponse.json() as {
            data?: {
              assignments?: Array<{
                gameId: string;
                deviceId: string;
              }>;
            };
            assignments?: Array<{
              gameId: string;
              deviceId: string;
            }>;
          };

          const assignments =
            assignmentBody.data?.assignments ??
            assignmentBody.assignments ??
            [];

          assignedDeviceId =
            assignments.find(
              (item) =>
                String(item.gameId) === String(id.data),
            )?.deviceId ?? null;
        } catch {
          assignedDeviceId = null;
        }
      }

      const readinessGate =
        evaluatePregameReadinessGate({
          gameId: String(id.data),
          deviceId: assignedDeviceId,
        });

      if (!readinessGate.allowed) {
        return reply.code(409).send({
          error:
            readinessGate.reason ??
            "Pregame scoreboard readiness gate blocked game start.",
          code: "PREGAME_SCOREBOARD_READINESS_BLOCKED",
          readinessGate,
        });
      }
    }
`;

text =
  text.slice(0, globalAnchor) +
  block +
  text.slice(globalAnchor);

fs.writeFileSync(file, text);
NODE

mkdir -p "$(dirname "$TEST")"
cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 16.9 lifecycle readiness gate enforcement", () => {
  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/modules/games/routes.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("binds readiness enforcement to the real lifecycle route", () => {
    expect(route).toContain(
      'app.post("/games/:id/lifecycle"',
    );
    expect(route).toContain(
      'parsed.data.command === "startGame"',
    );
  });

  it("does not globally gate every startClock action", () => {
    expect(route).toContain(
      "PREGAME_SCOREBOARD_READINESS_GATE_16_9",
    );
    expect(route).toContain(
      "explicit startGame lifecycle command",
    );
  });

  it("resolves the assigned scoreboard and evaluates readiness", () => {
    expect(route).toContain(
      "/scoreboard-devices/assignments",
    );
    expect(route).toContain(
      "evaluatePregameReadinessGate",
    );
  });

  it("returns a conflict when the pregame gate blocks start", () => {
    expect(route).toContain(
      "PREGAME_SCOREBOARD_READINESS_BLOCKED",
    );
    expect(route).toContain(
      "reply.code(409)",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 16.9 lifecycle integration installed"
echo "============================================================"
echo
echo "Correct integration boundary:"
echo "  POST /games/:id/lifecycle"
echo "  command === startGame"
echo
echo "Why this boundary:"
echo "  - lifecycle.ts maps startGame -> startClock"
echo "  - engine.ts changes SCHEDULED -> LIVE on startClock"
echo "  - gating the explicit lifecycle command avoids blocking"
echo "    unrelated clock resumes/recovery paths"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 16.10 - Physical Control Resilience Acceptance / Closeout"
