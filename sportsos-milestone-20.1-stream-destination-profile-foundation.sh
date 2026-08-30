#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-20.1-stream-destination-profile-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "apps/api/src/app.ts" \
  "apps/dashboard/app/scoreboards/operations/page.tsx" \
  "docs/MILESTONE-STATUS.md"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

SERVICE="apps/api/src/services/streamDestinationProfile.ts"
ROUTE="apps/api/src/routes/streamDestinationProfiles.ts"
APP="apps/api/src/app.ts"
TEST="packages/core/test/stream-destination-profile-20.1.test.ts"
DOC="docs/STREAMING-OPERATIONS.md"
STATUS="docs/MILESTONE-STATUS.md"

for file in "$SERVICE" "$ROUTE" "$APP" "$TEST" "$DOC" "$STATUS"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$ROUTE")" "$(dirname "$TEST")" docs

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type StreamProtocol =
  | "RTMP"
  | "SRT";

export type StreamLatencyMode =
  | "NORMAL"
  | "LOW"
  | "ULTRA_LOW";

export type StreamDestinationStatus =
  | "DISABLED"
  | "CONFIGURED"
  | "READY"
  | "LIVE"
  | "ERROR";

export type StreamDestinationProfile = {
  gameId: string;
  enabled: boolean;
  protocol: StreamProtocol;
  ingestUrl: string | null;
  streamName: string | null;
  credentialRef: string | null;
  latencyMode: StreamLatencyMode;
  status: StreamDestinationStatus;
  lastError: string | null;
  updatedAt: string;
};

