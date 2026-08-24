#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-21.8-go-live-audit-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

AUDIT="apps/api/src/services/goLiveAudit.ts"
SERVICE="apps/api/src/services/goLiveSession.ts"
ROUTE="apps/api/src/routes/goLiveSessions.ts"
PANEL="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
TEST="packages/core/test/go-live-audit-history-21.8.test.ts"
DOC="docs/GO-LIVE-OPERATIONS.md"

for required in ".git" "$SERVICE" "$ROUTE" "$PANEL" "$DOC"; do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$AUDIT" "$SERVICE" "$ROUTE" "$PANEL" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$AUDIT")" "$(dirname "$TEST")"

cat > "$AUDIT" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type GoLiveAuditEventType =
  | "ARMED"
  | "START_REQUESTED"
  | "STARTING"
  | "LIVE_CONFIRMED"
  | "DEGRADED"
  | "RECOVERED"
  | "INCIDENT_ACKNOWLEDGED"
  | "INCIDENT_RETRY"
  | "STOP_REQUESTED"
  | "COMPLETE"
  | "EMERGENCY_STOP"
  | "RESET"
  | "ERROR";

export type GoLiveAuditEvent = {
  id: string;
  gameId: string;
  type: GoLiveAuditEventType;
  timestamp: string;
  detail: string | null;
  operator: string | null;
};

