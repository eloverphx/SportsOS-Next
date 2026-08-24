#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-21.1-go-live-session-foundation-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "apps/api/src/services/streamingReadinessPreflight.ts" \
  "apps/api/src/services/encoderSession.ts" \
  "apps/api/src/routes/encoderSessions.ts" \
  "apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx" \
  "docs/MILESTONE-STATUS.md"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

SERVICE="apps/api/src/services/goLiveSession.ts"
ROUTE="apps/api/src/routes/goLiveSessions.ts"
APP="apps/api/src/app.ts"
PANEL="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
TEST="packages/core/test/go-live-session-foundation-21.1.test.ts"
DOC="docs/GO-LIVE-OPERATIONS.md"
STATUS="docs/MILESTONE-STATUS.md"

for file in "$SERVICE" "$ROUTE" "$APP" "$PANEL" "$TEST" "$DOC" "$STATUS"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$ROUTE")" "$(dirname "$TEST")" docs

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type GoLiveSessionStatus =
  | "IDLE"
  | "ARMED"
  | "STARTING"
  | "LIVE"
  | "STOPPING"
  | "COMPLETE"
  | "ERROR";

export type GoLiveSession = {
  gameId: string;
  status: GoLiveSessionStatus;
  armedAt: string | null;
  startedAt: string | null;
  liveAt: string | null;
  stoppedAt: string | null;
  completedAt: string | null;
  lastTransitionAt: string;
  lastError: string | null;
};

type Store = {
  version: 1;
  sessions: GoLiveSession[];
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
    "go-live-sessions.json",
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
        "Invalid go-live session store.",
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
  session: GoLiveSession,
): GoLiveSession {
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

export function getGoLiveSession(
  gameId: string,
): GoLiveSession {
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
      "IDLE",
    armedAt:
      null,
    startedAt:
      null,
    liveAt:
      null,
    stoppedAt:
      null,
    completedAt:
      null,
    lastTransitionAt:
      now,
    lastError:
      null,
  };
}

export function armGoLiveSession(
  gameId: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  if (
    current.status ===
      "ARMED" ||
    current.status ===
      "STARTING" ||
    current.status ===
      "LIVE"
  ) {
    return current;
  }

  const now =
    new Date().toISOString();

  return replaceSession({
    ...current,
    status:
      "ARMED",
    armedAt:
      now,
    startedAt:
      null,
    liveAt:
      null,
    stoppedAt:
      null,
    completedAt:
      null,
    lastTransitionAt:
      now,
    lastError:
      null,
  });
}

export function markGoLiveStarting(
  gameId: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  const now =
    new Date().toISOString();

  return replaceSession({
    ...current,
    status:
      "STARTING",
    startedAt:
      current.startedAt ??
      now,
    lastTransitionAt:
      now,
    lastError:
      null,
  });
}

export function markGoLiveLive(
  gameId: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  const now =
    new Date().toISOString();

  return replaceSession({
    ...current,
    status:
      "LIVE",
    liveAt:
      current.liveAt ??
      now,
    lastTransitionAt:
      now,
    lastError:
      null,
  });
}

export function markGoLiveStopping(
  gameId: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  return replaceSession({
    ...current,
    status:
      "STOPPING",
    stoppedAt:
      null,
    lastTransitionAt:
      new Date().toISOString(),
    lastError:
      null,
  });
}

export function completeGoLiveSession(
  gameId: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  const now =
    new Date().toISOString();

  return replaceSession({
    ...current,
    status:
      "COMPLETE",
    stoppedAt:
      now,
    completedAt:
      now,
    lastTransitionAt:
      now,
    lastError:
      null,
  });
}

export function markGoLiveError(
  gameId: string,
  message: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
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
      "Go-live session error.",
  });
}

export function resetGoLiveSession(
  gameId: string,
): GoLiveSession {
  const now =
    new Date().toISOString();

  return replaceSession({
    gameId,
    status:
      "IDLE",
    armedAt:
      null,
    startedAt:
      null,
    liveAt:
      null,
    stoppedAt:
      null,
    completedAt:
      null,
    lastTransitionAt:
      now,
    lastError:
      null,
  });
}
EOF

