#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-20.8-encoder-audit-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

AUDIT="apps/api/src/services/encoderRuntimeAudit.ts"
RUNTIME="apps/api/src/services/encoderRuntime.ts"
ROUTE="apps/api/src/routes/encoderSessions.ts"
PANEL="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
TEST="packages/core/test/encoder-runtime-audit-20.8.test.ts"
DOC="docs/STREAMING-OPERATIONS.md"

for required in \
  ".git" \
  "$RUNTIME" \
  "$ROUTE" \
  "$PANEL"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$AUDIT" "$RUNTIME" "$ROUTE" "$PANEL" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$AUDIT")" "$(dirname "$TEST")"

cat > "$AUDIT" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type EncoderAuditEventType =
  | "START_REQUESTED"
  | "RUNTIME_STARTED"
  | "RUNTIME_LIVE"
  | "STOP_REQUESTED"
  | "RUNTIME_STOPPED"
  | "RUNTIME_ERROR"
  | "RESTART_SCHEDULED"
  | "RESTARTING"
  | "RESTART_EXHAUSTED";

export type EncoderAuditEvent = {
  id: string;
  gameId: string;
  type: EncoderAuditEventType;
  timestamp: string;
  detail: string | null;
  attempt: number | null;
};

type Store = {
  version: 1;
  events: EncoderAuditEvent[];
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
    "encoder-runtime-audit.json",
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
        parsed.events,
      )
    ) {
      throw new Error(
        "Invalid encoder runtime audit store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      events: [],
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

  fs.writeFileSync(
    STORE_FILE,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );
}

export function recordEncoderAuditEvent(input: {
  gameId: string;
  type: EncoderAuditEventType;
  detail?: string | null;
  attempt?: number | null;
}): EncoderAuditEvent {
  const timestamp =
    new Date().toISOString();

  const event: EncoderAuditEvent = {
    id:
      `encoder-audit-${input.gameId}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    gameId:
      input.gameId,
    type:
      input.type,
    timestamp,
    detail:
      input.detail ??
      null,
    attempt:
      input.attempt ??
      null,
  };

  store.events.push(
    event,
  );

  if (
    store.events.length >
    1000
  ) {
    store.events =
      store.events.slice(
        -1000,
      );
  }

  persistStore();

  return {
    ...event,
  };
}

export function listEncoderAuditEvents(
  gameId: string,
  limit = 50,
): EncoderAuditEvent[] {
  const safeLimit =
    Math.max(
      1,
      Math.min(
        Math.floor(
          limit,
        ),
        200,
      ),
    );

  return store.events
    .filter(
      (event) =>
        event.gameId ===
        gameId,
    )
    .slice(
      -safeLimit,
    )
    .reverse()
    .map(
      (event) => ({
        ...event,
      }),
    );
}
EOF

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/services/encoderRuntime.ts";
let text = fs.readFileSync(file, "utf8");

const auditImport =
  'import { recordEncoderAuditEvent } from "./encoderRuntimeAudit.js";';

if (!text.includes(auditImport)) {
  const imports =
    text.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate encoder runtime imports.",
    );
  }

  text =
    text.replace(
      imports[0],
      imports[0] +
        auditImport +
        "\n",
    );
}

const injections = [
  [
    `  recovery.set(
    input.gameId,
    {
      gameId:
        input.gameId,
      state:
        "SCHEDULED",`,
    `  recordEncoderAuditEvent({
    gameId:
      input.gameId,
    type:
      "RESTART_SCHEDULED",
    attempt:
      nextAttempt,
    detail:
      \`Retry in \${delayMs} ms.\`,
  });

  recovery.set(
    input.gameId,
    {
      gameId:
        input.gameId,
      state:
        "SCHEDULED",`,
  ],
  [
    `      recovery.set(
        input.gameId,
        {
          ...snapshot,
          state:
            "RESTARTING",`,
    `      recordEncoderAuditEvent({
        gameId:
          input.gameId,
        type:
          "RESTARTING",
        attempt:
          nextAttempt,
      });

      recovery.set(
        input.gameId,
        {
          ...snapshot,
          state:
            "RESTARTING",`,
  ],
  [
    `    recovery.set(
      input.gameId,
      {
        ...current,
        state: "EXHAUSTED",`,
    `    recordEncoderAuditEvent({
      gameId:
        input.gameId,
      type:
        "RESTART_EXHAUSTED",
      attempt:
        current.attempt,
    });

    recovery.set(
      input.gameId,
      {
        ...current,
        state: "EXHAUSTED",`,
  ],
];

for (const [from, to] of injections) {
  if (
    text.includes(from) &&
    !text.includes(to)
  ) {
    text =
      text.replace(
        from,
        to,
      );
  }
}

if (!text.includes('"RUNTIME_STARTED"')) {
  const marker =
`  runtimes.set(
    input.gameId,
    entry,
  );`;

  text =
    text.replace(
      marker,
`${marker}

  recordEncoderAuditEvent({
    gameId:
      input.gameId,
    type:
      "RUNTIME_STARTED",
  });`,
    );
}

if (!text.includes('"RUNTIME_LIVE"')) {
  const marker =
`          markEncoderLive(
            input.gameId,
          );`;

  text =
    text.replace(
      marker,
`${marker}

          recordEncoderAuditEvent({
            gameId:
              input.gameId,
            type:
              "RUNTIME_LIVE",
          });`,
    );
}

if (!text.includes('"RUNTIME_STOPPED"')) {
  const marker =
`        markEncoderStopped(
          input.gameId,
        );`;

  text =
    text.replace(
      marker,
`${marker}

        recordEncoderAuditEvent({
          gameId:
            input.gameId,
          type:
            "RUNTIME_STOPPED",
        });`,
    );
}

if (!text.includes('"RUNTIME_ERROR"')) {
  const marker =
`      markEncoderError(
        input.gameId,`;

  const idx =
    text.indexOf(marker);

  if (idx !== -1) {
    const insert =
`      recordEncoderAuditEvent({
        gameId:
          input.gameId,
        type:
          "RUNTIME_ERROR",
        detail:
          sanitizedMessage(
            error,
          ),
      });

`;
    text =
      text.slice(0, idx) +
      insert +
      text.slice(idx);
  }
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/routes/encoderSessions.ts";
let text = fs.readFileSync(file, "utf8");

const auditImport =
  'import { listEncoderAuditEvents, recordEncoderAuditEvent } from "../services/encoderRuntimeAudit.js";';

if (!text.includes(auditImport)) {
  const imports =
    text.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate encoder route imports.",
    );
  }

  text =
    text.replace(
      imports[0],
      imports[0] +
        auditImport +
        "\n",
    );
}

if (!text.includes('"START_REQUESTED"')) {
  const marker =
`      beginEncoderStart(
        gameId,
      );`;

  text =
    text.replace(
      marker,
`      recordEncoderAuditEvent({
        gameId,
        type:
          "START_REQUESTED",
      });

${marker}`,
    );
}

if (!text.includes('"STOP_REQUESTED"')) {
  const marker =
`      beginEncoderStop(
        gameId,
      );`;

  text =
    text.replace(
      marker,
`      recordEncoderAuditEvent({
        gameId,
        type:
          "STOP_REQUESTED",
      });

${marker}`,
    );
}

if (!text.includes('"/encoder-sessions/:gameId/audit"')) {
  const marker =
`  app.get(
    "/encoder-sessions/:gameId/telemetry",`;

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate telemetry route.",
    );
  }

  const route =
`  app.get(
    "/encoder-sessions/:gameId/audit",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const query =
        request.query as {
          limit?: string;
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

      const limit =
        Number.parseInt(
          query.limit ??
            "50",
          10,
        );

      return {
        success: true,
        data: {
          events:
            listEncoderAuditEvents(
              gameId,
              Number.isFinite(limit)
                ? limit
                : 50,
            ),
        },
      };
    },
  );

`;

  text =
    text.slice(0, idx) +
    route +
    text.slice(idx);
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file = "apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("type EncoderAuditEvent =")) {
  const marker = "type EncoderRecoverySnapshot = {";
  const idx = text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate recovery type.",
    );
  }

  const type =
`type EncoderAuditEvent = {
  id: string;
  gameId: string;
  type:
    | "START_REQUESTED"
    | "RUNTIME_STARTED"
    | "RUNTIME_LIVE"
    | "STOP_REQUESTED"
    | "RUNTIME_STOPPED"
    | "RUNTIME_ERROR"
    | "RESTART_SCHEDULED"
    | "RESTARTING"
    | "RESTART_EXHAUSTED";
  timestamp: string;
  detail: string | null;
  attempt: number | null;
};

`;

  text =
    text.slice(0, idx) +
    type +
    text.slice(idx);
}

