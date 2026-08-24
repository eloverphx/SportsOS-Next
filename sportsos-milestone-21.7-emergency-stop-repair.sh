#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-21.7-emergency-stop-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/goLiveSession.ts"
RUNTIME="apps/api/src/services/encoderRuntime.ts"
ROUTE="apps/api/src/routes/goLiveSessions.ts"
PANEL="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
TEST="packages/core/test/emergency-broadcast-stop-21.7.test.ts"
DOC="docs/GO-LIVE-OPERATIONS.md"

for required in ".git" "$SERVICE" "$RUNTIME" "$ROUTE" "$PANEL" "$DOC"; do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$RUNTIME" "$ROUTE" "$PANEL" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/services/goLiveSession.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes('"EMERGENCY_STOPPED"')) {
  s=s.replace(
    '  | "ERROR";',
    '  | "ERROR"\n  | "EMERGENCY_STOPPED";'
  );
}

if(!s.includes("emergencyStoppedAt:")) {
  const typeStart=s.indexOf("export type GoLiveSession = {");
  const typeEnd=s.indexOf("\n};",typeStart);
  if(typeStart<0||typeEnd<0) throw Error("GoLiveSession service type missing.");

  let block=s.slice(typeStart,typeEnd+3);
  block=block.replace(
    "\n};",
    "\n  emergencyStoppedAt: string | null;\n  emergencyStopReason: string | null;\n};"
  );
  s=s.slice(0,typeStart)+block+s.slice(typeEnd+3);
}

s=s.replaceAll(
`    incidentAcknowledgedBy:
      null,
  };`,
`    incidentAcknowledgedBy:
      null,
    emergencyStoppedAt:
      null,
    emergencyStopReason:
      null,
  };`
);

s=s.replaceAll(
`    incidentAcknowledgedBy:
      null,
  });`,
`    incidentAcknowledgedBy:
      null,
    emergencyStoppedAt:
      null,
    emergencyStopReason:
      null,
  });`
);

if(!s.includes("export function markGoLiveEmergencyStopped")) {
  const marker="export function resetGoLiveSession(";
  const i=s.indexOf(marker);
  if(i<0) throw Error("resetGoLiveSession missing.");

  const x=`export function markGoLiveEmergencyStopped(
  gameId: string,
  reason: string | null,
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
      "EMERGENCY_STOPPED",
    stoppedAt:
      now,
    emergencyStoppedAt:
      now,
    emergencyStopReason:
      reason?.trim() ||
      "Emergency broadcast stop.",
    lastTransitionAt:
      now,
    lastError:
      reason?.trim() ||
      "Emergency broadcast stop.",
  });
}

`;

  s=s.slice(0,i)+x+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/services/encoderRuntime.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("export function suppressEncoderRecovery")) {
  const marker="export async function stopEncoderRuntime(";
  const i=s.indexOf(marker);
  if(i<0) throw Error("stopEncoderRuntime missing.");

  const x=`export function suppressEncoderRecovery(
  gameId: string,
): void {
  const snapshot =
    getEncoderRecoverySnapshot(
      gameId,
    );

  recovery.set(
    gameId,
    {
      ...snapshot,
      state:
        "EXHAUSTED",
      nextRetryAt:
        null,
    },
  );
}

`;

  s=s.slice(0,i)+x+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/goLiveSessions.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("markGoLiveEmergencyStopped,")) {
  s=s.replace(
    "  markGoLiveError,\n",
    "  markGoLiveEmergencyStopped,\n  markGoLiveError,\n"
  );
}

if(!s.includes("suppressEncoderRecovery")) {
  s=s.replace(
    "  stopEncoderRuntime,\n",
    "  stopEncoderRuntime,\n  suppressEncoderRecovery,\n"
  );
}

if(!s.includes('"/go-live-sessions/:gameId/emergency-stop"')) {
  const marker='  app.post(\n    "/go-live-sessions/:gameId/stop",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("Normal go-live stop route missing.");

  const x=`  app.post(
    "/go-live-sessions/:gameId/emergency-stop",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          reason?: string | null;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      suppressEncoderRecovery(
        gameId,
      );

      await stopEncoderRuntime(
        gameId,
      );

      const session =
        markGoLiveEmergencyStopped(
          gameId,
          body.reason ??
          null,
        );

      return {
        success: true,
        data: {
          session,
          runtime:
            encoderRuntimeSnapshot(
              gameId,
            ),
        },
      };
    },
  );

`;

  s=s.slice(0,i)+x+s.slice(i);
}

