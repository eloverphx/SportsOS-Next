#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="15.1-physical-control-enable-lockout-policy"
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
  "$ROOT/packages/core/src" \
  "$ROOT/apps/api/src/routes/scoreboardControlInputs.ts" \
  "$ROOT/apps/api/src/services/automaticGameScoreboardSync.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

CORE="packages/core/src/scoreboard-control-policy.ts"
CORE_INDEX="packages/core/src/index.ts"
SERVICE="apps/api/src/services/scoreboardControlPolicy.ts"
ROUTE="apps/api/src/routes/scoreboardControlPolicy.ts"
CONTROL_ROUTE="apps/api/src/routes/scoreboardControlInputs.ts"
APP="apps/api/src/app.ts"
TEST="packages/core/test/physical-control-enable-lockout-policy-15.1.test.ts"

for file in \
  "$CORE" \
  "$CORE_INDEX" \
  "$SERVICE" \
  "$ROUTE" \
  "$CONTROL_ROUTE" \
  "$APP" \
  "$TEST"
do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
  fi
done

mkdir -p \
  "$(dirname "$CORE")" \
  "$(dirname "$SERVICE")" \
  "$(dirname "$ROUTE")" \
  "$(dirname "$TEST")"

cat > "$CORE" <<'EOF'
export type ScoreboardPhysicalControlPolicyMode =
  | "ENABLED"
  | "LOCKED";

export type ScoreboardPhysicalControlPolicyScope =
  | {
      scopeType: "GAME";
      gameId: string;
      deviceId: null;
    }
  | {
      scopeType: "DEVICE";
      gameId: null;
      deviceId: string;
    }
  | {
      scopeType: "GAME_DEVICE";
      gameId: string;
      deviceId: string;
    };

export type ScoreboardPhysicalControlPolicy =
  ScoreboardPhysicalControlPolicyScope & {
    mode:
      ScoreboardPhysicalControlPolicyMode;
    reason:
      string | null;
    updatedAt:
      string;
  };

export type ScoreboardPhysicalControlPolicyDecision = {
  allowed: boolean;
  effectiveMode:
    ScoreboardPhysicalControlPolicyMode;
  matchedPolicy:
    ScoreboardPhysicalControlPolicy | null;
  reason:
    string | null;
};
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "packages/core/src/index.ts";

let text =
  fs.readFileSync(file, "utf8");

const line =
  'export * from "./scoreboard-control-policy.js";';

if (!text.includes(line)) {
  if (
    text.length > 0 &&
    !text.endsWith("\n")
  ) {
    text += "\n";
  }

  text +=
    line +
    "\n";
}

fs.writeFileSync(file, text);
NODE

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

import type {
  ScoreboardPhysicalControlPolicy,
  ScoreboardPhysicalControlPolicyDecision,
  ScoreboardPhysicalControlPolicyMode,
  ScoreboardPhysicalControlPolicyScope,
} from "@sportsos/core";

type Store = {
  version: 1;
  policies: ScoreboardPhysicalControlPolicy[];
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
    "scoreboard-control-policy.json",
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
        parsed.policies,
      )
    ) {
      throw new Error(
        "Invalid physical control policy store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      policies: [],
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

  const temp =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    temp,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );

  fs.renameSync(
    temp,
    STORE_FILE,
  );
}

function keyOf(
  scope: ScoreboardPhysicalControlPolicyScope,
): string {
  return [
    scope.scopeType,
    scope.gameId ?? "",
    scope.deviceId ?? "",
  ].join(":");
}

export function setScoreboardPhysicalControlPolicy(
  scope: ScoreboardPhysicalControlPolicyScope,
  mode: ScoreboardPhysicalControlPolicyMode,
  reason?: string | null,
): ScoreboardPhysicalControlPolicy {
  const policy:
    ScoreboardPhysicalControlPolicy = {
      ...scope,
      mode,
      reason:
        reason?.trim() || null,
      updatedAt:
        new Date().toISOString(),
    };

  const key =
    keyOf(scope);

  store.policies =
    store.policies.filter(
      (item) =>
        keyOf(item) !== key,
    );

  store.policies.push(
    policy,
  );

  persistStore();

  return policy;
}

export function deleteScoreboardPhysicalControlPolicy(
  scope: ScoreboardPhysicalControlPolicyScope,
): boolean {
  const key =
    keyOf(scope);

  const before =
    store.policies.length;

  store.policies =
    store.policies.filter(
      (item) =>
        keyOf(item) !== key,
    );

  if (
    store.policies.length !==
    before
  ) {
    persistStore();
    return true;
  }

  return false;
}

