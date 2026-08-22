#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.1-game-day-hardware-preflight-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "package.json" \
  "apps/api/src/services/scoreboardDeviceCommissioning.ts" \
  "apps/api/src/services/scoreboardControlReadiness.ts" \
  "apps/api/src/services/scoreboardReadinessReliability.ts" \
  "apps/api/src/services/scoreboardCommissioningSelfTest.ts" \
  "apps/api/src/routes/scoreboardDeviceCommissioning.ts" \
  "apps/api/src/modules/games/routes.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

SERVICE="apps/api/src/services/gameDayHardwarePreflight.ts"
ROUTE="apps/api/src/routes/gameDayHardwarePreflight.ts"
TEST="packages/core/test/game-day-hardware-preflight-18.1.test.ts"
DOC="docs/GAME-DAY-HARDWARE-PREFLIGHT.md"

for file in "$SERVICE" "$ROUTE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$ROUTE")" "$(dirname "$TEST")" "$(dirname "$DOC")"

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

import {
  getScoreboardCommissioning,
} from "./scoreboardDeviceCommissioning.js";

import {
  evaluateScoreboardControlReadiness,
} from "./scoreboardControlReadiness.js";

import {
  listScoreboardReliabilityClassifications,
} from "./scoreboardReadinessReliability.js";

import {
  latestCommissioningSelfTest,
} from "./scoreboardCommissioningSelfTest.js";

export type GameDayPreflightCheck = {
  id:
    | "COMMISSIONING"
    | "HEARTBEAT"
    | "RELIABILITY"
    | "SELF_TEST";
  passed: boolean;
  detail: string;
};

export type GameDayHardwarePreflight = {
  preflightId: string;
  gameId: string;
  deviceId: string;
  status:
    | "PASS"
    | "FAIL";
  checks: GameDayPreflightCheck[];
  startedAt: string;
  completedAt: string;
};