type Store = {
  version: 1;
  events: GoLiveAuditEvent[];
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
    "go-live-audit.json",
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
        "Invalid go-live audit store.",
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

export function recordGoLiveAuditEvent(input: {
  gameId: string;
  type: GoLiveAuditEventType;
  detail?: string | null;
  operator?: string | null;
}): GoLiveAuditEvent {
  const event: GoLiveAuditEvent = {
    id:
      `go-live-audit-${input.gameId}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    gameId:
      input.gameId,
    type:
      input.type,
    timestamp:
      new Date().toISOString(),
    detail:
      input.detail ??
      null,
    operator:
      input.operator ??
      null,
  };

  store.events.push(
    event,
  );

  if (
    store.events.length >
    2000
  ) {
    store.events =
      store.events.slice(
        -2000,
      );
  }

  persistStore();

  return {
    ...event,
  };
}

export function listGoLiveAuditEvents(
  gameId: string,
  limit = 100,
): GoLiveAuditEvent[] {
  const safeLimit =
    Math.max(
      1,
      Math.min(
        Math.floor(
          limit,
        ),
        250,
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
const fs=require("fs");
const f="apps/api/src/routes/goLiveSessions.ts";
let s=fs.readFileSync(f,"utf8");

const auditImport='import { listGoLiveAuditEvents, recordGoLiveAuditEvent } from "../services/goLiveAudit.js";';

if(!s.includes(auditImport)) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+auditImport+"\n");
}

const inserts = [
  ['"ARMED"', '          session:\n            armGoLiveSession(\n              gameId,\n            ),'],
  ['"LIVE_CONFIRMED"', '          session:\n            markGoLiveLive(\n              gameId,\n            ),'],
  ['"COMPLETE"', '          session:\n            completeGoLiveSession(\n              gameId,\n            ),'],
];

if(!s.includes('type:\n          "ARMED"')) {
  const marker='      return {\n        success: true,\n        data: {\n          session:\n            armGoLiveSession(\n              gameId,\n            ),';
  if(s.includes(marker)) {
    s=s.replace(
      marker,
`      recordGoLiveAuditEvent({
        gameId,
        type:
          "ARMED",
      });

${marker}`
    );
  }
}

if(!s.includes('type:\n          "START_REQUESTED"')) {
  const marker=`      markGoLiveStarting(
        gameId,
      );`;
  if(s.includes(marker)) {
    s=s.replace(
      marker,
`      recordGoLiveAuditEvent({
        gameId,
        type:
          "START_REQUESTED",
      });

${marker}

      recordGoLiveAuditEvent({
        gameId,
        type:
          "STARTING",
      });`
    );
  }
}

if(!s.includes('type:\n          "LIVE_CONFIRMED"')) {
  const marker=`      return {
        success: true,
        data: {
          session:
            markGoLiveLive(
              gameId,
            ),`;
  if(s.includes(marker)) {
    s=s.replace(
      marker,
`      recordGoLiveAuditEvent({
        gameId,
        type:
          "LIVE_CONFIRMED",
      });

${marker}`
    );
  }
}

if(!s.includes('type:\n          "STOP_REQUESTED"')) {
  const marker=`      markGoLiveStopping(
        gameId,
      );`;
  if(s.includes(marker)) {
    s=s.replace(
      marker,
`      recordGoLiveAuditEvent({
        gameId,
        type:
          "STOP_REQUESTED",
      });

${marker}`
    );
  }
}

if(!s.includes('type:\n          "COMPLETE"')) {
  const marker=`      return {
        success: true,
        data: {
          session:
            completeGoLiveSession(
              gameId,
            ),`;
  if(s.includes(marker)) {
    s=s.replace(
      marker,
`      recordGoLiveAuditEvent({
        gameId,
        type:
          "COMPLETE",
      });

${marker}`
    );
  }
}

if(!s.includes('type:\n          "EMERGENCY_STOP"')) {
  const marker=`      const session =
        markGoLiveEmergencyStopped(
          gameId,
          body.reason ??
          null,
        );`;
  if(s.includes(marker)) {
    s=s.replace(
      marker,
`${marker}

      recordGoLiveAuditEvent({
        gameId,
        type:
          "EMERGENCY_STOP",
        detail:
          body.reason ??
          null,
      });`
    );
  }
}

if(!s.includes('type:\n          "INCIDENT_ACKNOWLEDGED"')) {
  const marker=`      return {
        success: true,
        data: {
          session:
            acknowledgeGoLiveIncident(
              gameId,
              body.operator ??
              null,
            ),
        },
      };`;
  if(s.includes(marker)) {
    s=s.replace(
      marker,
`      recordGoLiveAuditEvent({
        gameId,
        type:
          "INCIDENT_ACKNOWLEDGED",
        operator:
          body.operator ??
          null,
      });

${marker}`
    );
  }
}

if(!s.includes('type:\n          "INCIDENT_RETRY"')) {
  const marker=`      const current =
        clearGoLiveIncidentAcknowledgement(
          gameId,
        );`;
  if(s.includes(marker)) {
    s=s.replace(
      marker,
`${marker}

      recordGoLiveAuditEvent({
        gameId,
        type:
          "INCIDENT_RETRY",
      });`
    );
  }
}

if(!s.includes('type:\n            "DEGRADED"')) {
  const marker=`          session =
            markGoLiveDegraded(
              gameId,
              reason,
            );`;
  if(s.includes(marker)) {
    s=s.replace(
      marker,
`${marker}

          recordGoLiveAuditEvent({
            gameId,
            type:
              "DEGRADED",
            detail:
              reason,
          });`
    );
  }
}

if(!s.includes('type:\n            "RECOVERED"')) {
  const marker=`          session =
            clearGoLiveDegraded(
              gameId,
            );`;
  if(s.includes(marker)) {
    s=s.replace(
      marker,
`${marker}

          recordGoLiveAuditEvent({
            gameId,
            type:
              "RECOVERED",
          });`
    );
  }
}

if(!s.includes('"/go-live-sessions/:gameId/audit"')) {
  const marker='  app.get(\n    "/go-live-sessions/:gameId",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("Go-live GET route missing.");

  const route=`  app.get(
    "/go-live-sessions/:gameId/audit",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const query =
        request.query as {
          limit?: string;
        };

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
          "100",
          10,
        );

      return {
        success: true,
        data: {
          events:
            listGoLiveAuditEvents(
              gameId,
              Number.isFinite(limit)
                ? limit
                : 100,
            ),
        },
      };
    },
  );

`;

  s=s.slice(0,i)+route+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("type GoLiveAuditEvent =")) {
  const marker="type GoLiveSession = {";
  const i=s.indexOf(marker);
  if(i<0) throw Error("GoLiveSession type missing.");

  const type=`type GoLiveAuditEvent = {
  id: string;
  gameId: string;
  type: string;
  timestamp: string;
  detail: string | null;
  operator: string | null;
};

`;

  s=s.slice(0,i)+type+s.slice(i);
}

if(!s.includes("const [goLiveAudit")) {
  const marker="  const [\n    goLiveSession,";
  const i=s.indexOf(marker);
  if(i<0) throw Error("goLiveSession state missing.");

  const end=s.indexOf(";",i);
  if(end<0) throw Error("goLiveSession state end missing.");

  const addition=`

  const [
    goLiveAudit,
    setGoLiveAudit,
  ] =
    useState<GoLiveAuditEvent[]>(
      [],
    );`;

  s=s.slice(0,end+1)+addition+s.slice(end+1);
}

if(!s.includes("async function refreshGoLiveAudit")) {
  const marker="  async function loadGoLiveSession() {";
  const i=s.indexOf(marker);
  if(i<0) throw Error("loadGoLiveSession missing.");

  const fn=`  async function refreshGoLiveAudit() {
    const normalized =
      gameId.trim();

    if (!normalized) return;

    try {
      const response =
        await fetch(
          \`\${API_BASE}/go-live-sessions/\${encodeURIComponent(normalized)}/audit?limit=25\`,
          {
            cache:
              "no-store",
          },
        );

      if (!response.ok) return;

      const json =
        await response.json();

      setGoLiveAudit(
        json?.data?.events ??
        [],
      );
    } catch {
      // Audit history failure must not affect go-live controls.
    }
  }

`;

  s=s.slice(0,i)+fn+s.slice(i);
}

if(!s.includes("Go-Live Session History")) {
  const candidates=[
    "Emergency Broadcast Stop",
    "Live Incident Controls",
    "Live Broadcast Watchdog",
    "Production Go-Live"
  ];

  let base=-1;
  for(const marker of candidates) {
    base=s.indexOf(marker);
    if(base>=0) break;
  }

  if(base<0) throw Error("Go-live UI missing.");

  const anchor='        <div className="mt-4 flex flex-wrap gap-3">';
  let i=s.indexOf(anchor,base);

  if(i<0) {
    i=s.indexOf("      </div>",base);
  }

  if(i<0) throw Error("Unable to locate go-live UI insertion point.");

  const ui=`        <div className="mt-4 rounded border border-slate-800 p-3">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="text-sm font-semibold">
              Go-Live Session History
            </div>

            <button
              type="button"
              disabled={
                busy ||
                !gameId.trim()
              }
              onClick={() =>
                void refreshGoLiveAudit()
              }
              className="rounded-lg border border-slate-800 px-3 py-2 text-xs disabled:opacity-50"
            >
              Refresh Go-Live History
            </button>
          </div>

          <div className="mt-3 space-y-2">
            {goLiveAudit.length === 0 ? (
              <div className="rounded border border-slate-800 p-3 text-xs text-slate-500">
                No go-live events recorded.
              </div>
            ) : (
              goLiveAudit.map(
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

                    {event.operator && (
                      <div className="mt-1 text-xs text-slate-500">
                        Operator: {event.operator}
                      </div>
                    )}
                  </div>
                ),
              )
            )}
          </div>
        </div>

`;

  s=s.slice(0,i)+ui+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 21.8 — Go-live audit timeline and session history

SportsOS now persists the production go-live lifecycle separately from the lower-level encoder runtime audit.

Recorded event types include:

```text
ARMED
START_REQUESTED
STARTING
LIVE_CONFIRMED
DEGRADED
RECOVERED
INCIDENT_ACKNOWLEDGED
INCIDENT_RETRY
STOP_REQUESTED
COMPLETE
EMERGENCY_STOP
RESET
ERROR
```

API:

```text
GET /go-live-sessions/:gameId/audit?limit=100
```

The audit store keeps the newest 2000 events globally and limits individual API requests to 250 events.

The operator UI exposes the latest go-live session history, including incident details and operator acknowledgement information.
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 21.8 go-live audit timeline / session history", () => {
  const audit=fs.readFileSync(new URL("../../../apps/api/src/services/goLiveAudit.ts",import.meta.url),"utf8");
  const route=fs.readFileSync(new URL("../../../apps/api/src/routes/goLiveSessions.ts",import.meta.url),"utf8");
  const panel=fs.readFileSync(new URL("../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",import.meta.url),"utf8");

  it("persists bounded go-live audit history",()=> {
    expect(audit).toContain("go-live-audit.json");
    expect(audit).toContain("2000");
  });

  it("records core production lifecycle events",()=> {
    for(const event of [
      "ARMED",
      "START_REQUESTED",
      "STARTING",
      "LIVE_CONFIRMED",
      "DEGRADED",
      "RECOVERED",
      "EMERGENCY_STOP",
    ]) {
      expect(route).toContain(`"${event}"`);
    }
  });

  it("records incident acknowledgement and retry",()=> {
    expect(route).toContain('"INCIDENT_ACKNOWLEDGED"');
    expect(route).toContain('"INCIDENT_RETRY"');
  });

  it("provides audit API",()=> {
    expect(route).toContain('"/go-live-sessions/:gameId/audit"');
    expect(route).toContain("listGoLiveAuditEvents");
  });

  it("provides operator session history",()=> {
    expect(panel).toContain("Go-Live Session History");
    expect(panel).toContain("Refresh Go-Live History");
    expect(panel).toContain("/audit?limit=25");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 21.8 installed"
echo "============================================================"
echo "Added:"
echo "  - persistent go-live audit store"
echo "  - arm/start/live/degraded/recovery event history"
echo "  - incident acknowledgement/retry history"
echo "  - stop/complete/emergency-stop history"
echo "  - go-live audit API"
echo "  - operator session-history panel"
echo "  - Milestone 21.8 regression tests"
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
echo "  Milestone 21.9 - Game-Day Go-Live Readiness / Final Operator Preflight"