const startRoute=s.indexOf('"/go-live-sessions/:gameId/start"');
if(startRoute>=0 && !s.slice(startRoute,startRoute+4000).includes("Emergency-stopped go-live session must be reset before start.")) {
  const marker=`      if (
        current.status !==
        "ARMED"
      ) {`;
  const i=s.indexOf(marker,startRoute);
  if(i<0) throw Error("Start-state guard missing.");

  const guard=`      if (
        current.status ===
        "EMERGENCY_STOPPED"
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Emergency-stopped go-live session must be reset before start.",
        });
      }

`;

  s=s.slice(0,i)+guard+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx";
let s=fs.readFileSync(f,"utf8");

const start=s.indexOf("type GoLiveSession = {");
const end=s.indexOf("\n};",start);
if(start<0||end<0) throw Error("Dashboard GoLiveSession type missing.");

let block=s.slice(start,end+3);

if(!block.includes('"EMERGENCY_STOPPED"')) {
  if(block.includes('    | "ERROR"\n')) {
    block=block.replace(
      '    | "ERROR"\n',
      '    | "ERROR"\n    | "EMERGENCY_STOPPED"\n'
    );
  } else {
    block=block.replace(
      "\n};",
      '\n  status: GoLiveSession["status"] | "EMERGENCY_STOPPED";\n};'
    );
  }
}

if(!block.includes("emergencyStoppedAt:")) {
  block=block.replace(
    "\n};",
    "\n  emergencyStoppedAt: string | null;\n  emergencyStopReason: string | null;\n};"
  );
}

s=s.slice(0,start)+block+s.slice(end+3);

if(!s.includes("async function emergencyStopGoLive")) {
  const candidates=[
    "  async function acknowledgeIncident() {",
    "  async function runLiveWatchdog() {",
    "  async function saveHealthHold() {",
    "  async function goLiveAction("
  ];

  let i=-1;
  for(const marker of candidates){
    i=s.indexOf(marker);
    if(i>=0) break;
  }
  if(i<0) throw Error("Unable to locate dashboard function insertion point.");

  const x=`  const [
    emergencyStopReason,
    setEmergencyStopReason,
  ] =
    useState("");

  async function emergencyStopGoLive() {
    const normalized =
      gameId.trim();

    if (!normalized) return;

    setBusy(true);

    try {
      const response =
        await fetch(
          \`\${API_BASE}/go-live-sessions/\${encodeURIComponent(normalized)}/emergency-stop\`,
          {
            method:
              "POST",
            headers: {
              "Content-Type":
                "application/json",
            },
            body:
              JSON.stringify({
                reason:
                  emergencyStopReason.trim() ||
                  null,
              }),
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          "Emergency stop failed.",
        );
      }

      setGoLiveSession(
        json?.data?.session ??
        null,
      );

      setEncoderSession(
        json?.data?.runtime?.session ??
        null,
      );

      setEncoderTelemetry(
        json?.data?.runtime?.telemetry ??
        null,
      );

      setError(null);
    } catch (stopError) {
      setError(
        stopError instanceof Error
          ? stopError.message
          : "Emergency stop failed.",
      );
    } finally {
      setBusy(false);
    }
  }

`;

  s=s.slice(0,i)+x+s.slice(i);
}

if(!s.includes("Emergency Broadcast Stop")) {
  const candidates=[
    "Live Incident Controls",
    "Live Broadcast Watchdog",
    "Go-Live Health Hold",
    "Production Go-Live"
  ];

  let base=-1;
  for(const marker of candidates){
    base=s.indexOf(marker);
    if(base>=0) break;
  }
  if(base<0) throw Error("Unable to locate go-live UI.");

  const anchor='        <div className="mt-4 flex flex-wrap gap-3">';
  let i=s.indexOf(anchor,base);

  if(i<0){
    i=s.indexOf("      </div>",base);
  }

  if(i<0) throw Error("Unable to locate go-live UI insertion point.");

  const x=`        <div className="mt-4 rounded border border-red-900/50 bg-red-950/10 p-3">
          <div className="text-sm font-semibold text-red-300">
            Emergency Broadcast Stop
          </div>
          <p className="mt-1 text-xs text-slate-500">
            Immediately stops the encoder runtime and suppresses automatic recovery. Reset is required before another start.
          </p>

          <div className="mt-3 grid gap-3 md:grid-cols-2">
            <label className="text-sm">
              <span className="text-xs text-slate-500">
                Emergency Stop Reason
              </span>
              <input
                value={emergencyStopReason}
                onChange={(event) =>
                  setEmergencyStopReason(
                    event.target.value,
                  )
                }
                placeholder="Reason for emergency stop"
                className="mt-1 w-full rounded-lg border border-red-900/50 bg-slate-950 px-3 py-2"
              />
            </label>

            <div className="flex items-end">
              <button
                type="button"
                disabled={
                  busy ||
                  !gameId.trim() ||
                  goLiveSession?.status ===
                    "IDLE" ||
                  goLiveSession?.status ===
                    "COMPLETE" ||
                  goLiveSession?.status ===
                    "EMERGENCY_STOPPED"
                }
                onClick={() =>
                  void emergencyStopGoLive()
                }
                className="rounded-lg border border-red-800 px-4 py-2 text-sm font-semibold text-red-300 disabled:opacity-50"
              >
                Emergency Stop Broadcast
              </button>
            </div>
          </div>

          {goLiveSession?.status === "EMERGENCY_STOPPED" && (
            <div className="mt-3 rounded border border-red-900/50 p-3 text-xs text-red-300">
              Emergency stopped
              {goLiveSession.emergencyStopReason
                ? \`: \${goLiveSession.emergencyStopReason}\`
                : ""}
            </div>
          )}
        </div>

`;

  s=s.slice(0,i)+x+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 21.7 — Emergency stop / broadcast kill switch

Production go-live sessions now support an `EMERGENCY_STOPPED` state with timestamp and reason.

Emergency stop suppresses automatic encoder recovery, stops the encoder through the existing runtime stop path, and requires an explicit go-live reset before another start.

Endpoint:

```text
POST /go-live-sessions/:gameId/emergency-stop
```
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 21.7 emergency stop / broadcast kill switch", () => {
  const service=fs.readFileSync(new URL("../../../apps/api/src/services/goLiveSession.ts",import.meta.url),"utf8");
  const runtime=fs.readFileSync(new URL("../../../apps/api/src/services/encoderRuntime.ts",import.meta.url),"utf8");
  const route=fs.readFileSync(new URL("../../../apps/api/src/routes/goLiveSessions.ts",import.meta.url),"utf8");
  const panel=fs.readFileSync(new URL("../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",import.meta.url),"utf8");

  it("adds emergency-stopped state",()=> {
    expect(service).toContain('"EMERGENCY_STOPPED"');
    expect(service).toContain("emergencyStoppedAt");
    expect(service).toContain("emergencyStopReason");
  });

  it("suppresses encoder recovery",()=> {
    expect(runtime).toContain("suppressEncoderRecovery");
    expect(runtime).toContain('"EXHAUSTED"');
  });

  it("provides emergency-stop API",()=> {
    expect(route).toContain('"/go-live-sessions/:gameId/emergency-stop"');
    expect(route).toContain("stopEncoderRuntime");
  });

  it("requires reset before another start",()=> {
    expect(route).toContain("Emergency-stopped go-live session must be reset before start.");
  });

  it("provides operator kill switch",()=> {
    expect(panel).toContain("Emergency Broadcast Stop");
    expect(panel).toContain("Emergency Stop Broadcast");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 21.7 repair installed"
echo "============================================================"
echo "Fixed:"
echo "  - removes fragile dependency on 21.6 dashboard marker"
echo "  - structurally patches GoLiveSession"
echo "  - installs emergency-stop service/runtime/API/UI"
echo "  - preserves existing 21.6 logic if present"
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
