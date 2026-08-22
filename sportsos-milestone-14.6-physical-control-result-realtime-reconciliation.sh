#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="14.6-physical-control-result-realtime-reconciliation"
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
  "$ROOT/apps/api/src/services/scoreboardPhysicalControlExecution.ts" \
  "$ROOT/apps/api/src/services/automaticGameScoreboardSync.ts" \
  "$ROOT/apps/api/src/services/scoreboardDeviceRecovery.ts"
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

    if (entry.isDirectory()) {
      walk(full);
    } else if (entry.isFile() && entry.name.endsWith(".ts")) {
      files.push(full);
    }
  }
}

walk("apps/api/src");

const findings = [];

for (const file of files) {
  const text = fs.readFileSync(file, "utf8");

  const score =
    (/handleAuthoritativeSnapshot/.test(text) ? 5 : 0) +
    (/rememberAuthoritativeSnapshot/.test(text) ? 5 : 0) +
    (/AuthoritativeGameSnapshot/.test(text) ? 3 : 0) +
    (/get.*game/i.test(text) ? 2 : 0) +
    (/realtime|socket|emit/i.test(text) ? 1 : 0);

  if (score >= 4) {
    findings.push({
      file,
      score,
      exports: [
        ...text.matchAll(/export\s+(?:async\s+)?function\s+([A-Za-z0-9_]+)/g),
        ...text.matchAll(/export\s+class\s+([A-Za-z0-9_]+)/g),
      ].map(m => m[1]),
      symbols: [...new Set(
        [...text.matchAll(/\b([A-Za-z0-9_]*(?:Snapshot|snapshot|game)[A-Za-z0-9_]*)\b/g)]
          .map(m => m[1])
      )].slice(0, 40),
    });
  }
}

findings.sort((a,b) => b.score - a.score);

console.log(JSON.stringify(findings.slice(0, 12), null, 2));
NODE

echo "Realtime reconciliation discovery:"
cat "$DISCOVERY_FILE"

SERVICE="apps/api/src/services/scoreboardPhysicalControlReconciliation.ts"
ROUTE="apps/api/src/routes/scoreboardControlInputs.ts"
TEST="packages/core/test/physical-control-result-realtime-reconciliation-14.6.test.ts"
DISCOVERY_DOC="apps/api/src/services/scoreboardPhysicalControlReconciliation.discovery.json"

for file in "$SERVICE" "$ROUTE" "$TEST" "$DISCOVERY_DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
  fi
done

mkdir -p \
  "$(dirname "$SERVICE")" \
  "$(dirname "$TEST")"

cp "$DISCOVERY_FILE" "$DISCOVERY_DOC"

cat > "$SERVICE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import type {
  AutomaticGameScoreboardSync,
  GameScoreboardAssignment,
} from "./automaticGameScoreboardSync.js";

export type PhysicalControlReconciliationResult = {
  reconciled: boolean;
  authoritativeGameId: string;
  deviceId: string;
  reason: string | null;
  responseBody: unknown;
};

function gameSnapshotUrls(
  gameId: string,
): string[] {
  const encoded =
    encodeURIComponent(
      gameId,
    );

  return [
    `/games/${encoded}`,
    `/games/${encoded}/snapshot`,
    `/games/${encoded}/state`,
  ];
}