export function listScoreboardPhysicalControlPolicies():
  ScoreboardPhysicalControlPolicy[] {
  return [...store.policies]
    .sort(
      (a, b) =>
        b.updatedAt.localeCompare(
          a.updatedAt,
        ),
    );
}

export function evaluateScoreboardPhysicalControlPolicy(
  gameId: string,
  deviceId: string,
): ScoreboardPhysicalControlPolicyDecision {
  const matches =
    store.policies.filter(
      (policy) =>
        (
          policy.scopeType ===
            "GAME_DEVICE" &&
          policy.gameId ===
            gameId &&
          policy.deviceId ===
            deviceId
        ) ||
        (
          policy.scopeType ===
            "GAME" &&
          policy.gameId ===
            gameId
        ) ||
        (
          policy.scopeType ===
            "DEVICE" &&
          policy.deviceId ===
            deviceId
        ),
    );

  const priority =
    (
      policy:
        ScoreboardPhysicalControlPolicy,
    ) =>
      policy.scopeType ===
        "GAME_DEVICE"
        ? 3
        : policy.scopeType ===
            "GAME"
          ? 2
          : 1;

  matches.sort(
    (a, b) =>
      priority(b) -
      priority(a),
  );

  const matched =
    matches[0] ??
    null;

  /*
   * Default is ENABLED to preserve existing deployed behavior.
   * A server-side LOCKED policy is authoritative and cannot be bypassed by
   * dashboard localStorage or client-side test overrides.
   */
  if (!matched) {
    return {
      allowed: true,
      effectiveMode:
        "ENABLED",
      matchedPolicy:
        null,
      reason:
        null,
    };
  }

  return {
    allowed:
      matched.mode ===
      "ENABLED",
    effectiveMode:
      matched.mode,
    matchedPolicy:
      matched,
    reason:
      matched.reason,
  };
}
EOF

cat > "$ROUTE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import type {
  ScoreboardPhysicalControlPolicyMode,
  ScoreboardPhysicalControlPolicyScope,
} from "@sportsos/core";

import {
  deleteScoreboardPhysicalControlPolicy,
  listScoreboardPhysicalControlPolicies,
  setScoreboardPhysicalControlPolicy,
} from "../services/scoreboardControlPolicy.js";

function parseScope(
  body: unknown,
): ScoreboardPhysicalControlPolicyScope | null {
  const value =
    body as {
      scopeType?: string;
      gameId?: string | null;
      deviceId?: string | null;
    };

  const gameId =
    value?.gameId?.trim() ||
    null;

  const deviceId =
    value?.deviceId?.trim() ||
    null;

  if (
    value?.scopeType ===
      "GAME" &&
    gameId
  ) {
    return {
      scopeType: "GAME",
      gameId,
      deviceId: null,
    };
  }

  if (
    value?.scopeType ===
      "DEVICE" &&
    deviceId
  ) {
    return {
      scopeType: "DEVICE",
      gameId: null,
      deviceId,
    };
  }

  if (
    value?.scopeType ===
      "GAME_DEVICE" &&
    gameId &&
    deviceId
  ) {
    return {
      scopeType:
        "GAME_DEVICE",
      gameId,
      deviceId,
    };
  }

  return null;
}

