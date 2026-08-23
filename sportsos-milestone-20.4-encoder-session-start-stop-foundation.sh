#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-20.4-encoder-session-foundation-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "apps/api/src/services/streamDestinationProfile.ts" \
  "apps/api/src/routes/streamDestinationProfiles.ts" \
  "apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

SERVICE="apps/api/src/services/encoderSession.ts"
ROUTE="apps/api/src/routes/encoderSessions.ts"
APP="apps/api/src/app.ts"
PANEL="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
TEST="packages/core/test/encoder-session-foundation-20.4.test.ts"
DOC="docs/STREAMING-OPERATIONS.md"

for file in "$SERVICE" "$ROUTE" "$APP" "$PANEL" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$ROUTE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type EncoderSessionStatus =
  | "STOPPED"
  | "STARTING"
  | "LIVE"
  | "STOPPING"
  | "ERROR";

export type EncoderSession = {
  gameId: string;
  status: EncoderSessionStatus;
  startedAt: string | null;
  stoppedAt: string | null;
  lastTransitionAt: string;
  lastError: string | null;
};

type Store = {
  version: 1;
  sessions:
    EncoderSession[];
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
    "encoder-sessions.json",
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
        parsed.sessions,
      )
    ) {
      throw new Error(
        "Invalid encoder-session store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      sessions: [],
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

function replaceSession(
  session: EncoderSession,
): EncoderSession {
  store.sessions =
    store.sessions.filter(
      (item) =>
        item.gameId !==
        session.gameId,
    );

  store.sessions.push(
    session,
  );

  persistStore();

  return {
    ...session,
  };
}

export function getEncoderSession(
  gameId: string,
): EncoderSession {
  const existing =
    store.sessions.find(
      (item) =>
        item.gameId ===
        gameId,
    );

  if (existing) {
    return {
      ...existing,
    };
  }

  const now =
    new Date().toISOString();

  return {
    gameId,
    status:
      "STOPPED",
    startedAt:
      null,
    stoppedAt:
      now,
    lastTransitionAt:
      now,
    lastError:
      null,
  };
}

export function beginEncoderStart(
  gameId: string,
): EncoderSession {
  const current =
    getEncoderSession(
      gameId,
    );

  if (
    current.status ===
      "LIVE" ||
    current.status ===
      "STARTING"
  ) {
    return current;
  }

  const now =
    new Date().toISOString();

  return replaceSession({
    ...current,
    status:
      "STARTING",
    startedAt:
      null,
    stoppedAt:
      current.stoppedAt,
    lastTransitionAt:
      now,
    lastError:
      null,
  });
}

export function markEncoderLive(
  gameId: string,
): EncoderSession {
  const current =
    getEncoderSession(
      gameId,
    );

  const now =
    new Date().toISOString();

  return replaceSession({
    ...current,
    status:
      "LIVE",
    startedAt:
      current.startedAt ??
      now,
    stoppedAt:
      null,
    lastTransitionAt:
      now,
    lastError:
      null,
  });
}

export function beginEncoderStop(
  gameId: string,
): EncoderSession {
  const current =
    getEncoderSession(
      gameId,
    );

  if (
    current.status ===
      "STOPPED" ||
    current.status ===
      "STOPPING"
  ) {
    return current;
  }

  return replaceSession({
    ...current,
    status:
      "STOPPING",
    lastTransitionAt:
      new Date().toISOString(),
    lastError:
      null,
  });
}

export function markEncoderStopped(
  gameId: string,
): EncoderSession {
  const current =
    getEncoderSession(
      gameId,
    );

  const now =
    new Date().toISOString();

  return replaceSession({
    ...current,
    status:
      "STOPPED",
    stoppedAt:
      now,
    lastTransitionAt:
      now,
    lastError:
      null,
  });
}

export function markEncoderError(
  gameId: string,
  message: string,
): EncoderSession {
  const current =
    getEncoderSession(
      gameId,
    );

  return replaceSession({
    ...current,
    status:
      "ERROR",
    lastTransitionAt:
      new Date().toISOString(),
    lastError:
      message.trim() ||
      "Encoder session error.",
  });
}
EOF

cat > "$ROUTE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import {
  beginEncoderStart,
  beginEncoderStop,
  getEncoderSession,
  markEncoderStopped,
} from "../services/encoderSession.js";

import {
  getStreamDestinationProfile,
} from "../services/streamDestinationProfile.js";

export async function registerEncoderSessionRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.get(
    "/encoder-sessions/:gameId",
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
          session:
            getEncoderSession(
              gameId,
            ),
        },
      };
    },
  );

  app.post(
    "/encoder-sessions/:gameId/start",
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

      const destination =
        getStreamDestinationProfile(
          gameId,
        );

      if (
        !destination ||
        !destination.enabled
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Enabled stream destination is required before encoder start.",
        });
      }

      if (
        destination.status !==
          "READY" &&
        destination.status !==
          "LIVE"
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Stream destination must be READY before encoder start.",
        });
      }

      const session =
        beginEncoderStart(
          gameId,
        );

      return {
        success: true,
        data: {
          session,
          launchRequired:
            session.status ===
            "STARTING",
        },
      };
    },
  );

  app.post(
    "/encoder-sessions/:gameId/stop",
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

      const current =
        beginEncoderStop(
          gameId,
        );

      /*
       * 20.4 does not launch a real encoder process yet.
       * If nothing is actually running, complete the control transition.
       */
      const session =
        current.status ===
          "STOPPING"
          ? markEncoderStopped(
              gameId,
            )
          : current;

      return {
        success: true,
        data: {
          session,
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
  'import { registerEncoderSessionRoutes } from "./routes/encoderSessions.js";';

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
    "app.register(registerEncoderSessionRoutes)"
  )
) {
  const candidates = [
    "await app.register(registerStreamDestinationProfileRoutes);",
    "await app.register(registerBroadcastSessionProfileRoutes);",
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
      "Unable to locate encoder route registration insertion point.",
    );
  }

  text =
    text.replace(
      marker,
      marker +
        "\n  await app.register(registerEncoderSessionRoutes);",
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
  "apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !text.includes(
    "type EncoderSessionStatus"
  )
) {
  const marker =
    "type StreamDestinationProfile = {";

  const idx =
    text.indexOf(
      marker,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate stream profile type.",
    );
  }

  const types =
