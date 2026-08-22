#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.6-full-emergency-override-recovery-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/gameStartPreflightOverride.ts"
ROUTE="apps/api/src/routes/gameDayHardwarePreflight.ts"
GAMES="apps/api/src/modules/games/routes.ts"
TEST="packages/core/test/preflight-emergency-override-recovery-18.6.test.ts"

for required in \
  ".git" \
  "$ROUTE" \
  "$GAMES" \
  "apps/api/src/services/gameStartPreflightGuard.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$ROUTE" "$GAMES" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type GameStartPreflightOverride = {
  overrideId: string;
  gameId: string;
  deviceId: string;
  reason: string;
  actorUserId: string | null;
  actorRoles: string[];
  createdAt: string;
  expiresAt: string;
  revokedAt: string | null;
};

type Store = {
  version: 1;
  overrides:
    GameStartPreflightOverride[];
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
    "game-start-preflight-overrides.json",
  );

const DEFAULT_OVERRIDE_TTL_MS =
  Number.parseInt(
    process.env.SPORTSOS_GAME_START_OVERRIDE_TTL_MS ??
      "600000",
    10,
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
        parsed.overrides,
      )
    ) {
      throw new Error(
        "Invalid game-start override store.",
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

function configuredTtlMs(): number {
  return (
    Number.isFinite(
      DEFAULT_OVERRIDE_TTL_MS,
    ) &&
    DEFAULT_OVERRIDE_TTL_MS > 0
      ? DEFAULT_OVERRIDE_TTL_MS
      : 600000
  );
}

export function createGameStartPreflightOverride(input: {
  gameId: string;
  deviceId: string;
  reason: string;
  actorUserId: string | null;
  actorRoles: string[];
}): GameStartPreflightOverride {
  const reason =
    input.reason.trim();

  if (!reason) {
    throw new Error(
      "Emergency override reason is required.",
    );
  }

  const now =
    Date.now();

  const override:
    GameStartPreflightOverride = {
      overrideId:
        `preflight-override-${input.gameId}-${input.deviceId}-${now}`,
      gameId:
        input.gameId,
      deviceId:
        input.deviceId,
      reason,
      actorUserId:
        input.actorUserId,
      actorRoles:
        [...input.actorRoles],
      createdAt:
        new Date(
          now,
        ).toISOString(),
      expiresAt:
        new Date(
          now +
            configuredTtlMs(),
        ).toISOString(),
      revokedAt:
        null,
    };

  store.overrides.push(
    override,
  );

  persistStore();

  return {
    ...override,
    actorRoles:
      [...override.actorRoles],
  };
}

export function getActiveGameStartPreflightOverride(
  gameId: string,
  deviceId: string,
): GameStartPreflightOverride | null {
  const now =
    Date.now();

  const active =
    [...store.overrides]
      .reverse()
      .find(
        (item) =>
          item.gameId ===
            gameId &&
          item.deviceId ===
            deviceId &&
          item.revokedAt ===
            null &&
          Date.parse(
            item.expiresAt,
          ) >
            now,
      );

  return active
    ? {
        ...active,
        actorRoles:
          [...active.actorRoles],
      }
    : null;
}

export function revokeGameStartPreflightOverride(
  overrideId: string,
): boolean {
  const override =
    store.overrides.find(
      (item) =>
        item.overrideId ===
        overrideId,
    );

  if (
    !override ||
    override.revokedAt
  ) {
    return false;
  }

  override.revokedAt =
    new Date().toISOString();

  persistStore();

  return true;
}

export function listGameStartPreflightOverrides(
  gameId?: string,
): GameStartPreflightOverride[] {
  return [...store.overrides]
    .filter(
      (item) =>
        !gameId ||
        item.gameId ===
          gameId,
    )
    .sort(
      (a, b) =>
        b.createdAt.localeCompare(
          a.createdAt,
        ),
    )
    .map(
      (item) => ({
        ...item,
        actorRoles:
          [...item.actorRoles],
      }),
    );
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/gameDayHardwarePreflight.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { createGameStartPreflightOverride, listGameStartPreflightOverrides, revokeGameStartPreflightOverride } from "../services/gameStartPreflightOverride.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate preflight route imports.",
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

const registrationMarker =
  "export async function registerGameDayHardwarePreflightRoutes";

const regIndex =
  text.indexOf(
    registrationMarker,
  );

if (regIndex === -1) {
  throw new Error(
    "Unable to locate preflight route registration.",
  );
}

const bodyOpen =
  text.indexOf(
    "{",
    regIndex,
  );

if (bodyOpen === -1) {
  throw new Error(
    "Unable to locate preflight route body.",
  );
}

let routes = "";

if (
  !text.includes(
    '"/game-day-hardware-preflight/:gameId/overrides"'
  )
) {
  routes += `
  app.get(
    "/game-day-hardware-preflight/:gameId/overrides",
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
          overrides:
            listGameStartPreflightOverrides(
              gameId,
            ),
        },
      };
    },
  );

`;
}

if (
  !text.includes(
    '"/game-day-hardware-preflight/:gameId/override"'
  )
) {
  routes += `
  app.post(
    "/game-day-hardware-preflight/:gameId/override",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const body =
        request.body as {
          deviceId?: string;
          reason?: string;
          actorUserId?: string | null;
          actorRoles?: string[];
        };

      const gameId =
        params.gameId?.trim();

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
            "Game ID, device ID, and emergency override reason are required.",
        });
      }

      const override =
        createGameStartPreflightOverride({
          gameId,
          deviceId,
          reason,
          actorUserId:
            body.actorUserId ??
            null,
          actorRoles:
            Array.isArray(
              body.actorRoles,
            )
              ? body.actorRoles
              : [],
        });

      return reply.code(201).send({
        success: true,
        data: {
          override,
        },
      });
    },
  );

`;
}

if (
  !text.includes(
    '"/game-day-hardware-preflight/:gameId/override/:overrideId"'
  )
) {
  routes += `
  app.delete(
    "/game-day-hardware-preflight/:gameId/override/:overrideId",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
          overrideId?: string;
        };

      if (
        !params.gameId?.trim() ||
        !params.overrideId?.trim()
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID and override ID are required.",
        });
      }

      return {
        success: true,
        data: {
          revoked:
            revokeGameStartPreflightOverride(
              params.overrideId.trim(),
            ),
        },
      };
    },
  );

`;
}

if (routes) {
  text =
    text.slice(
      0,
      bodyOpen + 1,
    ) +
    routes +
    text.slice(
      bodyOpen + 1,
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/modules/games/routes.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { getActiveGameStartPreflightOverride } from "../../services/gameStartPreflightOverride.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate game route imports.",
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
    "GAME_START_PREFLIGHT_OVERRIDE_18_6"
  )
) {
  const marker =
    "// GAME_START_PREFLIGHT_ENFORCEMENT_18_4";

  const markerIndex =
    text.indexOf(
      marker,
    );

  if (markerIndex === -1) {
    throw new Error(
      "Unable to locate 18.4 start preflight enforcement.",
    );
  }

  const ifIndex =
    text.indexOf(
      "if (",
      markerIndex,
    );

  if (ifIndex === -1) {
    throw new Error(
      "Unable to locate 18.4 rejection branch.",
    );
  }

  const braceOpen =
    text.indexOf(
      "{",
      ifIndex,
    );

  if (braceOpen === -1) {
    throw new Error(
      "Unable to locate 18.4 rejection branch body.",
    );
  }

  /*
   * Transform:
   * if (!gameStartPreflight.allowed) {
   *   return 409...
   * }
   *
   * into:
   * if (!gameStartPreflight.allowed) {
   *   const activeEmergencyOverride = ...
   *   if (!activeEmergencyOverride) {
   *     return 409...
   *   }
   * }
   */

  const insert =
`
        // GAME_START_PREFLIGHT_OVERRIDE_18_6
        const activeEmergencyOverride =
          getActiveGameStartPreflightOverride(
            String(id.data),
            gameStartPreflight.deviceId ??
              "",
          );

        if (
          !activeEmergencyOverride
        ) {
`;

  text =
    text.slice(
      0,
      braceOpen + 1,
    ) +
    insert +
    text.slice(
      braceOpen + 1,
    );

  const afterInsert =
    braceOpen +
    1 +
    insert.length;

  const replyIndex =
    text.indexOf(
      "return reply.code(409).send(",
      afterInsert,
    );

  if (replyIndex === -1) {
    throw new Error(
      "Unable to locate 18.4 HTTP 409 response.",
    );
  }

  const sendEnd =
    text.indexOf(
      "        });",
      replyIndex,
    );

  if (sendEnd === -1) {
    throw new Error(
      "Unable to locate 18.4 HTTP 409 response end.",
    );
  }

  const closeAt =
    sendEnd +
    "        });".length;

  text =
    text.slice(
      0,
      closeAt,
    ) +
    "\n        }" +
    text.slice(
      closeAt,
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

describe("Milestone 18.6 full emergency override recovery", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameStartPreflightOverride.ts",
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

  const games =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/modules/games/routes.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("restores override service operations", () => {
    expect(service).toContain(
      "createGameStartPreflightOverride",
    );

    expect(service).toContain(
      "getActiveGameStartPreflightOverride",
    );

    expect(service).toContain(
      "revokeGameStartPreflightOverride",
    );

    expect(service).toContain(
      "listGameStartPreflightOverrides",
    );
  });

  it("restores override API wiring", () => {
    expect(route).toContain(
      "/game-day-hardware-preflight/:gameId/override",
    );

    expect(route).toContain(
      "/game-day-hardware-preflight/:gameId/overrides",
    );
  });

  it("restores game-start override lookup", () => {
    expect(games).toContain(
      "GAME_START_PREFLIGHT_OVERRIDE_18_6",
    );

    expect(games).toContain(
      "getActiveGameStartPreflightOverride",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 18.6 full override recovery"
echo "============================================================"
echo
echo "Restored:"
echo "  - gameStartPreflightOverride.ts"
echo "  - create/list/revoke override API routes"
echo "  - game-start active override lookup"
echo "  - 10-minute default override expiration"
echo "  - persisted audit history"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then retry:"
echo "  bash sportsos-milestone-18.10-game-day-deployment-acceptance-closeout.sh"
