#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-19.4-realtime-contract-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

ROUTE="apps/api/src/routes/broadcastSessionProfiles.ts"
CORE="packages/core/src/contracts/realtime.ts"
OVERLAY="apps/dashboard/app/games/[id]/overlay/page.tsx"
TEST="packages/core/test/broadcast-session-realtime-19.4.test.ts"

for required in \
  ".git" \
  "$ROUTE" \
  "$CORE" \
  "$OVERLAY" \
  "apps/api/src/infrastructure/realtime.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$ROUTE" "$CORE" "$OVERLAY" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

node <<'NODE'
const fs = require("fs");

const routeFile =
  "apps/api/src/routes/broadcastSessionProfiles.ts";

let route =
  fs.readFileSync(
    routeFile,
    "utf8",
  );

const realtimeImport =
  'import { realtime } from "../infrastructure/realtime.js";';

if (!route.includes(realtimeImport)) {
  const imports =
    route.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate broadcast route imports.",
    );
  }

  route =
    route.replace(
      imports[0],
      imports[0] +
        realtimeImport +
        "\n",
    );
}

route =
  route.replace(
    /app\.io\?\.to\(/g,
    "realtime().to(",
  );

route =
  route.replace(
    /`public-game:\$\{gameId\}`/g,
    "`game:${gameId}`",
  );

if (route.includes("app.io")) {
  throw new Error(
    "19.4 repair failed: app.io still present.",
  );
}

if (
  route.includes(
    "`public-game:${gameId}`",
  )
) {
  throw new Error(
    "19.4 repair failed: wrong realtime room remains.",
  );
}

if (
  !route.includes(
    'realtime().to('
  ) ||
  !route.includes(
    '`game:${gameId}`'
  )
) {
  throw new Error(
    "19.4 repair failed: established realtime transport not found.",
  );
}

fs.writeFileSync(
  routeFile,
  route,
);
NODE

node <<'NODE'
const fs = require("fs");

const coreFile =
  "packages/core/src/contracts/realtime.ts";

let core =
  fs.readFileSync(
    coreFile,
    "utf8",
  );

if (
  !core.includes(
    "BroadcastSessionProfilePayload"
  )
) {
  const marker =
`export interface BroadcastSoundPayload {
  gameId: number;
  soundId: string;
  type: BroadcastSoundType;
}`;

  if (!core.includes(marker)) {
    throw new Error(
      "Unable to locate broadcast payload contracts.",
    );
  }

  const addition =
`${marker}

export interface BroadcastSessionProfilePayload {
  gameId: string;
  enabled: boolean;
  title: string | null;
  sponsorUrl: string | null;
  showPowerPlay: boolean;
  showTeamLogos: boolean;
  updatedAt: string;
}

export interface BroadcastSessionUpdatedPayload {
  gameId: string;
  profile: BroadcastSessionProfilePayload;
}

export interface BroadcastSessionDeletedPayload {
  gameId: string;
}`;

  core =
    core.replace(
      marker,
      addition,
    );
}

if (
  !core.includes(
    '"broadcast-session:updated"'
  )
) {
  const marker =
`  "scoreboard:sound": (payload: BroadcastSoundPayload) => void;`;

  if (!core.includes(marker)) {
    throw new Error(
      "Unable to locate RealtimeServerEvents broadcast section.",
    );
  }

  core =
    core.replace(
      marker,
`${marker}

  "broadcast-session:updated": (payload: BroadcastSessionUpdatedPayload) => void;
  "broadcast-session:deleted": (payload: BroadcastSessionDeletedPayload) => void;`,
    );
}

fs.writeFileSync(
  coreFile,
  core,
);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.4 realtime contract repair", () => {
  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionProfiles.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const realtime =
    fs.readFileSync(
      new URL(
        "../../../packages/core/src/contracts/realtime.ts",
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

  it("uses the established realtime server accessor", () => {
    expect(route).toContain(
      'import { realtime } from "../infrastructure/realtime.js";',
    );

    expect(route).toContain(
      "realtime().to(",
    );

    expect(route).not.toContain(
      "app.io",
    );
  });

  it("targets the actual public game room", () => {
    expect(route).toContain(
      "`game:${gameId}`",
    );

    expect(route).not.toContain(
      "`public-game:${gameId}`",
    );
  });

  it("registers broadcast-session events in the shared realtime contract", () => {
    expect(realtime).toContain(
      "BroadcastSessionUpdatedPayload",
    );

    expect(realtime).toContain(
      '"broadcast-session:updated"',
    );

    expect(realtime).toContain(
      '"broadcast-session:deleted"',
    );
  });

  it("keeps overlay listeners strongly typed", () => {
    expect(overlay).toContain(
      '"broadcast-session:updated"',
    );

    expect(overlay).toContain(
      '"broadcast-session:deleted"',
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 19.4 realtime contract repair"
echo "============================================================"
echo
echo "Fixed:"
echo "  - replaces invalid app.io access with realtime()"
echo "  - targets existing game:<id> Socket.IO room"
echo "  - adds broadcast-session events to @sportsos/core realtime contract"
echo "  - preserves strongly typed dashboard socket listeners"
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