if (!text.includes("const [encoderAudit")) {
  const marker =
`  const [
    encoderRecovery,
    setEncoderRecovery,
  ] =
    useState<EncoderRecoverySnapshot | null>(
      null,
    );`;

  if (!text.includes(marker)) {
    throw new Error(
      "Unable to locate recovery state.",
    );
  }

  text =
    text.replace(
      marker,
`${marker}

  const [
    encoderAudit,
    setEncoderAudit,
  ] =
    useState<EncoderAuditEvent[]>(
      [],
    );`,
    );
}

if (!text.includes("/audit?limit=12")) {
  const marker =
`          setEncoderRecovery(json?.data?.recovery ?? null);`;

  if (!text.includes(marker)) {
    throw new Error(
      "Unable to locate telemetry polling updates.",
    );
  }

  text =
    text.replace(
      marker,
`${marker}

          void fetch(
            \`\${API_BASE}/encoder-sessions/\${encodeURIComponent(normalized)}/audit?limit=12\`,
            {
              cache:
                "no-store",
            },
          )
            .then(
              (response) =>
                response.json(),
            )
            .then(
              (auditJson) => {
                setEncoderAudit(
                  auditJson?.data?.events ??
                  [],
                );
              },
            )
            .catch(
              () => {
                // Audit history failure must not affect encoder controls.
              },
            );`,
    );
}