`type EncoderSessionStatus =
  | "STOPPED"
  | "STARTING"
  | "LIVE"
  | "STOPPING"
  | "ERROR";

type EncoderSession = {
  gameId: string;
  status: EncoderSessionStatus;
  startedAt: string | null;
  stoppedAt: string | null;
  lastTransitionAt: string;
  lastError: string | null;
};

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    types +
    text.slice(
      idx,
    );
}

if (
  !text.includes(
    "const [encoderSession"
  )
) {
  const marker =
`  const [error, setError] =
    useState<string | null>(
      null,
    );`;

  if (
    !text.includes(
      marker,
    )
  ) {
    throw new Error(
      "Unable to locate StreamDestinationPanel error state.",
    );
  }

  text =
    text.replace(
      marker,
`${marker}

  const [
    encoderSession,
    setEncoderSession,
  ] =
    useState<EncoderSession | null>(
      null,
    );`,
    );
}

if (
  !text.includes(
    "loadEncoderSession"
  )
) {
  const marker =
`  const loadProfile =
    useCallback(`;

  const idx =
    text.indexOf(
      marker,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate loadProfile.",
    );
  }

  const fn =
`  const loadEncoderSession =
    useCallback(
      async (
        targetGameId: string,
      ) => {
        const normalized =
          targetGameId.trim();

        if (!normalized) {
          setEncoderSession(
            null,
          );
          return;
        }

        const response =
          await fetch(
            \`\${API_BASE}/encoder-sessions/\${encodeURIComponent(normalized)}\`,
            {
              cache:
                "no-store",
            },
          );

        if (!response.ok) {
          return;
        }

        const json =
          await response.json();

        setEncoderSession(
          json?.data?.session ??
          null,
        );
      },
      [],
    );

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    fn +
    text.slice(
      idx,
    );
}

if (
  !text.includes(
    "void loadEncoderSession("
  )
) {
  text =
    text.replace(
`          void loadProfile(
            normalized,
          );`,
`          void loadProfile(
            normalized,
          );
          void loadEncoderSession(
            normalized,
          );`,
    );
}

if (
  text.includes(
    "  }, [\n    gameId,\n    loadProfile,\n  ]);"
  )
) {
  text =
    text.replace(
`  }, [
    gameId,
    loadProfile,
  ]);`,
`  }, [
    gameId,
    loadProfile,
    loadEncoderSession,
  ]);`,
    );
}

if (
  !text.includes(
    "async function startEncoderSession"
  )
) {
  const marker =
    "  async function saveProfile() {";

  const idx =
    text.indexOf(
      marker,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate saveProfile.",
    );
  }

  const fns =
`  async function startEncoderSession() {
    const normalized =
      gameId.trim();

    if (!normalized) {
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          \`\${API_BASE}/encoder-sessions/\${encodeURIComponent(normalized)}/start\`,
          {
            method:
              "POST",
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          \`Encoder start failed (\${response.status}).\`,
        );
      }

      setEncoderSession(
        json?.data?.session ??
        null,
      );

      setError(
        null,
      );
    } catch (startError) {
      setError(
        startError instanceof Error
          ? startError.message
          : "Unable to start encoder session.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  async function stopEncoderSession() {
    const normalized =
      gameId.trim();

    if (!normalized) {
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          \`\${API_BASE}/encoder-sessions/\${encodeURIComponent(normalized)}/stop\`,
          {
            method:
              "POST",
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          \`Encoder stop failed (\${response.status}).\`,
        );
      }

      setEncoderSession(
        json?.data?.session ??
        null,
      );

      setError(
        null,
      );
    } catch (stopError) {
      setError(
        stopError instanceof Error
          ? stopError.message
          : "Unable to stop encoder session.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    fns +
    text.slice(
      idx,
    );
}

if (
  !text.includes(
    "Encoder Session"
  )
) {
  const marker =
    `      <div className="mt-4 flex flex-wrap gap-3">`;

  const idx =
    text.indexOf(
      marker,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate StreamDestinationPanel action area.",
    );
  }

  const block =
`      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="font-semibold">
              Encoder Session
            </div>
            <p className="mt-1 text-xs text-slate-500">
              Control-plane state only. Milestone 20.4 does not launch FFmpeg or publish media yet.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-3 py-1 text-xs font-medium">
            {encoderSession?.status ?? "STOPPED"}
          </span>
        </div>

        <div className="mt-3 flex flex-wrap gap-3">
          <button
            type="button"
            disabled={
              busy ||
              !gameId.trim() ||
              profile?.status !==
                "READY" ||
              encoderSession?.status ===
                "STARTING" ||
              encoderSession?.status ===
                "LIVE"
            }
            onClick={() =>
              void startEncoderSession()
            }
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            Arm Encoder Start
          </button>

          <button
            type="button"
            disabled={
              busy ||
              !gameId.trim() ||
              !encoderSession ||
              encoderSession.status ===
                "STOPPED"
            }
            onClick={() =>
              void stopEncoderSession()
            }
            className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
          >
            Stop Encoder Session
          </button>
        </div>

        {encoderSession?.lastError && (
          <p className="mt-3 text-xs text-red-300">
            Encoder status: {encoderSession.lastError}
          </p>
        )}
      </div>

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    block +
    text.slice(
      idx,
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 20.4 — Encoder session model and control foundation

SportsOS now has a persisted encoder-session control model.

States:

```text
STOPPED
STARTING
LIVE
STOPPING
ERROR
```

Operator API:

```text
GET  /encoder-sessions/:gameId
POST /encoder-sessions/:gameId/start
POST /encoder-sessions/:gameId/stop
```

Start is blocked unless the stream destination is enabled and `READY`.

Milestone 20.4 is intentionally **control-plane only**. It does not:

- spawn FFmpeg
- resolve stream credentials
- publish media
- mark a session LIVE automatically

The start action arms the session as `STARTING`. A later milestone will connect this model to an actual encoder runtime and explicitly promote the session to `LIVE` only after the runtime confirms publishing.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.4 encoder session model / start-stop control foundation", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/encoderSession.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/encoderSessions.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("defines encoder lifecycle states", () => {
    for (const state of [
      "STOPPED",
      "STARTING",
      "LIVE",
      "STOPPING",
      "ERROR",
    ]) {
      expect(service).toContain(
        `"${state}"`,
      );
    }
  });

  it("persists encoder sessions separately from stream destinations", () => {
    expect(service).toContain(
      "encoder-sessions.json",
    );
  });

  it("blocks start until destination is ready", () => {
    expect(route).toContain(
      'destination.status !==\n          "READY"',
    );

    expect(route).toContain(
      "Stream destination must be READY before encoder start.",
    );
  });

  it("provides start and stop control routes", () => {
    expect(route).toContain(
      '"/encoder-sessions/:gameId/start"',
    );

    expect(route).toContain(
      '"/encoder-sessions/:gameId/stop"',
    );
  });

  it("provides operator encoder controls", () => {
    expect(panel).toContain(
      "Encoder Session",
    );

    expect(panel).toContain(
      "Arm Encoder Start",
    );

    expect(panel).toContain(
      "Stop Encoder Session",
    );
  });

  it("does not launch media processes in this milestone", () => {
    expect(service).not.toContain(
      "child_process",
    );

    expect(route).not.toContain(
      "ffmpeg",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 20.4 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - persisted encoder session model"
echo "  - STOPPED/STARTING/LIVE/STOPPING/ERROR states"
echo "  - destination-ready start guard"
echo "  - start/stop control API"
echo "  - operator encoder controls"
echo "  - no FFmpeg/media process launch yet"
echo "  - Milestone 20.4 regression tests"
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
echo "  Milestone 20.5 - Encoder Runtime Adapter / FFmpeg Process Control"
