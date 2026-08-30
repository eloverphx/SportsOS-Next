#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-19.1-broadcast-session-profile-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "package.json" \
  "apps/api/src/app.ts" \
  "apps/dashboard/app/games/[id]/overlay/page.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

SERVICE="apps/api/src/services/broadcastSessionProfile.ts"
ROUTE="apps/api/src/routes/broadcastSessionProfiles.ts"
APP="apps/api/src/app.ts"
TEST="packages/core/test/broadcast-session-profile-19.1.test.ts"
DOC="docs/BROADCAST-SESSIONS.md"

for file in "$SERVICE" "$ROUTE" "$APP" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$ROUTE")" "$(dirname "$TEST")" docs

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type BroadcastSessionProfile = {
  gameId: string;
  enabled: boolean;
  title: string | null;
  sponsorUrl: string | null;
  showPowerPlay: boolean;
  showTeamLogos: boolean;
  updatedAt: string;
};

type Store = {
  version: 1;
  profiles:
    BroadcastSessionProfile[];
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
    "broadcast-session-profiles.json",
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
        parsed.profiles,
      )
    ) {
      throw new Error(
        "Invalid broadcast session profile store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      profiles: [],
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

export function getBroadcastSessionProfile(
  gameId: string,
): BroadcastSessionProfile | null {
  const profile =
    store.profiles.find(
      (item) =>
        item.gameId ===
        gameId,
    );

  return profile
    ? { ...profile }
    : null;
}

export function upsertBroadcastSessionProfile(input: {
  gameId: string;
  enabled?: boolean;
  title?: string | null;
  sponsorUrl?: string | null;
  showPowerPlay?: boolean;
  showTeamLogos?: boolean;
}): BroadcastSessionProfile {
  const existing =
    getBroadcastSessionProfile(
      input.gameId,
    );

  const title =
    typeof input.title ===
      "string"
      ? input.title.trim() ||
        null
      : input.title === null
        ? null
        : existing?.title ??
          null;

  const sponsorUrl =
    typeof input.sponsorUrl ===
      "string"
      ? input.sponsorUrl.trim() ||
        null
      : input.sponsorUrl ===
          null
        ? null
        : existing?.sponsorUrl ??
          null;

  const profile:
    BroadcastSessionProfile = {
      gameId:
        input.gameId,
      enabled:
        input.enabled ??
        existing?.enabled ??
        true,
      title,
      sponsorUrl,
      showPowerPlay:
        input.showPowerPlay ??
        existing?.showPowerPlay ??
        true,
      showTeamLogos:
        input.showTeamLogos ??
        existing?.showTeamLogos ??
        true,
      updatedAt:
        new Date().toISOString(),
    };

  store.profiles =
    store.profiles.filter(
      (item) =>
        item.gameId !==
        input.gameId,
    );

  store.profiles.push(
    profile,
  );

  persistStore();

  return {
    ...profile,
  };
}

export function deleteBroadcastSessionProfile(
  gameId: string,
): boolean {
  const before =
    store.profiles.length;

  store.profiles =
    store.profiles.filter(
      (item) =>
        item.gameId !==
        gameId,
    );

  const changed =
    store.profiles.length !==
    before;

  if (changed) {
    persistStore();
  }

  return changed;
}
EOF

cat > "$ROUTE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import {
  deleteBroadcastSessionProfile,
  getBroadcastSessionProfile,
  upsertBroadcastSessionProfile,
} from "../services/broadcastSessionProfile.js";

export async function registerBroadcastSessionProfileRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.get(
    "/broadcast-sessions/:gameId",
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
          profile:
            getBroadcastSessionProfile(
              gameId,
            ),
        },
      };
    },
  );

  app.put(
    "/broadcast-sessions/:gameId",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const body =
        request.body as {
          enabled?: boolean;
          title?: string | null;
          sponsorUrl?: string | null;
          showPowerPlay?: boolean;
          showTeamLogos?: boolean;
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

      const profile =
        upsertBroadcastSessionProfile({
          gameId,
          enabled:
            body.enabled,
          title:
            body.title,
          sponsorUrl:
            body.sponsorUrl,
          showPowerPlay:
            body.showPowerPlay,
          showTeamLogos:
            body.showTeamLogos,
        });

      return {
        success: true,
        data: {
          profile,
        },
      };
    },
  );

  app.delete(
    "/broadcast-sessions/:gameId",
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
          deleted:
            deleteBroadcastSessionProfile(
              gameId,
            ),
        },
      };
    },
  );

  app.get(
    "/public/games/:gameId/broadcast-session",
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

      const profile =
        getBroadcastSessionProfile(
          gameId,
        );

      return {
        success: true,
        data: {
          profile:
            profile?.enabled
              ? profile
              : null,
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
  'import { registerBroadcastSessionProfileRoutes } from "./routes/broadcastSessionProfiles.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate API import block.",
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
    "registerBroadcastSessionProfileRoutes"
  ) ||
  !text.includes(
    "app.register(registerBroadcastSessionProfileRoutes)"
  )
) {
  const marker =
    "await app.register(registerGameDayHardwarePreflightRoutes);";

  const idx =
    text.indexOf(
      marker,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate game-day preflight route registration.",
    );
  }

  const insertAt =
    idx +
    marker.length;

  text =
    text.slice(
      0,
      insertAt,
    ) +
    "\n  await app.register(registerBroadcastSessionProfileRoutes);" +
    text.slice(
      insertAt,
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat > "$DOC" <<'EOF'
# Broadcast Sessions

Milestone 19 begins the broadcast/streaming operations layer on top of the existing public scoreboard and broadcast overlay.

## Existing overlay

SportsOS already exposes a realtime broadcast overlay:

```text
/games/:id/overlay
```

The overlay consumes the same public authoritative scoreboard snapshot as:

```text
/games/:id/scoreboard
```

Milestone 19 preserves that architecture.

## Milestone 19.1

Broadcast presentation settings are now represented by a persisted per-game broadcast session profile.

Profile fields:

- game ID
- enabled state
- broadcast title
- sponsor image URL
- show/hide power-play indicator
- show/hide team logos
- last update timestamp

API:

```text
GET    /broadcast-sessions/:gameId
PUT    /broadcast-sessions/:gameId
DELETE /broadcast-sessions/:gameId
GET    /public/games/:gameId/broadcast-session
```

The public endpoint returns the profile only when the broadcast session is enabled.

## Architecture boundary

Broadcast presentation configuration must not become authoritative game state.

Score, clock, period, penalties, teams, and lifecycle remain sourced from the authoritative public scoreboard snapshot.

Future Milestone 19 work should make the overlay consume this profile rather than encode persistent presentation configuration only in URL query parameters.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.1 broadcast session profile", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastSessionProfile.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionProfiles.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const app =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/app.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("persists one broadcast profile per game", () => {
    expect(service).toContain(
      "broadcast-session-profiles.json",
    );

    expect(service).toContain(
      "gameId",
    );

    expect(service).toContain(
      "upsertBroadcastSessionProfile",
    );
  });

  it("supports broadcast presentation settings", () => {
    for (const field of [
      "enabled",
      "title",
      "sponsorUrl",
      "showPowerPlay",
      "showTeamLogos",
    ]) {
      expect(service).toContain(
        field,
      );
    }
  });

  it("provides operator CRUD routes", () => {
    expect(route).toContain(
      '"/broadcast-sessions/:gameId"',
    );

    expect(route).toContain(
      "app.put",
    );

    expect(route).toContain(
      "app.delete",
    );
  });

  it("provides a public enabled-session endpoint", () => {
    expect(route).toContain(
      '"/public/games/:gameId/broadcast-session"',
    );

    expect(route).toContain(
      "profile?.enabled",
    );
  });

  it("registers broadcast-session routes in the API", () => {
    expect(app).toContain(
      "registerBroadcastSessionProfileRoutes",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 19.1 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - persisted per-game broadcast session profile"
echo "  - enabled state"
echo "  - broadcast title"
echo "  - sponsor URL"
echo "  - power-play visibility preference"
echo "  - team-logo visibility preference"
echo "  - operator GET/PUT/DELETE API"
echo "  - public enabled-session API"
echo "  - API registration"
echo "  - Milestone 19.1 regression tests"
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
echo "  Milestone 19.2 - Overlay Profile Consumption / Persistent Broadcast Branding"