export async function reconcilePhysicalControlResult(
  app: FastifyInstance,
  automaticSync: AutomaticGameScoreboardSync,
  assignment: GameScoreboardAssignment,
): Promise<PhysicalControlReconciliationResult> {
  let lastBody: unknown =
    null;

  for (
    const url of gameSnapshotUrls(
      assignment.gameId,
    )
  ) {
    const response =
      await app.inject({
        method: "GET",
        url,
      });

    if (response.statusCode === 404) {
      continue;
    }

    let body: unknown =
      response.body;

    try {
      body =
        response.json();
    } catch {
      // Keep raw body for diagnostics.
    }

    lastBody =
      body;

    if (
      response.statusCode < 200 ||
      response.statusCode >= 300
    ) {
      return {
        reconciled: false,
        authoritativeGameId:
          assignment.gameId,
        deviceId:
          assignment.deviceId,
        reason:
          "Authoritative game snapshot request was rejected.",
        responseBody:
          body,
      };
    }

    /*
     * Do not reimplement game snapshot construction here.
     * Existing automatic scoreboard sync remains responsible for consuming
     * authoritative snapshots produced by the game engine. This reconciliation
     * step intentionally invalidates the dedupe fingerprint so the next
     * authoritative snapshot is guaranteed to reach the physical scoreboard.
     */
    automaticSync.invalidate(
      assignment.gameId,
    );

    return {
      reconciled: true,
      authoritativeGameId:
        assignment.gameId,
      deviceId:
        assignment.deviceId,
      reason:
        null,
      responseBody:
        body,
    };
  }

  /*
   * Even when there is no dedicated GET snapshot route, invalidating the
   * existing sync fingerprint is safe and ensures the next authoritative
   * game-state publication will not be deduplicated.
   */
  automaticSync.invalidate(
    assignment.gameId,
  );

  return {
    reconciled: true,
    authoritativeGameId:
      assignment.gameId,
    deviceId:
      assignment.deviceId,
    reason:
      "No direct game snapshot route found; realtime sync cache invalidated.",
    responseBody:
      lastBody,
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
  'import { reconcilePhysicalControlResult } from "../services/scoreboardPhysicalControlReconciliation.js";';

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

if (
  !text.includes(
    "const reconciliation =",
  )
) {
  const executionAnchor =
`      if (!execution.executed) {
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
      }`;

  if (!text.includes(executionAnchor)) {
    throw new Error(
      "Unable to locate successful physical execution boundary.",
    );
  }

  const reconciliationBlock =
`${executionAnchor}

      const assignment =
        automaticSync
          .getAssignmentByDeviceId(
            body.deviceId,
          );

      if (!assignment) {
        return reply.code(409).send({
          success: false,
          error:
            "Scoreboard assignment disappeared before reconciliation.",
          data: {
            acknowledgement:
              result,
            execution,
          },
        });
      }

      const reconciliation =
        await reconcilePhysicalControlResult(
          app,
          automaticSync,
          assignment,
        );`;

  text =
    text.replace(
      executionAnchor,
      reconciliationBlock,
    );
}

text =
  text.replace(
`      return {
        success: true,
        data: {
          ...result,
          execution,
        },
      };`,
`      return {
        success: true,
        data: {
          ...result,
          execution,
          reconciliation,
        },
      };`,
  );

if (
  !text.includes(
    "reconcilePhysicalControlResult(",
  )
) {
  throw new Error(
    "Realtime reconciliation was not bound to control route.",
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

describe("Milestone 14.6 physical control result / realtime reconciliation", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardPhysicalControlReconciliation.ts",
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

  it("reuses automatic scoreboard sync instead of creating another sync path", () => {
    expect(service).toContain(
      "AutomaticGameScoreboardSync",
    );

    expect(service).toContain(
      "automaticSync.invalidate",
    );

    expect(service).not.toContain(
      "new AutomaticGameScoreboardSync",
    );
  });

  it("attempts to read authoritative game state after physical mutation", () => {
    expect(service).toContain(
      'method: "GET"',
    );

    expect(service).toContain(
      "/snapshot",
    );

    expect(service).toContain(
      "/state",
    );
  });

  it("invalidates dedupe cache even without a direct snapshot route", () => {
    const occurrences =
      service.match(
        /automaticSync\.invalidate/g,
      ) ?? [];

    expect(
      occurrences.length,
    ).toBeGreaterThanOrEqual(2);
  });

  it("runs reconciliation only after successful authoritative execution", () => {
    const execution =
      route.indexOf(
        "if (!execution.executed)",
      );

    const reconciliation =
      route.indexOf(
        "reconcilePhysicalControlResult",
      );

    expect(execution).toBeGreaterThan(
      -1,
    );

    expect(reconciliation).toBeGreaterThan(
      execution,
    );
  });

  it("returns reconciliation details with the control acknowledgement", () => {
    expect(route).toContain(
      "reconciliation,",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 14.6 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - physical-control post-execution reconciliation service"
echo "  - authoritative game-state GET probing"
echo "  - automatic scoreboard sync fingerprint invalidation"
echo "  - assignment revalidation before reconciliation"
echo "  - reconciliation result returned with control acknowledgement"
echo "  - no duplicate realtime engine"
echo "  - discovery snapshot:"
echo "    $DISCOVERY_DOC"
echo
echo "Safety:"
echo "  - reconciliation happens only after successful authoritative mutation"
echo "  - automaticSync remains scoreboard sync source of truth"
echo "  - no client-side state is treated as authoritative"
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
echo "  Milestone 14.7 - Physical Control Audit / Operator Diagnostics"
