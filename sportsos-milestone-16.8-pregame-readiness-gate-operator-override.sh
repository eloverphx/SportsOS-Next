#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-16.8-pregame-readiness-gate-operator-override-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/services/scoreboardReadinessReliability.ts" \
  "$ROOT/apps/api/src/services/automaticGameScoreboardSync.ts" \
  "$ROOT/apps/api/src/routes/scoreboardControlPolicy.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

SERVICE="apps/api/src/services/scoreboardPregameReadinessGate.ts"
ROUTE="apps/api/src/routes/scoreboardControlPolicy.ts"
TEST="packages/core/test/pregame-readiness-gate-operator-override-16.8.test.ts"

for file in "$SERVICE" "$ROUTE" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

import {
  listScoreboardReliabilityClassifications,
} from "./scoreboardReadinessReliability.js";

export type PregameReadinessGateDecision = {
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

export type PregameReadinessOverride = {
  gameId: string;
  deviceId: string;
  reason: string;
  actorUserId: string | null;
  actorRoles: string[];
  createdAt: string;
};

type Store = {
  version: 1;
  overrides: PregameReadinessOverride[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(process.cwd(), "data");

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-pregame-readiness-overrides.json",
  );

let store = loadStore();

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
        parsed.overrides,
      )
    ) {
      throw new Error(
        "Invalid pregame readiness override store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      overrides: [],
    };
  }
}

function persistStore(): void {
  fs.mkdirSync(
    DATA_DIR,
    { recursive: true },
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

export function setPregameReadinessOverride(input: {
  gameId: string;
  deviceId: string;
  reason: string;
  actorUserId: string | null;
  actorRoles: string[];
}): PregameReadinessOverride {
  const record:
    PregameReadinessOverride = {
      gameId:
        input.gameId,
      deviceId:
        input.deviceId,
      reason:
        input.reason.trim(),
      actorUserId:
        input.actorUserId,
      actorRoles:
        [...input.actorRoles],
      createdAt:
        new Date().toISOString(),
    };

  store.overrides =
    store.overrides.filter(
      (item) =>
        !(
          item.gameId ===
            input.gameId &&
          item.deviceId ===
            input.deviceId
        ),
    );

  store.overrides.push(
    record,
  );

  persistStore();

  return record;
}

export function clearPregameReadinessOverride(
  gameId: string,
  deviceId: string,
): boolean {
  const before =
    store.overrides.length;

  store.overrides =
    store.overrides.filter(
      (item) =>
        !(
          item.gameId ===
            gameId &&
          item.deviceId ===
            deviceId
        ),
    );

  const changed =
    store.overrides.length !==
    before;

  if (changed) {
    persistStore();
  }

  return changed;
}

export function getPregameReadinessOverride(
  gameId: string,
  deviceId: string,
): PregameReadinessOverride | null {
  return (
    store.overrides.find(
      (item) =>
        item.gameId ===
          gameId &&
        item.deviceId ===
          deviceId,
    ) ??
    null
  );
}

export function evaluatePregameReadinessGate(input: {
  gameId: string;
  deviceId: string | null;
}): PregameReadinessGateDecision {
  if (!input.deviceId) {
    return {
      allowed: false,
      gameId:
        input.gameId,
      deviceId:
        null,
      risk:
        "UNKNOWN",
      overrideApplied:
        false,
      reason:
        "No scoreboard device is assigned to this game.",
    };
  }

  const classification =
    listScoreboardReliabilityClassifications()
      .find(
        (item) =>
          item.deviceId ===
          input.deviceId,
      );

  if (!classification) {
    return {
      allowed: false,
      gameId:
        input.gameId,
      deviceId:
        input.deviceId,
      risk:
        "UNKNOWN",
      overrideApplied:
        false,
      reason:
        "No readiness reliability history is available for the assigned scoreboard.",
    };
  }

  const override =
    getPregameReadinessOverride(
      input.gameId,
      input.deviceId,
    );

  if (
    classification.risk ===
      "HEALTHY" ||
    classification.risk ===
      "WATCH"
  ) {
    return {
      allowed: true,
      gameId:
        input.gameId,
      deviceId:
        input.deviceId,
      risk:
        classification.risk,
      overrideApplied:
        false,
      reason:
        classification.risk ===
          "WATCH"
          ? "Assigned scoreboard is in WATCH state but remains eligible for game start."
          : null,
    };
  }

  if (override) {
    return {
      allowed: true,
      gameId:
        input.gameId,
      deviceId:
        input.deviceId,
      risk:
        classification.risk,
      overrideApplied:
        true,
      reason:
        override.reason,
    };
  }

  return {
    allowed: false,
    gameId:
      input.gameId,
    deviceId:
      input.deviceId,
    risk:
      classification.risk,
    overrideApplied:
      false,
    reason:
      `Pregame scoreboard readiness gate blocked start because device risk is ${classification.risk}.`,
  };
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardControlPolicy.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { clearPregameReadinessOverride, evaluatePregameReadinessGate, setPregameReadinessOverride } from "../services/scoreboardPregameReadinessGate.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate policy route imports.",
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
    "/scoreboard-control-pregame-gate",
  )
) {
  const marker =
    "export async function registerScoreboardControlPolicyRoutes";

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate policy route registration.",
    );
  }

  const open =
    text.indexOf(
      "{",
      idx,
    );

  if (open === -1) {
    throw new Error(
      "Unable to locate policy route body.",
    );
  }

  const routes =
