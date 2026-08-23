#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-19.4-broadcast-session-realtime-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "apps/api/src/routes/broadcastSessionProfiles.ts" \
  "apps/dashboard/app/games/[id]/overlay/page.tsx" \
  "apps/dashboard/lib/realtime.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

ROUTE="apps/api/src/routes/broadcastSessionProfiles.ts"
OVERLAY="apps/dashboard/app/games/[id]/overlay/page.tsx"
TEST="packages/core/test/broadcast-session-realtime-19.4.test.ts"
DOC="docs/BROADCAST-SESSIONS.md"

for file in "$ROUTE" "$OVERLAY" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/broadcastSessionProfiles.ts";

let text =
  fs.readFileSync(file, "utf8");

if (!text.includes("broadcast-session:updated")) {
  const saveMarker =
`      const profile =
        upsertBroadcastSessionProfile({`;

  const saveIndex =
    text.indexOf(saveMarker);

  if (saveIndex === -1) {
    throw new Error(
      "Unable to locate broadcast profile save route.",
    );
  }

  const returnMarker =
`      return {
        success: true,
        data: {
          profile,
        },
      };`;

  const returnIndex =
    text.indexOf(
      returnMarker,
      saveIndex,
    );

  if (returnIndex === -1) {
    throw new Error(
      "Unable to locate broadcast profile save response.",
    );
  }

  const emitBlock =
`      app.io?.to(
        \`public-game:\${gameId}\`,
      ).emit(
        "broadcast-session:updated",
        {
          gameId,
          profile,
        },
      );

`;

  text =
    text.slice(0, returnIndex) +
    emitBlock +
    text.slice(returnIndex);
}

if (!text.includes("broadcast-session:deleted")) {
  const deleteMarker =
`      return {
        success: true,
        data: {
          deleted:
            deleteBroadcastSessionProfile(
              gameId,
            ),
        },
      };`;

  const deleteIndex =
    text.indexOf(deleteMarker);

  if (deleteIndex === -1) {
    throw new Error(
      "Unable to locate broadcast profile delete response.",
    );
  }

  const replacement =
`      const deleted =
        deleteBroadcastSessionProfile(
          gameId,
        );

      app.io?.to(
        \`public-game:\${gameId}\`,
      ).emit(
        "broadcast-session:deleted",
        {
          gameId,
        },
      );

      return {
        success: true,
        data: {
          deleted,
        },
      };`;

  text =
    text.replace(
      deleteMarker,
      replacement,
    );
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/games/[id]/overlay/page.tsx";

let text =
  fs.readFileSync(file, "utf8");

if (!text.includes('socket.on("broadcast-session:updated"')) {
  const marker =
`    socket.on("game:penalties-updated", refresh);`;

  if (!text.includes(marker)) {
    throw new Error(
      "Unable to locate overlay realtime subscriptions.",
    );
  }

  const addition =
`${marker}

    socket.on(
      "broadcast-session:updated",
      (payload: {
        gameId?: number | string;
        profile?: BroadcastSessionProfile | null;
      }) => {
        if (
          String(
            payload.gameId ??
            "",
          ) ===
          String(
            gameId,
          )
        ) {
          setProfile(
            payload.profile ??
            null,
          );
        }
      },
    );

    socket.on(
      "broadcast-session:deleted",
      (payload: {
        gameId?: number | string;
      }) => {
        if (
          String(
            payload.gameId ??
            "",
          ) ===
          String(
            gameId,
          )
        ) {
          setProfile(
            null,
          );
        }
      },
    );`;

  text =
    text.replace(
      marker,
      addition,
    );
}

fs.writeFileSync(file, text);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 19.4 — Realtime broadcast profile updates

Broadcast-session saves and resets now emit realtime events to the game’s public realtime room.

Events:

```text
broadcast-session:updated
broadcast-session:deleted
```

The overlay listens for both events.

This means an already-open overlay immediately reflects:

- title changes
- sponsor changes
- power-play visibility
- team-logo visibility
- profile reset

without requiring a manual browser refresh.

Game state realtime and broadcast-profile realtime remain separate concerns.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.4 broadcast session realtime profile updates", () => {
  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionProfiles.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const overlay =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/games/[id]/overlay/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("emits updated profile events", () => {
    expect(route).toContain(
      '"broadcast-session:updated"',
    );

    expect(route).toContain(
      "profile,",
    );
  });

  it("emits profile deletion events", () => {
    expect(route).toContain(
      '"broadcast-session:deleted"',
    );
  });

  it("targets the public game realtime room", () => {
    expect(route).toContain(
      "public-game:",
    );
  });

  it("updates open overlays without reload", () => {
    expect(overlay).toContain(
      'socket.on(\n      "broadcast-session:updated"',
    );

    expect(overlay).toContain(
      "setProfile(",
    );
  });

  it("clears profile on reset", () => {
    expect(overlay).toContain(
      '"broadcast-session:deleted"',
    );

    expect(overlay).toContain(
      "setProfile(\n            null",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 19.4 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - broadcast-session:updated realtime event"
echo "  - broadcast-session:deleted realtime event"
echo "  - game-room targeting"
echo "  - live overlay profile updates"
echo "  - live overlay profile reset"
echo "  - no page refresh required"
echo "  - Milestone 19.4 regression tests"
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
echo "  Milestone 19.5 - Broadcast Scene Presets / Sponsor Rotation Foundation"