cat > "$ROUTE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import {
  armGoLiveSession,
  completeGoLiveSession,
  getGoLiveSession,
  markGoLiveError,
  markGoLiveLive,
  markGoLiveStarting,
  markGoLiveStopping,
  resetGoLiveSession,
} from "../services/goLiveSession.js";

import {
  evaluateStreamingReadiness,
} from "../services/streamingReadinessPreflight.js";

import {
  encoderRuntimeSnapshot,
  startEncoderRuntime,
  stopEncoderRuntime,
} from "../services/encoderRuntime.js";

import {
  getStreamDestinationProfile,
} from "../services/streamDestinationProfile.js";

export async function registerGoLiveSessionRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.get(
    "/go-live-sessions/:gameId",
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
            getGoLiveSession(
              gameId,
            ),
        },
      };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/arm",
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

      const preflight =
        evaluateStreamingReadiness(
          gameId,
        );

      if (!preflight.ready) {
        return reply.code(409).send({
          success: false,
          error:
            "Streaming readiness preflight must pass before arming go-live.",
          data: {
            preflight,
          },
        });
      }

      return {
        success: true,
        data: {
          session:
            armGoLiveSession(
              gameId,
            ),
          preflight,
        },
      };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/start",
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
        getGoLiveSession(
          gameId,
        );

      if (
        current.status !==
        "ARMED"
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Go-live session must be ARMED before start.",
        });
      }

      const preflight =
        evaluateStreamingReadiness(
          gameId,
        );

      if (!preflight.ready) {
        return reply.code(409).send({
          success: false,
          error:
            "Streaming readiness preflight failed before go-live start.",
          data: {
            preflight,
          },
        });
      }

      const destination =
        getStreamDestinationProfile(
          gameId,
        );

      if (!destination) {
        return reply.code(409).send({
          success: false,
          error:
            "Stream destination is missing.",
        });
      }

      markGoLiveStarting(
        gameId,
      );

      try {
        await startEncoderRuntime({
          gameId,
          destination,
        });
      } catch (error) {
        const message =
          error instanceof Error
            ? error.message
            : "Unable to start encoder runtime.";

        const session =
          markGoLiveError(
            gameId,
            message,
          );

        return reply.code(500).send({
          success: false,
          error:
            message,
          data: {
            session,
          },
        });
      }

      return {
        success: true,
        data: {
          session:
            getGoLiveSession(
              gameId,
            ),
          runtime:
            encoderRuntimeSnapshot(
              gameId,
            ),
        },
      };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/confirm-live",
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

      const runtime =
        encoderRuntimeSnapshot(
          gameId,
        );

      if (
        runtime.session.status !==
          "LIVE" ||
        runtime.telemetry.health !==
          "HEALTHY"
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Encoder must be LIVE with HEALTHY publish telemetry before go-live confirmation.",
          data: {
            runtime,
          },
        });
      }

      return {
        success: true,
        data: {
          session:
            markGoLiveLive(
              gameId,
            ),
          runtime,
        },
      };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/stop",
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

      markGoLiveStopping(
        gameId,
      );

      await stopEncoderRuntime(
        gameId,
      );

      return {
        success: true,
        data: {
          session:
            completeGoLiveSession(
              gameId,
            ),
          runtime:
            encoderRuntimeSnapshot(
              gameId,
            ),
        },
      };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/reset",
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
            resetGoLiveSession(
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
  'import { registerGoLiveSessionRoutes } from "./routes/goLiveSessions.js";';

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
    "app.register(registerGoLiveSessionRoutes)"
  )
) {
  const candidates = [
    "await app.register(registerEncoderSessionRoutes);",
    "await app.register(registerStreamDestinationProfileRoutes);",
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
      "Unable to locate go-live route registration insertion point.",
    );
  }

  text =
    text.replace(
      marker,
      marker +
        "\n  await app.register(registerGoLiveSessionRoutes);",
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
    "type GoLiveSession ="
  )
) {
  const marker =
    "type StreamingReadinessPreflight = {";

  const idx =
    text.indexOf(
      marker,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate streaming preflight type.",
    );
  }

  const type =
