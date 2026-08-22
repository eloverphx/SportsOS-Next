#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.6-override-service-recovery-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "apps/api/src/routes/gameDayHardwarePreflight.ts" \
  "apps/api/src/modules/games/routes.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

SERVICE="apps/api/src/services/gameStartPreflightOverride.ts"
TEST="packages/core/test/preflight-override-service-recovery-18.6.test.ts"

for file in "$SERVICE" "$TEST"; do
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

  const createdAtMs =
    Date.now();

  const override:
    GameStartPreflightOverride = {
      overrideId:
        `preflight-override-${input.gameId}-${input.deviceId}-${createdAtMs}`,
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
          createdAtMs,
        ).toISOString(),
      expiresAt:
        new Date(
          createdAtMs +
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

for (const [file, required] of [
  [
    "apps/api/src/routes/gameDayHardwarePreflight.ts",
    [
      "createGameStartPreflightOverride",
      "revokeGameStartPreflightOverride",
    ],
  ],
  [
    "apps/api/src/modules/games/routes.ts",
    [
      "getActiveGameStartPreflightOverride",
    ],
  ],
]) {
  const text =
    fs.readFileSync(
      file,
      "utf8",
    );

  for (const symbol of required) {
    if (!text.includes(symbol)) {
      throw new Error(
        `Existing 18.6 wiring missing in ${file}: ${symbol}`,
      );
    }
  }
}

console.log(
  "Existing 18.6 route/start-gate wiring verified.",
);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.6 override service recovery", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameStartPreflightOverride.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("restores create active revoke and list operations", () => {
    for (const symbol of [
      "createGameStartPreflightOverride",
      "getActiveGameStartPreflightOverride",
      "revokeGameStartPreflightOverride",
      "listGameStartPreflightOverrides",
    ]) {
      expect(service).toContain(
        symbol,
      );
    }
  });

  it("restores persisted scoped overrides", () => {
    expect(service).toContain(
      "game-start-preflight-overrides.json",
    );

    expect(service).toContain(
      "gameId",
    );

    expect(service).toContain(
      "deviceId",
    );
  });

  it("restores expiration and required reason", () => {
    expect(service).toContain(
      "SPORTSOS_GAME_START_OVERRIDE_TTL_MS",
    );

    expect(service).toContain(
      "Emergency override reason is required.",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 18.6 override service recovery"
echo "============================================================"
echo
echo "Restored:"
echo "  - gameStartPreflightOverride.ts"
echo "  - create / active lookup / revoke / list"
echo "  - persisted override audit store"
echo "  - 10-minute default expiration"
echo "  - game/device scoping"
echo "  - existing 18.6 route/start-gate wiring verification"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then retry:"
echo "  bash sportsos-milestone-18.10-game-day-deployment-acceptance-closeout.sh"
