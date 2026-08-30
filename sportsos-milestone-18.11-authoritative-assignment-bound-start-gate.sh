#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.11-authoritative-assignment-bound-start-gate-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

ROUTES="apps/api/src/modules/games/routes.ts"
TEST="packages/core/test/authoritative-assignment-bound-start-gate-18.11.test.ts"
DOC="docs/GAME-DAY-DEPLOYMENT-ACCEPTANCE.md"

for required in \
  ".git" \
  "$ROUTES" \
  "apps/api/src/services/gameStartPreflightGuard.ts" \
  "apps/api/src/services/scoreboardPregameReadinessGate.ts" \
  "apps/api/src/services/gameStartPreflightOverride.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$ROUTES" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/modules/games/routes.ts";
let text = fs.readFileSync(file, "utf8");

const routeStart = text.indexOf('app.post("/games/:id/lifecycle"');
const nextRoute = text.indexOf('\n  app.post("/games/:id/broadcast"', routeStart);

if (routeStart === -1 || nextRoute === -1) {
  throw new Error("Unable to locate lifecycle route boundaries.");
}

let region = text.slice(routeStart, nextRoute);

const oldGateMarker = "// PREGAME_SCOREBOARD_READINESS_GATE_16_9";
const oldGateStart = region.indexOf(oldGateMarker);

if (oldGateStart !== -1) {
  const replayResume = region.indexOf(
    '        if (!game) return reply.code(404).send({ error: "Game not found" });',
    oldGateStart,
  );

  if (replayResume === -1) {
    throw new Error("Unable to remove old post-mutation gate.");
  }

  region =
    region.slice(0, oldGateStart) +
    region.slice(replayResume);
}

if (!region.includes("AUTHORITATIVE_ASSIGNMENT_BOUND_START_GATE_18_11")) {
  const resultMarker = `    let result;
    try {
      result = await applyGameScoringAction(`;

  const resultIndex = region.indexOf(resultMarker);

  if (resultIndex === -1) {
    throw new Error("Unable to locate applyGameScoringAction boundary.");
  }

  const gate = `    // AUTHORITATIVE_ASSIGNMENT_BOUND_START_GATE_18_11
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
                String(item.gameId) ===
                String(id.data),
            )?.deviceId ?? null;
        } catch {
          assignedDeviceId = null;
        }
      }

      const gameStartPreflight =
        evaluateGameStartPreflight(
          String(id.data),
          assignedDeviceId,
        );

      if (!gameStartPreflight.allowed) {
        const activeEmergencyOverride =
          getActiveGameStartPreflightOverride(
            String(id.data),
            assignedDeviceId ?? "",
          );

        if (!activeEmergencyOverride) {
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

  region =
    region.slice(0, resultIndex) +
    gate +
    region.slice(resultIndex);
}

const markerIndex = region.indexOf("AUTHORITATIVE_ASSIGNMENT_BOUND_START_GATE_18_11");
const mutationIndex = region.indexOf("result = await applyGameScoringAction(");

if (markerIndex === -1 || mutationIndex === -1 || markerIndex > mutationIndex) {
  throw new Error("18.11 gate is not before lifecycle mutation.");
}

if (!region.includes(`evaluateGameStartPreflight(
          String(id.data),
          assignedDeviceId,`)) {
  throw new Error("Current assigned device is not passed to preflight guard.");
}

if (region.slice(mutationIndex).includes(oldGateMarker)) {
  throw new Error("Stale post-mutation gate still exists.");
}

text =
  text.slice(0, routeStart) +
  region +
  text.slice(nextRoute);

fs.writeFileSync(file, text);

console.log(
  "18.11 authoritative assignment-bound start gate installed.",
);
NODE

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 18.11 authoritative assignment-bound start gate", () => {
  const routes = fs.readFileSync(
    new URL(
      "../../../apps/api/src/modules/games/routes.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("places the gate before lifecycle mutation", () => {
    const gate =
      routes.indexOf(
        "AUTHORITATIVE_ASSIGNMENT_BOUND_START_GATE_18_11",
      );

    const mutation =
      routes.indexOf(
        "result = await applyGameScoringAction(",
      );

    expect(gate).toBeGreaterThanOrEqual(0);
    expect(mutation).toBeGreaterThan(gate);
  });

  it("passes current assignment to preflight guard", () => {
    expect(routes).toContain(
      `evaluateGameStartPreflight(
          String(id.data),
          assignedDeviceId,`,
    );
  });

  it("binds emergency override to current assignment", () => {
    expect(routes).toContain(
      `getActiveGameStartPreflightOverride(
            String(id.data),
            assignedDeviceId ??`,
    );
  });

  it("keeps readiness enforcement before mutation", () => {
    const readiness =
      routes.indexOf(
        "evaluatePregameReadinessGate({",
      );

    const mutation =
      routes.indexOf(
        "result = await applyGameScoringAction(",
      );

    expect(readiness).toBeGreaterThanOrEqual(0);
    expect(mutation).toBeGreaterThan(readiness);
  });
});
EOF

cat >> "$DOC" <<'EOF'

## Milestone 18.11 corrective closeout

The authoritative `startGame` boundary now resolves the current scoreboard assignment before lifecycle mutation and passes that device ID into the game-day preflight guard.

This closes two gaps: device swaps now invalidate an older preflight, and preflight/readiness rejection occurs before `applyGameScoringAction()` can mutate lifecycle state. Emergency override lookup is also scoped to the currently assigned device.
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 18.11 installed"
echo "============================================================"
echo
echo "Fixed:"
echo "  - current assignment resolved before start authorization"
echo "  - assignedDeviceId passed to preflight guard"
echo "  - device swap invalidation is enforced"
echo "  - emergency override bound to current device"
echo "  - preflight/readiness gates moved before lifecycle mutation"
echo "  - stale post-mutation gate removed"
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
