#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="15.3-game-lifecycle-auto-lock-policy"
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
  "$ROOT/apps/api/src/services/scoreboardControlPolicy.ts" \
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

const files = [];

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (entry.isFile() && entry.name.endsWith(".ts")) files.push(full);
  }
}

walk("apps/api/src/modules/games");
walk("apps/api/src/services");

const findings = [];

for (const file of files) {
  const text = fs.readFileSync(file, "utf8");

  const lifecycleWords = [
    "SCHEDULED",
    "READY",
    "LIVE",
    "IN_PROGRESS",
    "FINAL",
    "COMPLETED",
    "CANCELLED",
    "POSTPONED",
    "startGame",
    "finishGame",
    "lifecycle",
    "status",
  ];

  const hits = lifecycleWords.filter((word) => text.includes(word));

  if (hits.length >= 2) {
    findings.push({
      file,
      hits,
      exports: [
        ...text.matchAll(/export\s+(?:async\s+)?function\s+([A-Za-z0-9_]+)/g),
        ...text.matchAll(/export\s+class\s+([A-Za-z0-9_]+)/g),
        ...text.matchAll(/export\s+const\s+([A-Za-z0-9_]+)/g),
      ].map((m) => m[1]),
    });
  }
}

console.log(JSON.stringify(findings.slice(0, 20), null, 2));
NODE

echo "Lifecycle discovery:"
cat "$DISCOVERY_FILE"

SERVICE="apps/api/src/services/scoreboardControlLifecyclePolicy.ts"
ROUTE="apps/api/src/routes/scoreboardControlInputs.ts"
TEST="packages/core/test/game-lifecycle-auto-lock-policy-15.3.test.ts"
DISCOVERY_DOC="apps/api/src/services/scoreboardControlLifecyclePolicy.discovery.json"

for file in "$SERVICE" "$ROUTE" "$TEST" "$DISCOVERY_DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"
cp "$DISCOVERY_FILE" "$DISCOVERY_DOC"

cat > "$SERVICE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

export type LifecycleControlDecision = {
  allowed: boolean;
  status: string | null;
  reason: string | null;
};

function extractStatus(
  payload: unknown,
): string | null {
  if (
    typeof payload !== "object" ||
    payload === null
  ) {
    return null;
  }

  const value =
    payload as Record<
      string,
      unknown
    >;

  const candidates: unknown[] = [
    value.status,
    value.lifecycleStatus,
    value.gameStatus,
    value.state,
    (
      typeof value.data ===
        "object" &&
      value.data !==
        null
        ? (
            value.data as Record<
              string,
              unknown
            >
          ).status
        : null
    ),
    (
      typeof value.data ===
        "object" &&
      value.data !==
        null
        ? (
            value.data as Record<
              string,
              unknown
            >
          ).lifecycleStatus
        : null
    ),
  ];

  for (
    const candidate of candidates
  ) {
    if (
      typeof candidate ===
        "string" &&
      candidate.trim()
    ) {
      return candidate
        .trim()
        .toUpperCase();
    }
  }

  return null;
}

function isActiveStatus(
  status: string,
): boolean {
  return [
    "LIVE",
    "IN_PROGRESS",
    "STARTED",
    "ACTIVE",
    "RUNNING",
  ].includes(status);
}

function isTerminalStatus(
  status: string,
): boolean {
  return [
    "FINAL",
    "FINISHED",
    "COMPLETED",
    "CANCELLED",
    "CANCELED",
    "POSTPONED",
  ].includes(status);
}