type Store = {
  version: 1;
  profiles:
    StreamDestinationProfile[];
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
    "stream-destination-profiles.json",
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
        "Invalid stream destination profile store.",
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

function optionalText(
  value: string | null | undefined,
  fallback: string | null,
): string | null {
  if (value === undefined) {
    return fallback;
  }

  if (value === null) {
    return null;
  }

  return value.trim() || null;
}

export function getStreamDestinationProfile(
  gameId: string,
): StreamDestinationProfile | null {
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

export function upsertStreamDestinationProfile(input: {
  gameId: string;
  enabled?: boolean;
  protocol?: StreamProtocol;
  ingestUrl?: string | null;
  streamName?: string | null;
  credentialRef?: string | null;
  latencyMode?: StreamLatencyMode;
}): StreamDestinationProfile {
  const existing =
    getStreamDestinationProfile(
      input.gameId,
    );

  const enabled =
    input.enabled ??
    existing?.enabled ??
    false;

  const ingestUrl =
    optionalText(
      input.ingestUrl,
      existing?.ingestUrl ??
        null,
    );

  const credentialRef =
    optionalText(
      input.credentialRef,
      existing?.credentialRef ??
        null,
    );

  const configured =
    Boolean(
      ingestUrl &&
      credentialRef,
    );

  const profile:
    StreamDestinationProfile = {
      gameId:
        input.gameId,
      enabled,
      protocol:
        input.protocol ??
        existing?.protocol ??
        "RTMP",
      ingestUrl,
      streamName:
        optionalText(
          input.streamName,
          existing?.streamName ??
            null,
        ),
      credentialRef,
      latencyMode:
        input.latencyMode ??
        existing?.latencyMode ??
        "NORMAL",
      status:
        enabled
          ? configured
            ? existing?.status ===
                "LIVE"
              ? "LIVE"
              : "CONFIGURED"
            : "ERROR"
          : "DISABLED",
      lastError:
        enabled &&
        !configured
          ? "Enabled stream destination requires ingestUrl and credentialRef."
          : null,
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

export function deleteStreamDestinationProfile(
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

export function publicStreamDestinationSummary(
  gameId: string,
): {
  enabled: boolean;
  protocol: StreamProtocol | null;
  status: StreamDestinationStatus;
} {
  const profile =
    getStreamDestinationProfile(
      gameId,
    );

  if (!profile) {
    return {
      enabled: false,
      protocol: null,
      status: "DISABLED",
    };
  }

  return {
    enabled:
      profile.enabled,
    protocol:
      profile.protocol,
    status:
      profile.status,
  };
}
EOF

cat > "$ROUTE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import {
  deleteStreamDestinationProfile,
  getStreamDestinationProfile,
  publicStreamDestinationSummary,
  upsertStreamDestinationProfile,
  type StreamLatencyMode,
  type StreamProtocol,
} from "../services/streamDestinationProfile.js";

export async function registerStreamDestinationProfileRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.get(
    "/stream-destinations/:gameId",
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
            getStreamDestinationProfile(
              gameId,
            ),
        },
      };
    },
  );

  app.put(
    "/stream-destinations/:gameId",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const body =
        request.body as {
          enabled?: boolean;
          protocol?: StreamProtocol;
          ingestUrl?: string | null;
          streamName?: string | null;
          credentialRef?: string | null;
          latencyMode?: StreamLatencyMode;
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
        upsertStreamDestinationProfile({
          gameId,
          enabled:
            body.enabled,
          protocol:
            body.protocol,
          ingestUrl:
            body.ingestUrl,
          streamName:
            body.streamName,
          credentialRef:
            body.credentialRef,
          latencyMode:
            body.latencyMode,
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
    "/stream-destinations/:gameId",
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
            deleteStreamDestinationProfile(
              gameId,
            ),
        },
      };
    },
  );

  app.get(
    "/public/games/:gameId/stream-status",
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
          stream:
            publicStreamDestinationSummary(
              gameId,
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
  'import { registerStreamDestinationProfileRoutes } from "./routes/streamDestinationProfiles.js";';

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
    "app.register(registerStreamDestinationProfileRoutes)"
  )
) {
  const candidates = [
    "await app.register(registerBroadcastSessionProfileRoutes);",
    "await app.register(registerGameDayHardwarePreflightRoutes);",
  ];

  let marker =
    null;

  for (
    const candidate of
      candidates
  ) {
    if (
      text.includes(
        candidate,
      )
    ) {
      marker =
        candidate;
      break;
    }
  }

  if (!marker) {
    throw new Error(
      "Unable to locate route registration insertion point.",
    );
  }

  text =
    text.replace(
      marker,
      marker +
        "\n  await app.register(registerStreamDestinationProfileRoutes);",
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat > "$DOC" <<'EOF'
# Streaming Operations

Milestone 20 begins the streaming-output and encoder-operations layer.

## Authority boundary

Streaming configuration is operational metadata.

It must never become authoritative for:

- score
- clock
- period
- penalties
- game lifecycle
- scoreboard assignment

## Milestone 20.1 — Stream destination profile

Each game may have one persisted stream destination profile.

Supported protocols:

```text
RTMP
SRT
```

Supported latency modes:

```text
NORMAL
LOW
ULTRA_LOW
```

Destination states:

```text
DISABLED
CONFIGURED
READY
LIVE
ERROR
```

Profile fields:

- game ID
- enabled state
- protocol
- ingest URL
- stream name
- credential reference
- latency mode
- status
- last error
- updated timestamp

## Credential boundary

SportsOS 20.1 does **not** place a raw stream key in the public API.

The profile stores:

```text
credentialRef
```

rather than a public credential value.

Future milestones should resolve that reference through a server-side credential provider or secret store.

## API

Operator routes:

```text
GET    /stream-destinations/:gameId
PUT    /stream-destinations/:gameId
DELETE /stream-destinations/:gameId
```

Public status route:

```text
GET /public/games/:gameId/stream-status
```

The public route exposes only:

- enabled state
- protocol
- status

It never returns ingest URLs or credential references.
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "docs/MILESTONE-STATUS.md";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !text.includes(
    "### Milestone 20"
  )
) {
  text += `

### Milestone 20

Streaming output and encoder operations.

Current work:

- 20.1 stream destination profile foundation
`;
}

text =
  text.replace(
    /Milestone 19\.10 complete/g,
    "Milestone 19.10 complete\nMilestone 20.1 in progress",
  );

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

describe("Milestone 20.1 stream destination profile foundation", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/streamDestinationProfile.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/streamDestinationProfiles.ts",
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

  it("supports RTMP and SRT destinations", () => {
    expect(service).toContain(
      '"RTMP"',
    );

    expect(service).toContain(
      '"SRT"',
    );
  });

  it("stores credential references rather than a public stream key", () => {
    expect(service).toContain(
      "credentialRef",
    );

    expect(route).not.toContain(
      "streamKey",
    );
  });

  it("supports destination readiness states", () => {
    for (const state of [
      "DISABLED",
      "CONFIGURED",
      "READY",
      "LIVE",
      "ERROR",
    ]) {
      expect(service).toContain(
        `"${state}"`,
      );
    }
  });

  it("provides operator CRUD routes", () => {
    expect(route).toContain(
      '"/stream-destinations/:gameId"',
    );

    expect(route).toContain(
      "app.put",
    );

    expect(route).toContain(
      "app.delete",
    );
  });

  it("provides a redacted public status endpoint", () => {
    expect(route).toContain(
      '"/public/games/:gameId/stream-status"',
    );

    expect(service).toContain(
      "publicStreamDestinationSummary",
    );
  });

  it("registers streaming routes in the API", () => {
    expect(app).toContain(
      "registerStreamDestinationProfileRoutes",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 20.1 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - per-game stream destination profile"
echo "  - RTMP / SRT protocol selection"
echo "  - latency mode"
echo "  - destination readiness status"
echo "  - credentialRef boundary (no public stream key)"
echo "  - operator CRUD API"
echo "  - redacted public stream-status API"
echo "  - Milestone 20.1 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 20.2 - Stream Destination Operator UI / Validation"