`
  app.get(
    "/scoreboard-control-pregame-gate",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy read permission required.",
        });
      }

      const query =
        request.query as {
          gameId?: string;
          deviceId?: string;
        };

      const gameId =
        query.gameId?.trim();

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
          gate:
            evaluatePregameReadinessGate({
              gameId,
              deviceId:
                query.deviceId?.trim() ||
                null,
            }),
        },
      };
    },
  );

  app.put(
    "/scoreboard-control-pregame-gate/override",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_WRITE",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy write permission required.",
        });
      }

      const body =
        request.body as {
          gameId?: string;
          deviceId?: string;
          reason?: string;
        };

      const gameId =
        body.gameId?.trim();

      const deviceId =
        body.deviceId?.trim();

      const reason =
        body.reason?.trim();

      if (
        !gameId ||
        !deviceId ||
        !reason
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID, device ID, and override reason are required.",
        });
      }

      const principal =
        getScoreboardControlPrincipal(
          request,
        );

      const override =
        setPregameReadinessOverride({
          gameId,
          deviceId,
          reason,
          actorUserId:
            principal.userId,
          actorRoles:
            principal.roles,
        });

      return {
        success: true,
        data: {
          override,
          gate:
            evaluatePregameReadinessGate({
              gameId,
              deviceId,
            }),
        },
      };
    },
  );

  app.delete(
    "/scoreboard-control-pregame-gate/override",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_WRITE",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy write permission required.",
        });
      }

      const body =
        request.body as {
          gameId?: string;
          deviceId?: string;
        };

      const gameId =
        body.gameId?.trim();

      const deviceId =
        body.deviceId?.trim();

      if (
        !gameId ||
        !deviceId
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID and device ID are required.",
        });
      }

      return {
        success: true,
        data: {
          cleared:
            clearPregameReadinessOverride(
              gameId,
              deviceId,
            ),
        },
      };
    },
  );

`;

  text =
    text.slice(0, open + 1) +
    routes +
    text.slice(open + 1);
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

describe("Milestone 16.8 pre-game readiness gate / operator override", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardPregameReadinessGate.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlPolicy.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("blocks games with no assigned scoreboard", () => {
    expect(service).toContain(
      "No scoreboard device is assigned to this game.",
    );
  });

  it("blocks at-risk and offline devices without override", () => {
    expect(service).toContain(
      "AT_RISK",
    );

    expect(service).toContain(
      "OFFLINE",
    );

    expect(service).toContain(
      "Pregame scoreboard readiness gate blocked start",
    );
  });

  it("allows healthy and watch devices", () => {
    expect(service).toContain(
      '"HEALTHY"',
    );

    expect(service).toContain(
      '"WATCH"',
    );
  });

  it("persists explicit operator overrides", () => {
    expect(service).toContain(
      "scoreboard-pregame-readiness-overrides.json",
    );

    expect(service).toContain(
      "actorUserId",
    );

    expect(service).toContain(
      "actorRoles",
    );
  });

  it("requires write permission and reason for override", () => {
    expect(route).toContain(
      "/scoreboard-control-pregame-gate/override",
    );

    expect(route).toContain(
      '"CONTROL_POLICY_WRITE"',
    );

    expect(route).toContain(
      "override reason are required",
    );
  });

  it("exposes a read-only pregame gate evaluation endpoint", () => {
    expect(route).toContain(
      "/scoreboard-control-pregame-gate",
    );

    expect(route).toContain(
      '"CONTROL_POLICY_READ"',
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 16.8 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - pre-game scoreboard readiness gate"
echo "  - blocks missing, AT_RISK, and OFFLINE scoreboard states"
echo "  - HEALTHY and WATCH remain start-eligible"
echo "  - persistent operator override store"
echo "  - required override reason"
echo "  - actor user/role attribution"
echo "  - GET pregame gate evaluation"
echo "  - PUT/DELETE override API"
echo "  - Milestone 16.8 regression tests"
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
echo "  Milestone 16.9 - Game Start Integration / Readiness Gate Enforcement"