`type GoLiveSession = {
  gameId: string;
  status:
    | "IDLE"
    | "ARMED"
    | "STARTING"
    | "LIVE"
    | "STOPPING"
    | "COMPLETE"
    | "ERROR";
  armedAt: string | null;
  startedAt: string | null;
  liveAt: string | null;
  stoppedAt: string | null;
  completedAt: string | null;
  lastTransitionAt: string;
  lastError: string | null;
};

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    type +
    text.slice(
      idx,
    );
}

if (
  !text.includes(
    "const [goLiveSession"
  )
) {
  const marker =
`  const [
    streamingPreflight,
    setStreamingPreflight,
  ] =
    useState<StreamingReadinessPreflight | null>(
      null,
    );`;

  if (
    !text.includes(
      marker,
    )
  ) {
    throw new Error(
      "Unable to locate streaming preflight state.",
    );
  }

  text =
    text.replace(
      marker,
`${marker}

  const [
    goLiveSession,
    setGoLiveSession,
  ] =
    useState<GoLiveSession | null>(
      null,
    );`,
    );
}

if (
  !text.includes(
    "async function loadGoLiveSession"
  )
) {
  const marker =
    "  async function runStreamingPreflight() {";

  const idx =
    text.indexOf(
      marker,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate runStreamingPreflight.",
    );
  }

  const fn =
    '  async function loadGoLiveSession() {\n' +
    '    const normalized = gameId.trim();\n' +
    '    if (!normalized) return;\n' +
    '    const response = await fetch(\n' +
    '      `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}`,\n' +
    '      { cache: "no-store" },\n' +
    '    );\n' +
    '    if (!response.ok) return;\n' +
    '    const json = await response.json();\n' +
    '    setGoLiveSession(json?.data?.session ?? null);\n' +
    '  }\n\n' +
    '  async function goLiveAction(action: "arm" | "start" | "confirm-live" | "stop" | "reset") {\n' +
    '    const normalized = gameId.trim();\n' +
    '    if (!normalized) return;\n' +
    '    setBusy(true);\n' +
    '    try {\n' +
    '      const response = await fetch(\n' +
    '        `${API_BASE}/go-live-sessions/${encodeURIComponent(normalized)}/${action}`,\n' +
    '        { method: "POST" },\n' +
    '      );\n' +
    '      const json = await response.json();\n' +
    '      if (!response.ok) {\n' +
    '        throw new Error(json?.error ?? `Go-live action failed (${response.status}).`);\n' +
    '      }\n' +
    '      setGoLiveSession(json?.data?.session ?? null);\n' +
    '      setError(null);\n' +
    '    } catch (actionError) {\n' +
    '      setError(\n' +
    '        actionError instanceof Error\n' +
    '          ? actionError.message\n' +
    '          : "Unable to complete go-live action.",\n' +
    '      );\n' +
    '    } finally {\n' +
    '      setBusy(false);\n' +
    '    }\n' +
    '  }\n\n';

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
    "Production Go-Live"
  )
) {
  const marker =
`      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="font-semibold">
              Streaming Readiness`;

  const idx =
    text.indexOf(
      marker,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate streaming readiness panel.",
    );
  }

  const block =
`      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="font-semibold">
              Production Go-Live
            </div>
            <p className="mt-1 text-xs text-slate-500">
              Orchestrates readiness and encoder state without duplicating game-state authority.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-3 py-1 text-xs font-medium">
            {goLiveSession?.status ?? "IDLE"}
          </span>
        </div>

        <div className="mt-4 flex flex-wrap gap-3">
          <button
            type="button"
            disabled={
              busy ||
              !gameId.trim()
            }
            onClick={() =>
              void loadGoLiveSession()
            }
            className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
          >
            Refresh Go-Live State
          </button>

          <button
            type="button"
            disabled={
              busy ||
              !streamingPreflight?.ready ||
              (
                goLiveSession?.status != null &&
                goLiveSession.status !== "IDLE" &&
                goLiveSession.status !== "COMPLETE" &&
                goLiveSession.status !== "ERROR"
              )
            }
            onClick={() =>
              void goLiveAction("arm")
            }
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            Arm Go-Live
          </button>

          <button
            type="button"
            disabled={
              busy ||
              goLiveSession?.status !== "ARMED"
            }
            onClick={() =>
              void goLiveAction("start")
            }
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            Start Go-Live
          </button>

          <button
            type="button"
            disabled={
              busy ||
              goLiveSession?.status !== "STARTING"
            }
            onClick={() =>
              void goLiveAction("confirm-live")
            }
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            Confirm Live
          </button>

          <button
            type="button"
            disabled={
              busy ||
              (
                goLiveSession?.status !== "STARTING" &&
                goLiveSession?.status !== "LIVE"
              )
            }
            onClick={() =>
              void goLiveAction("stop")
            }
            className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
          >
            Stop Go-Live
          </button>

          <button
            type="button"
            disabled={
              busy ||
              !goLiveSession ||
              (
                goLiveSession.status !== "COMPLETE" &&
                goLiveSession.status !== "ERROR"
              )
            }
            onClick={() =>
              void goLiveAction("reset")
            }
            className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
          >
            Reset Go-Live
          </button>
        </div>

        {goLiveSession?.lastError && (
          <p className="mt-3 text-xs text-red-300">
            Go-live status: {goLiveSession.lastError}
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

cat > "$DOC" <<'EOF'
# Go-Live Operations

Milestone 21 begins the production go-live orchestration layer.

## Milestone 21.1 — Go-live session foundation

Go-live session states:

```text
IDLE
ARMED
STARTING
LIVE
STOPPING
COMPLETE
ERROR
```

The go-live layer orchestrates existing streaming readiness and encoder runtime capabilities.

It does not become authoritative for game state.

## Operator flow

```text
streaming preflight PASS
        ↓
ARMED
        ↓
STARTING
        ↓
encoder LIVE + publish HEALTHY
        ↓
LIVE
        ↓
STOPPING
        ↓
COMPLETE
```

## API

```text
GET  /go-live-sessions/:gameId
POST /go-live-sessions/:gameId/arm
POST /go-live-sessions/:gameId/start
POST /go-live-sessions/:gameId/confirm-live
POST /go-live-sessions/:gameId/stop
POST /go-live-sessions/:gameId/reset
```

Arming requires a passing streaming readiness preflight.

Start requires ARMED plus a fresh passing readiness preflight.

Live confirmation requires encoder state `LIVE` and publish telemetry health `HEALTHY`.
EOF

cat >> "$STATUS" <<'EOF'

### Milestone 21

Production streaming orchestration and game-day go-live.

Current work:

- 21.1 production go-live session foundation
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 21.1 production go-live session foundation", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/goLiveSession.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/goLiveSessions.ts",
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

  it("defines production go-live lifecycle states", () => {
    for (const state of [
      "IDLE",
      "ARMED",
      "STARTING",
      "LIVE",
      "STOPPING",
      "COMPLETE",
      "ERROR",
    ]) {
      expect(service).toContain(
        `"${state}"`,
      );
    }
  });

  it("persists go-live sessions separately", () => {
    expect(service).toContain(
      "go-live-sessions.json",
    );
  });

  it("requires streaming readiness before arming and start", () => {
    expect(route).toContain(
      "evaluateStreamingReadiness",
    );

    expect(route).toContain(
      "Streaming readiness preflight must pass before arming go-live.",
    );

    expect(route).toContain(
      "Streaming readiness preflight failed before go-live start.",
    );
  });

  it("requires encoder live plus healthy telemetry before confirmation", () => {
    expect(route).toContain(
      'runtime.session.status !==\n          "LIVE"',
    );

    expect(route).toContain(
      'runtime.telemetry.health !==\n          "HEALTHY"',
    );
  });

  it("provides operator go-live controls", () => {
    expect(panel).toContain(
      "Production Go-Live",
    );

    expect(panel).toContain(
      "Arm Go-Live",
    );

    expect(panel).toContain(
      "Start Go-Live",
    );

    expect(panel).toContain(
      "Confirm Live",
    );

    expect(panel).toContain(
      "Stop Go-Live",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 21.1 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - persisted production go-live session"
echo "  - IDLE/ARMED/STARTING/LIVE/STOPPING/COMPLETE/ERROR states"
echo "  - streaming-preflight arm/start guards"
echo "  - healthy publish confirmation gate"
echo "  - stop/reset orchestration"
echo "  - operator go-live controls"
echo "  - Milestone 21.1 regression tests"
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
echo "  Milestone 21.2 - Scheduled Go-Live / Start Window Foundation"