export async function registerScoreboardControlPolicyRoutes(
  app: FastifyInstance,
) {
  app.get(
    "/scoreboard-control-policies",
    async () => ({
      success: true,
      data: {
        policies:
          listScoreboardPhysicalControlPolicies(),
      },
    }),
  );

  app.put(
    "/scoreboard-control-policies",
    async (request, reply) => {
      const body =
        request.body as {
          scopeType?: string;
          gameId?: string | null;
          deviceId?: string | null;
          mode?: string;
          reason?: string | null;
        };

      const scope =
        parseScope(body);

      if (!scope) {
        return reply.code(400).send({
          success: false,
          error:
            "Invalid physical control policy scope.",
        });
      }

      if (
        body.mode !==
          "ENABLED" &&
        body.mode !==
          "LOCKED"
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Physical control policy mode must be ENABLED or LOCKED.",
        });
      }

      const policy =
        setScoreboardPhysicalControlPolicy(
          scope,
          body.mode as
            ScoreboardPhysicalControlPolicyMode,
          body.reason,
        );

      return {
        success: true,
        data: {
          policy,
        },
      };
    },
  );

  app.delete(
    "/scoreboard-control-policies",
    async (request, reply) => {
      const scope =
        parseScope(
          request.body,
        );

      if (!scope) {
        return reply.code(400).send({
          success: false,
          error:
            "Invalid physical control policy scope.",
        });
      }

      return {
        success: true,
        data: {
          deleted:
            deleteScoreboardPhysicalControlPolicy(
              scope,
            ),
        },
      };
    },
  );
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/app.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { registerScoreboardControlPolicyRoutes } from "./routes/scoreboardControlPolicy.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(
      /^(import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate API app import block.",
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
    "await registerScoreboardControlPolicyRoutes(app);",
  )
) {
  const idx =
    text.lastIndexOf(
      "return app;",
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate return app; in API app.",
    );
  }

  text =
    text.slice(0, idx) +
    "  await registerScoreboardControlPolicyRoutes(app);\n\n" +
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
  "apps/api/src/routes/scoreboardControlInputs.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { evaluateScoreboardPhysicalControlPolicy } from "../services/scoreboardControlPolicy.js";';

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
    "evaluateScoreboardPhysicalControlPolicy(",
  )
) {
  const anchor =
`      const execution =
        await executePhysicalScoreboardControl(
          app,
          result.authoritativeGameId,
          body,
        );`;

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate authoritative execution anchor.",
    );
  }

  const policyBlock =
`      const policyDecision =
        evaluateScoreboardPhysicalControlPolicy(
          result.authoritativeGameId,
          body.deviceId,
        );

      if (!policyDecision.allowed) {
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
            policyDecision.reason ??
            "Physical scoreboard controls are locked.",
          createdAt:
            new Date().toISOString(),
        });

        return reply.code(423).send({
          success: false,
          error:
            policyDecision.reason ??
            "Physical scoreboard controls are locked.",
          data: {
            acknowledgement: {
              ...result,
              disposition:
                "REJECTED",
              reason:
                policyDecision.reason ??
                "Physical scoreboard controls are locked.",
            },
            policy:
              policyDecision,
          },
        });
      }

${anchor}`;

  text =
    text.replace(
      anchor,
      policyBlock,
    );
}

if (
  !text.includes(
    "evaluateScoreboardPhysicalControlPolicy(",
  )
) {
  throw new Error(
    "Unable to bind physical control policy into input route.",
  );
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 15.1 physical control enable/lockout policy", () => {
  const policy = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlPolicy.ts",
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

  it("supports game device and game-device policy scopes", () => {
    for (const scope of [
      "GAME",
      "DEVICE",
      "GAME_DEVICE",
    ]) {
      expect(policy).toContain(
        `"${scope}"`,
      );
    }
  });

  it("supports enabled and locked modes", () => {
    expect(policy).toContain(
      '"ENABLED"',
    );

    expect(policy).toContain(
      '"LOCKED"',
    );
  });

  it("persists server-side policy state", () => {
    expect(policy).toContain(
      "scoreboard-control-policy.json",
    );

    expect(policy).toContain(
      "persistStore",
    );
  });

  it("checks policy before authoritative mutation execution", () => {
    const policyIndex =
      route.indexOf(
        "evaluateScoreboardPhysicalControlPolicy",
      );

    const executionIndex =
      route.indexOf(
        "executePhysicalScoreboardControl",
      );

    expect(policyIndex).toBeGreaterThan(
      -1,
    );

    expect(executionIndex).toBeGreaterThan(
      policyIndex,
    );
  });

  it("returns a locked response and writes an audit record", () => {
    expect(route).toContain(
      "reply.code(423)",
    );

    expect(route).toContain(
      "recordScoreboardControlAudit",
    );

    expect(route).toContain(
      "Physical scoreboard controls are locked.",
    );
  });

  it("does not reference localStorage or testing override authority", () => {
    expect(policy).not.toContain(
      "localStorage",
    );

    expect(policy).not.toContain(
      "testingOverride",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 15.1 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - server-authoritative physical control policy contract"
echo "  - GAME / DEVICE / GAME_DEVICE scopes"
echo "  - ENABLED / LOCKED modes"
echo "  - persistent policy store"
echo "  - GET/PUT/DELETE /scoreboard-control-policies"
echo "  - policy enforcement before authoritative game mutation"
echo "  - HTTP 423 Locked response for blocked physical controls"
echo "  - audit record for lockout rejection"
echo "  - no localStorage/testing override authority"
echo "  - Milestone 15.1 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run build --workspace @sportsos/core"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 15.2 - Operator Lockout Controls UI"