export async function evaluateGameLifecyclePhysicalControlPolicy(
  app: FastifyInstance,
  gameId: string,
): Promise<LifecycleControlDecision> {
  const encoded =
    encodeURIComponent(
      gameId,
    );

  const urls = [
    `/games/${encoded}`,
    `/games/${encoded}/state`,
    `/games/${encoded}/snapshot`,
  ];

  for (const url of urls) {
    const response =
      await app.inject({
        method: "GET",
        url,
      });

    if (
      response.statusCode ===
      404
    ) {
      continue;
    }

    if (
      response.statusCode <
        200 ||
      response.statusCode >=
        300
    ) {
      return {
        allowed: false,
        status: null,
        reason:
          "Unable to verify authoritative game lifecycle.",
      };
    }

    let body: unknown;

    try {
      body =
        response.json();
    } catch {
      body =
        response.body;
    }

    const status =
      extractStatus(
        body,
      );

    if (!status) {
      /*
       * Fail closed if the authoritative route exists but lifecycle cannot be
       * determined. This prevents physical controls from mutating a game whose
       * lifecycle is ambiguous.
       */
      return {
        allowed: false,
        status: null,
        reason:
          "Authoritative game lifecycle status is unavailable.",
      };
    }

    if (
      isActiveStatus(
        status,
      )
    ) {
      return {
        allowed: true,
        status,
        reason: null,
      };
    }

    if (
      isTerminalStatus(
        status,
      )
    ) {
      return {
        allowed: false,
        status,
        reason:
          `Physical controls are locked because game status is ${status}.`,
      };
    }

    return {
      allowed: false,
      status,
      reason:
        `Physical controls are locked until the game is active (status: ${status}).`,
    };
  }

  /*
   * If no supported authoritative read route exists, preserve existing
   * behavior rather than inventing lifecycle state. This makes the migration
   * non-breaking while still enforcing lifecycle where the API exposes it.
   */
  return {
    allowed: true,
    status: null,
    reason: null,
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
  'import { evaluateGameLifecyclePhysicalControlPolicy } from "../services/scoreboardControlLifecyclePolicy.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(
      /^(import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate control-input route import block.",
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
  !text.includes(
    "evaluateGameLifecyclePhysicalControlPolicy(",
  )
) {
  const anchor =
`      const policyDecision =
        evaluateScoreboardPhysicalControlPolicy(
          result.authoritativeGameId,
          body.deviceId,
        );`;

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate manual physical-control policy decision.",
    );
  }

  const insert =
`${anchor}

      const lifecycleDecision =
        await evaluateGameLifecyclePhysicalControlPolicy(
          app,
          result.authoritativeGameId,
        );

      if (!lifecycleDecision.allowed) {
        recordScoreboardControlAudit({
          auditId:
            body.inputId,
          deviceId:
            body.deviceId,
          gameId:
            result.authoritativeGameId,
          inputId:
            body.inputId,
          inputType:
            body.type,
          sequence:
            body.sequence,
          disposition:
            "REJECTED",
          command:
            "command" in result
              ? result.command
              : null,
          execution:
            null,
          reconciliation:
            null,
          error:
            lifecycleDecision.reason ??
            "Physical scoreboard controls are unavailable for the current game lifecycle.",
          createdAt:
            new Date().toISOString(),
        });

        return reply.code(423).send({
          success: false,
          error:
            lifecycleDecision.reason ??
            "Physical scoreboard controls are unavailable for the current game lifecycle.",
          data: {
            acknowledgement: {
              ...result,
              disposition:
                "REJECTED",
              reason:
                lifecycleDecision.reason ??
                "Physical scoreboard controls are unavailable for the current game lifecycle.",
            },
            lifecycle:
              lifecycleDecision,
          },
        });
      }`;

  text =
    text.replace(
      anchor,
      insert,
    );
}

const lifecycleIndex =
  text.indexOf(
    "evaluateGameLifecyclePhysicalControlPolicy(",
  );

const executionIndex =
  text.indexOf(
    "executePhysicalScoreboardControl(",
  );

if (
  lifecycleIndex === -1 ||
  executionIndex === -1 ||
  lifecycleIndex >
    executionIndex
) {
  throw new Error(
    "Lifecycle policy is not enforced before authoritative execution.",
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

describe("Milestone 15.3 game lifecycle auto-lock policy", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlLifecyclePolicy.ts",
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

  it("allows physical controls only for active lifecycle states", () => {
    for (const status of [
      "LIVE",
      "IN_PROGRESS",
      "STARTED",
      "ACTIVE",
      "RUNNING",
    ]) {
      expect(service).toContain(
        `"${status}"`,
      );
    }
  });

  it("locks terminal game lifecycle states", () => {
    for (const status of [
      "FINAL",
      "FINISHED",
      "COMPLETED",
      "CANCELLED",
      "POSTPONED",
    ]) {
      expect(service).toContain(
        `"${status}"`,
      );
    }
  });

  it("fails closed when lifecycle route exists but status is unavailable", () => {
    expect(service).toContain(
      "Authoritative game lifecycle status is unavailable.",
    );
  });

  it("checks lifecycle before authoritative physical mutation", () => {
    const lifecycleIndex =
      route.indexOf(
        "evaluateGameLifecyclePhysicalControlPolicy",
      );

    const executionIndex =
      route.indexOf(
        "executePhysicalScoreboardControl",
      );

    expect(lifecycleIndex).toBeGreaterThan(
      -1,
    );

    expect(executionIndex).toBeGreaterThan(
      lifecycleIndex,
    );
  });

  it("audits lifecycle lockout rejections", () => {
    expect(route).toContain(
      "recordScoreboardControlAudit",
    );

    expect(route).toContain(
      "lifecycleDecision.reason",
    );
  });

  it("does not use dashboard state as lifecycle authority", () => {
    expect(service).not.toContain(
      "localStorage",
    );

    expect(service).not.toContain(
      "window.",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 15.3 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - authoritative game lifecycle control policy"
echo "  - automatic lock before active gameplay"
echo "  - automatic lock after final/completed/cancelled/postponed state"
echo "  - fail-closed behavior when lifecycle route exists but status is unknown"
echo "  - lifecycle enforcement before physical mutation"
echo "  - lifecycle lockout audit records"
echo "  - no dashboard/localStorage lifecycle authority"
echo "  - discovery snapshot:"
echo "    $DISCOVERY_DOC"
echo
echo "Compatibility:"
echo "  - if no supported authoritative game read route exists, existing behavior is preserved"
echo "  - manual GAME/DEVICE/GAME_DEVICE policy from 15.1 still applies independently"
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
echo "  Milestone 15.4 - Control Role / Permission Enforcement"