type Store = {
  version: 1;
  preflights:
    GameDayHardwarePreflight[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(
    process.cwd(),
    "data",
  );

const STORE_FILE =
  path.join(
    DATA_DIR,
    "game-day-hardware-preflights.json",
  );

let store =
  loadStore();

function loadStore(): Store {
  try {
    const parsed =
      JSON.parse(
        fs.readFileSync(
          STORE_FILE,
          "utf8",
        ),
      ) as Store;

    if (
      parsed.version !== 1 ||
      !Array.isArray(
        parsed.preflights,
      )
    ) {
      throw new Error(
        "Invalid game-day preflight store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      preflights: [],
    };
  }
}

function persistStore(): void {
  fs.mkdirSync(
    DATA_DIR,
    {
      recursive: true,
    },
  );

  const temporary =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    temporary,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );

  fs.renameSync(
    temporary,
    STORE_FILE,
  );
}

export async function runGameDayHardwarePreflight(input: {
  gameId: string;
  deviceId: string;
}): Promise<GameDayHardwarePreflight> {
  const startedAt =
    new Date().toISOString();

  const commissioning =
    getScoreboardCommissioning(
      input.deviceId,
    );

  const readiness =
    await evaluateScoreboardControlReadiness(
      input.deviceId,
    );

  const reliability =
    listScoreboardReliabilityClassifications()
      .find(
        (item) =>
          item.deviceId ===
          input.deviceId,
      );

  const selfTest =
    latestCommissioningSelfTest(
      input.deviceId,
    );

  const checks:
    GameDayPreflightCheck[] = [
      {
        id:
          "COMMISSIONING",
        passed:
          commissioning?.status ===
          "GAME_READY",
        detail:
          commissioning?.status ===
            "GAME_READY"
            ? "Device commissioning status is GAME_READY."
            : `Commissioning status is ${commissioning?.status ?? "MISSING"}.`,
      },
      {
        id:
          "HEARTBEAT",
        passed:
          readiness.ready,
        detail:
          readiness.ready
            ? `Heartbeat age ${readiness.heartbeatAgeMs ?? 0}ms is within the ${readiness.thresholdMs}ms threshold.`
            : readiness.reason ??
              "Device heartbeat readiness failed.",
      },
      {
        id:
          "RELIABILITY",
        passed:
          Boolean(
            reliability &&
            (
              reliability.risk ===
                "HEALTHY" ||
              reliability.risk ===
                "WATCH"
            ),
          ),
        detail:
          reliability
            ? `Reliability classification is ${reliability.risk}.`
            : "Reliability classification is unavailable.",
      },
      {
        id:
          "SELF_TEST",
        passed:
          selfTest?.status ===
          "PASS",
        detail:
          selfTest?.status ===
            "PASS"
            ? `Latest ${selfTest.source} self-test passed at ${selfTest.completedAt}.`
            : selfTest
              ? `Latest ${selfTest.source} self-test status is ${selfTest.status}.`
              : "No commissioning self-test result is available.",
      },
    ];

  const completedAt =
    new Date().toISOString();

  const result:
    GameDayHardwarePreflight = {
      preflightId:
        `preflight-${input.gameId}-${input.deviceId}-${Date.now()}`,
      gameId:
        input.gameId,
      deviceId:
        input.deviceId,
      status:
        checks.every(
          (check) =>
            check.passed,
        )
          ? "PASS"
          : "FAIL",
      checks,
      startedAt,
      completedAt,
    };

  store.preflights.push(
    result,
  );

  if (
    store.preflights.length >
    2000
  ) {
    store.preflights =
      store.preflights.slice(
        -2000,
      );
  }

  persistStore();

  return result;
}

export function latestGameDayHardwarePreflight(
  gameId: string,
  deviceId?: string,
): GameDayHardwarePreflight | null {
  return (
    [...store.preflights]
      .reverse()
      .find(
        (item) =>
          item.gameId ===
            gameId &&
          (
            !deviceId ||
            item.deviceId ===
              deviceId
          ),
      ) ??
    null
  );
}

export function listGameDayHardwarePreflights(
  gameId?: string,
): GameDayHardwarePreflight[] {
  return [...store.preflights]
    .filter(
      (item) =>
        !gameId ||
        item.gameId ===
          gameId,
    )
    .sort(
      (a, b) =>
        b.completedAt.localeCompare(
          a.completedAt,
        ),
    );
}
EOF

cat > "$ROUTE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import {
  latestGameDayHardwarePreflight,
  listGameDayHardwarePreflights,
  runGameDayHardwarePreflight,
} from "../services/gameDayHardwarePreflight.js";

type Assignment = {
  gameId: string;
  deviceId: string;
};

async function assignedDeviceForGame(
  app: FastifyInstance,
  gameId: string,
): Promise<string | null> {
  const response =
    await app.inject({
      method:
        "GET",
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
          String(
            item.gameId,
          ) ===
          String(
            gameId,
          ),
      )?.deviceId ??
      null
    );
  } catch {
    return null;
  }
}

export async function registerGameDayHardwarePreflightRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.post(
    "/game-day-hardware-preflight/:gameId",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const gameId =
        params.gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const deviceId =
        await assignedDeviceForGame(
          app,
          gameId,
        );

      if (!deviceId) {
        return reply.code(409).send({
          success: false,
          error:
            "No scoreboard device is assigned to this game.",
        });
      }

      const preflight =
        await runGameDayHardwarePreflight({
          gameId,
          deviceId,
        });

      return reply
        .code(
          preflight.status ===
            "PASS"
            ? 200
            : 409,
        )
        .send({
          success:
            preflight.status ===
            "PASS",
          data: {
            preflight,
          },
          error:
            preflight.status ===
              "PASS"
              ? undefined
              : "Game-day hardware preflight failed.",
        });
    },
  );

  app.get(
    "/game-day-hardware-preflight/:gameId/latest",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const gameId =
        params.gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data: {
          preflight:
            latestGameDayHardwarePreflight(
              gameId,
            ),
        },
      };
    },
  );

  app.get(
    "/game-day-hardware-preflight/:gameId/history",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const gameId =
        params.gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data: {
          preflights:
            listGameDayHardwarePreflights(
              gameId,
            ),
        },
      };
    },
  );
}
EOF