if (!text.includes("Encoder Runtime History")) {
  const marker =
`        <div className="mt-4 grid gap-3 sm:grid-cols-3">`;

  const idx =
    text.lastIndexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate recovery cards.",
    );
  }

  const sectionEnd =
    text.indexOf(
      "\n      </div>",
      idx,
    );

  if (sectionEnd === -1) {
    throw new Error(
      "Unable to locate encoder section end.",
    );
  }

  const block =
`
        <div className="mt-5">
          <div className="text-sm font-semibold">
            Encoder Runtime History
          </div>

          <div className="mt-2 space-y-2">
            {encoderAudit.length === 0 ? (
              <div className="rounded border border-slate-800 p-3 text-xs text-slate-500">
                No encoder runtime events recorded.
              </div>
            ) : (
              encoderAudit.map(
                (event) => (
                  <div
                    key={event.id}
                    className="rounded border border-slate-800 p-3"
                  >
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <span className="text-xs font-semibold">
                        {event.type}
                      </span>
                      <span className="text-xs text-slate-500">
                        {event.timestamp}
                      </span>
                    </div>

                    {event.detail && (
                      <div className="mt-1 text-xs text-slate-400">
                        {event.detail}
                      </div>
                    )}

                    {event.attempt != null && (
                      <div className="mt-1 text-xs text-slate-500">
                        Attempt {event.attempt}
                      </div>
                    )}
                  </div>
                ),
              )
            )}
          </div>
        </div>
`;

  text =
    text.slice(0, sectionEnd) +
    block +
    text.slice(sectionEnd);
}

fs.writeFileSync(file, text);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 20.8 — Encoder runtime audit and failure history

SportsOS now persists encoder lifecycle and recovery events.

Audit event types:

```text
START_REQUESTED
RUNTIME_STARTED
RUNTIME_LIVE
STOP_REQUESTED
RUNTIME_STOPPED
RUNTIME_ERROR
RESTART_SCHEDULED
RESTARTING
RESTART_EXHAUSTED
```

API:

```text
GET /encoder-sessions/:gameId/audit?limit=50
```

The audit store is bounded to the newest 1000 events globally and the API limits a single request to 200 events.

The operator UI shows recent encoder runtime history alongside telemetry and recovery state.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.8 encoder runtime audit / failure history", () => {
  const audit =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/encoderRuntimeAudit.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const runtime =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/encoderRuntime.ts",
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

  it("persists bounded encoder audit history", () => {
    expect(audit).toContain(
      "encoder-runtime-audit.json",
    );

    expect(audit).toContain(
      "1000",
    );
  });

  it("records runtime and recovery events", () => {
    for (const event of [
      "RUNTIME_STARTED",
      "RUNTIME_LIVE",
      "RUNTIME_STOPPED",
      "RUNTIME_ERROR",
      "RESTART_SCHEDULED",
      "RESTARTING",
      "RESTART_EXHAUSTED",
    ]) {
      expect(runtime).toContain(
        `"${event}"`,
      );
    }
  });

  it("records operator start and stop requests", () => {
    expect(route).toContain(
      '"START_REQUESTED"',
    );

    expect(route).toContain(
      '"STOP_REQUESTED"',
    );
  });

  it("provides an audit endpoint", () => {
    expect(route).toContain(
      '"/encoder-sessions/:gameId/audit"',
    );

    expect(route).toContain(
      "listEncoderAuditEvents",
    );
  });

  it("shows encoder history in the operator UI", () => {
    expect(panel).toContain(
      "Encoder Runtime History",
    );

    expect(panel).toContain(
      "/audit?limit=12",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 20.8 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - persistent encoder runtime audit history"
echo "  - start/stop request audit"
echo "  - runtime start/live/stop/error audit"
echo "  - restart scheduled/restarting/exhausted audit"
echo "  - audit API"
echo "  - operator runtime-history panel"
echo "  - bounded audit retention"
echo "  - Milestone 20.8 regression tests"
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
echo "  Milestone 20.9 - Streaming Readiness / Operator Preflight"
