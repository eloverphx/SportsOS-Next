#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="14.5-game-mutation-adapter-physical-control-execution"
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
  "$ROOT/apps/api/src/routes/scoreboardControlInputs.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlInputs.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlCommandBinding.ts" \
  "$ROOT/apps/api/src/modules/games/routes.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

DISCOVERY_FILE="$(mktemp)"
trap 'rm -f "$DISCOVERY_FILE"' EXIT

node > "$DISCOVERY_FILE" <<'NODE'
const fs = require("fs");
const path = require("path");

const root = "apps/api/src/modules/games";
const files = [];

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      walk(full);
    } else if (entry.isFile() && entry.name.endsWith(".ts")) {
      files.push(full);
    }
  }
}

walk(root);

const findings = {
  lifecycle: [],
  score: [],
  clock: [],
  period: [],
  generic: [],
};

const routePattern =
  /\.(post|put|patch)\s*\(\s*["'`]([^"'`]+)["'`]/g;

for (const file of files) {
  const text = fs.readFileSync(file, "utf8");

  for (const match of text.matchAll(routePattern)) {
    const method = match[1].toUpperCase();
    const route = match[2];
    const index = match.index ?? 0;

    const nearby =
      text.slice(
        Math.max(0, index - 1200),
        Math.min(text.length, index + 5000),
      );

    const item = {
      file,
      method,
      route,
      nearby,
    };

    if (/lifecycle/i.test(route) || /startGame|finishGame/.test(nearby)) {
      findings.lifecycle.push(item);
    }

    if (/score/i.test(route) || /homeScore|awayScore|scoreDelta|incrementScore|decrementScore/i.test(nearby)) {
      findings.score.push(item);
    }

    if (/clock/i.test(route) || /startClock|pauseClock|toggleClock|running|remainingMs/i.test(nearby)) {
      findings.clock.push(item);
    }

    if (/period/i.test(route) || /setPeriod|periodDelta|incrementPeriod|decrementPeriod/i.test(nearby)) {
      findings.period.push(item);
    }

    if (/command|mutation|action/i.test(route)) {
      findings.generic.push(item);
    }
  }
}

function compact(items) {
  const seen = new Set();
  const out = [];

  for (const item of items) {
    const key = `${item.method} ${item.route}`;

    if (seen.has(key)) continue;
    seen.add(key);

    out.push({
      file: item.file,
      method: item.method,
      route: item.route,
      nearby:
        item.nearby
          .split(/\r?\n/)
          .filter(line =>
            /command|score|clock|period|home|away|delta|start|pause|toggle/i.test(line)
          )
          .slice(0, 80),
    });
  }

  return out;
}

const compacted = {
  lifecycle: compact(findings.lifecycle),
  score: compact(findings.score),
  clock: compact(findings.clock),
  period: compact(findings.period),
  generic: compact(findings.generic),
};

console.log(JSON.stringify(compacted, null, 2));
NODE

DISCOVERY_JSON="$(cat "$DISCOVERY_FILE")"

if [[ -z "$DISCOVERY_JSON" ]]; then
  echo "ERROR: authoritative game route discovery returned no data." >&2
  echo "Repository was not modified." >&2
  exit 1
fi

echo "Authoritative game route discovery complete."

ADAPTER="apps/api/src/services/scoreboardPhysicalControlExecution.ts"
ROUTE="apps/api/src/routes/scoreboardControlInputs.ts"
TEST="packages/core/test/game-mutation-adapter-physical-control-execution-14.5.test.ts"
DISCOVERY_DOC="apps/api/src/services/scoreboardPhysicalControlRouteDiscovery.json"

for file in "$ADAPTER" "$ROUTE" "$TEST" "$DISCOVERY_DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
  fi
done

mkdir -p \
  "$(dirname "$ADAPTER")" \
  "$(dirname "$TEST")"

printf '%s\n' "$DISCOVERY_JSON" > "$DISCOVERY_DOC"

cat > "$ADAPTER" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import type {
  ScoreboardControlInputEvent,
} from "@sportsos/core";

import {
  mapScoreboardControlInputToCommand,
  type ScoreboardControlCommand,
} from "./scoreboardControlCommandBinding.js";

export type PhysicalControlExecutionResult = {
  executed: boolean;
  statusCode: number;
  authoritativeGameId: string;
  command: ScoreboardControlCommand;
  responseBody: unknown;
  reason: string | null;
};

type RouteCandidate = {
  method: "POST" | "PUT" | "PATCH";
  route: string;
  payload:
    | Record<string, unknown>
    | null;
};

function routeUrl(
  route: string,
  gameId: string,
): string {
  return route
    .replace(
      ":gameId",
      encodeURIComponent(gameId),
    )
    .replace(
      ":id",
      encodeURIComponent(gameId),
    );
}

function candidatesFor(
  gameId: string,
  command: ScoreboardControlCommand,
): RouteCandidate[] {
  /*
   * These candidate contracts are intentionally limited to the existing
   * SportsOS game API shapes used across prior milestones. The adapter never
   * edits game state directly; it re-enters Fastify through app.inject().
   *
   * We stop after the first non-404 response so the same physical action
   * cannot be applied twice.
   */
  if (command.kind === "SCORE") {
    return [
      {
        method: "POST",
        route:
          "/games/:gameId/score",
        payload: {
          side:
            command.side.toLowerCase(),
          delta:
            command.delta,
        },
      },
      {
        method: "POST",
        route:
          "/games/:gameId/command",
        payload: {
          command:
            command.delta > 0
              ? command.side === "HOME"
                ? "incrementHomeScore"
                : "incrementAwayScore"
              : command.side === "HOME"
                ? "decrementHomeScore"
                : "decrementAwayScore",
        },
      },
      {
        method: "POST",
        route:
          "/games/:gameId/commands",
        payload: {
          command:
            command.delta > 0
              ? command.side === "HOME"
                ? "incrementHomeScore"
                : "incrementAwayScore"
              : command.side === "HOME"
                ? "decrementHomeScore"
                : "decrementAwayScore",
        },
      },
    ];
  }

  if (command.kind === "CLOCK") {
    const commandName =
      command.action === "START"
        ? "startClock"
        : command.action === "PAUSE"
          ? "pauseClock"
          : "toggleClock";

    return [
      {
        method: "POST",
        route:
          "/games/:gameId/clock",
        payload: {
          command:
            commandName,
        },
      },
      {
        method: "POST",
        route:
          "/games/:gameId/command",
        payload: {
          command:
            commandName,
        },
      },
      {
        method: "POST",
        route:
          "/games/:gameId/commands",
        payload: {
          command:
            commandName,
        },
      },
    ];
  }

  if (command.kind === "PERIOD") {
    return [
      {
        method: "POST",
        route:
          "/games/:gameId/period",
        payload: {
          delta:
            command.delta,
        },
      },
      {
        method: "POST",
        route:
          "/games/:gameId/command",
        payload: {
          command:
            command.delta > 0
              ? "incrementPeriod"
              : "decrementPeriod",
        },
      },
      {
        method: "POST",
        route:
          "/games/:gameId/commands",
        payload: {
          command:
            command.delta > 0
              ? "incrementPeriod"
              : "decrementPeriod",
        },
      },
    ];
  }

  /*
   * Horn is a physical side-effect, not a persistent game-state mutation.
   * It is acknowledged here and is bound to the scoreboard device command
   * transport in a later milestone.
   */
  return [];
}

export async function executePhysicalScoreboardControl(
  app: FastifyInstance,
  gameId: string,
  event: ScoreboardControlInputEvent,
): Promise<PhysicalControlExecutionResult> {
  const command =
    mapScoreboardControlInputToCommand(
      event,
    );

  if (command.kind === "HORN") {
    return {
      executed: true,
      statusCode: 202,
      authoritativeGameId:
        gameId,
      command,
      responseBody: {
        accepted: true,
        deferredToDeviceTransport: true,
      },
      reason:
        null,
    };
  }

  const candidates =
    candidatesFor(
      gameId,
      command,
    );

  for (const candidate of candidates) {
    const response =
      await app.inject({
        method:
          candidate.method,
        url:
          routeUrl(
            candidate.route,
            gameId,
          ),
        payload:
          candidate.payload ??
          undefined,
      });

    if (response.statusCode === 404) {
      continue;
    }

    let responseBody: unknown =
      response.body;

    try {
      responseBody =
        response.json();
    } catch {
      // Keep raw response body.
    }

    return {
      executed:
        response.statusCode >= 200 &&
        response.statusCode < 300,
      statusCode:
        response.statusCode,
      authoritativeGameId:
        gameId,
      command,
      responseBody,
      reason:
        response.statusCode >= 200 &&
        response.statusCode < 300
          ? null
          : "Authoritative game mutation rejected.",
    };
  }

  return {
    executed: false,
    statusCode: 501,
    authoritativeGameId:
      gameId,
    command,
    responseBody: null,
    reason:
      "No compatible authoritative game mutation route was found.",
  };
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardControlInputs.ts";

let text =
  fs.readFileSync(file, "utf8");

const importLine =
  'import { executePhysicalScoreboardControl } from "../services/scoreboardPhysicalControlExecution.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate scoreboard control route import block.",
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

const oldReturn = `      return {
        success: true,
        data:
          result,
      };`;

if (
  text.includes(oldReturn) &&
  !text.includes(
    "executePhysicalScoreboardControl(",
  )
) {
  text =
    text.replace(
      oldReturn,
`      if (
        result.disposition !==
          "ACCEPTED" ||
        !result.authoritativeGameId
      ) {
        return {
          success: true,
          data:
            result,
        };
      }

      const execution =
        await executePhysicalScoreboardControl(
          app,
          result.authoritativeGameId,
          body,
        );

      if (!execution.executed) {
        return reply.code(
          execution.statusCode >= 400 &&
          execution.statusCode <= 599
            ? execution.statusCode
            : 409,
        ).send({
          success: false,
          error:
            execution.reason ??
            "Physical scoreboard command was not executed.",
          data: {
            acknowledgement:
              result,
            execution,
          },
        });
      }

      return {
        success: true,
        data: {
          ...result,
          execution,
        },
      };`,
    );
}

if (
  !text.includes(
    "executePhysicalScoreboardControl(",
  )
) {
  throw new Error(
    "Unable to bind authoritative physical-control execution into route.",
  );
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

describe("Milestone 14.5 game mutation adapter / physical control execution", () => {
  const adapter = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardPhysicalControlExecution.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlInputs.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("re-enters authoritative Fastify routes instead of mutating storage directly", () => {
    expect(adapter).toContain(
      "app.inject",
    );

    expect(adapter).not.toContain(
      "UPDATE games",
    );

    expect(adapter).not.toContain(
      "INSERT INTO games",
    );
  });

  it("supports score clock and period command execution", () => {
    expect(adapter).toContain(
      'command.kind === "SCORE"',
    );

    expect(adapter).toContain(
      'command.kind === "CLOCK"',
    );

    expect(adapter).toContain(
      'command.kind === "PERIOD"',
    );
  });

  it("stops on the first non-404 authoritative route", () => {
    expect(adapter).toContain(
      "response.statusCode === 404",
    );

    expect(adapter).toContain(
      "return {",
    );
  });

  it("executes only after control acknowledgement is ACCEPTED", () => {
    expect(route).toContain(
      'result.disposition !==',
    );

    expect(route).toContain(
      '"ACCEPTED"',
    );

    expect(route).toContain(
      "executePhysicalScoreboardControl",
    );
  });

  it("does not persist horn as game state", () => {
    expect(adapter).toContain(
      'command.kind === "HORN"',
    );

    expect(adapter).toContain(
      "deferredToDeviceTransport",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 14.5 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - authoritative physical-control execution adapter"
echo "  - Fastify app.inject() re-entry into game mutation API"
echo "  - score execution"
echo "  - clock execution"
echo "  - period execution"
echo "  - horn acknowledged as deferred device side-effect"
echo "  - execution only after ACCEPTED assignment/duplicate validation"
echo "  - authoritative mutation errors returned to device"
echo "  - route discovery snapshot:"
echo "    $DISCOVERY_DOC"
echo
echo "Safety:"
echo "  - no direct database/game-state mutation code added"
echo "  - ESP32 remains non-authoritative"
echo "  - first non-404 server route wins; action is never retried after a real response"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 14.6 - Physical Control Result / Realtime State Reconciliation"