# Discover API registration file safely.
REGISTRATION_FILE="$(
node <<'NODE'
const fs = require("fs");
const path = require("path");

const root =
  "apps/api/src";

const files = [];

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full =
      path.join(
        dir,
        entry.name,
      );

    if (entry.isDirectory()) {
      walk(full);
    } else if (
      entry.isFile() &&
      entry.name.endsWith(".ts")
    ) {
      files.push(full);
    }
  }
}

walk(root);

const candidates = [];

for (const file of files) {
  const text =
    fs.readFileSync(
      file,
      "utf8",
    );

  let score = 0;

  if (
    /registerScoreboardDeviceCommissioningRoutes/.test(
      text,
    )
  ) score += 30;

  if (
    /scoreboardDeviceCommissioning/.test(
      text,
    )
  ) score += 20;

  if (
    /app\.register|fastify\.register/.test(
      text,
    )
  ) score += 5;

  if (
    /buildApp/.test(
      text,
    )
  ) score += 3;

  if (score > 0) {
    candidates.push({
      file,
      score,
    });
  }
}

candidates.sort(
  (a, b) =>
    b.score -
      a.score ||
    a.file.localeCompare(
      b.file,
    ),
);

if (!candidates.length) {
  process.exit(2);
}

console.log(
  candidates[0].file,
);
NODE
)" || {
  echo "ERROR: unable to discover API route registration file." >&2
  echo "Repository was not modified beyond new 18.1 files." >&2
  exit 1
}

mkdir -p "$BACKUP/$(dirname "$REGISTRATION_FILE")"
cp -a "$REGISTRATION_FILE" "$BACKUP/$REGISTRATION_FILE"

node - "$REGISTRATION_FILE" <<'NODE'
const fs = require("fs");
const path = require("path");

const file =
  process.argv[2];

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  text.includes(
    "registerGameDayHardwarePreflightRoutes"
  )
) {
  console.log(
    "18.1 routes already registered.",
  );
  process.exit(0);
}

const target =
  path.resolve(
    "apps/api/src/routes/gameDayHardwarePreflight.ts",
  );

const dir =
  path.dirname(
    path.resolve(file),
  );

let relative =
  path.relative(
    dir,
    target,
  ).replace(
    /\\/g,
    "/",
  );

relative =
  relative.replace(
    /\.ts$/,
    ".js",
  );

if (
  !relative.startsWith(
    ".",
  )
) {
  relative =
    `./${relative}`;
}

const importLine =
  `import { registerGameDayHardwarePreflightRoutes } from "${relative}";\n`;

const imports =
  text.match(
    /^(?:import[\s\S]*?;\n)+/,
  );

if (!imports) {
  throw new Error(
    "Unable to locate API imports.",
  );
}

text =
  text.replace(
    imports[0],
    imports[0] +
      importLine,
  );

const known =
  [
    "registerScoreboardDeviceCommissioningRoutes",
    "registerScoreboardControlPolicyRoutes",
  ];

let insertionPoint =
  -1;

for (const symbol of known) {
  const regex =
    new RegExp(
      `(?:await\\s+)?(?:app|fastify)\\.register\\(\\s*${symbol}[\\s\\S]*?\\);`,
      "g",
    );

  const matches =
    [...text.matchAll(regex)];

  if (matches.length) {
    const last =
      matches[
        matches.length - 1
      ];

    insertionPoint =
      Math.max(
        insertionPoint,
        last.index +
          last[0].length,
      );
  }
}

if (
  insertionPoint === -1
) {
  const registerMatches =
    [
      ...text.matchAll(
        /(?:await\s+)?(?:app|fastify)\.register\([\s\S]*?\);/g,
      ),
    ];

  if (
    registerMatches.length
  ) {
    const last =
      registerMatches[
        registerMatches.length -
        1
      ];

    insertionPoint =
      last.index +
      last[0].length;
  }
}

if (
  insertionPoint === -1
) {
  throw new Error(
    "Unable to locate API registration insertion point.",
  );
}

const receiver =
  text.slice(
    Math.max(
      0,
      insertionPoint -
        500,
    ),
    insertionPoint,
  ).includes(
    "fastify.register",
  )
    ? "fastify"
    : "app";

text =
  text.slice(
    0,
    insertionPoint,
  ) +
  `\n  await ${receiver}.register(registerGameDayHardwarePreflightRoutes);` +
  text.slice(
    insertionPoint,
  );

fs.writeFileSync(
  file,
  text,
);

console.log(
  `Registered 18.1 routes in ${file}`,
);
NODE

cat > "$DOC" <<'EOF'
# SportsOS Game-Day Hardware Preflight

Milestone 18.1 introduces a fresh, game-specific hardware preflight.

Commissioning `GAME_READY` status proves that the scoreboard was installed correctly. A game-day preflight proves that the assigned scoreboard is still ready immediately before the game.

The preflight evaluates:

- commissioning status is `GAME_READY`
- device heartbeat is currently fresh
- reliability classification is `HEALTHY` or `WATCH`
- latest commissioning hardware self-test is `PASS`

Each run is persisted with its game ID, device ID, individual check results, timestamps, and final PASS/FAIL result.

API:

- `POST /game-day-hardware-preflight/:gameId`
- `GET /game-day-hardware-preflight/:gameId/latest`
- `GET /game-day-hardware-preflight/:gameId/history`

A failed preflight returns HTTP 409. The preflight does not modify game state.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.1 game-day hardware preflight", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameDayHardwarePreflight.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/gameDayHardwarePreflight.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("requires commissioning game-ready status", () => {
    expect(service).toContain(
      '"GAME_READY"',
    );

    expect(service).toContain(
      '"COMMISSIONING"',
    );
  });

  it("requires fresh heartbeat readiness", () => {
    expect(service).toContain(
      "evaluateScoreboardControlReadiness",
    );

    expect(service).toContain(
      '"HEARTBEAT"',
    );
  });

  it("requires acceptable reliability state", () => {
    expect(service).toContain(
      "listScoreboardReliabilityClassifications",
    );

    expect(service).toContain(
      '"HEALTHY"',
    );

    expect(service).toContain(
      '"WATCH"',
    );
  });

  it("requires a passing hardware self-test", () => {
    expect(service).toContain(
      "latestCommissioningSelfTest",
    );

    expect(service).toContain(
      '"SELF_TEST"',
    );
  });

  it("persists game-specific preflight history", () => {
    expect(service).toContain(
      "game-day-hardware-preflights.json",
    );

    expect(service).toContain(
      "preflightId",
    );
  });

  it("returns conflict when preflight fails", () => {
    expect(route).toContain(
      "reply",
    );

    expect(route).toContain(
      "409",
    );

    expect(route).toContain(
      "Game-day hardware preflight failed.",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 18.1 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - game-specific hardware preflight sessions"
echo "  - GAME_READY commissioning verification"
echo "  - live heartbeat readiness verification"
echo "  - reliability classification verification"
echo "  - latest hardware self-test verification"
echo "  - persistent preflight history"
echo "  - PASS / FAIL preflight result"
echo "  - POST latest/history API"
echo "  - HTTP 409 on failed preflight"
echo "  - Milestone 18.1 regression tests"
echo
echo "API registration:"
echo "  $REGISTRATION_FILE"
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
echo "  Milestone 18.2 - Game-Day Preflight Dashboard / Operator Workflow"
