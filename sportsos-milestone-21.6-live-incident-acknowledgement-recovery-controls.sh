#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-21.6-live-incident-controls-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/goLiveSession.ts"
ROUTE="apps/api/src/routes/goLiveSessions.ts"
PANEL="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
TEST="packages/core/test/live-incident-controls-21.6.test.ts"
DOC="docs/GO-LIVE-OPERATIONS.md"

for required in ".git" "$SERVICE" "$ROUTE" "$PANEL" "$DOC"; do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$ROUTE" "$PANEL" "$TEST" "$DOC"; do
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

if(!s.includes("incidentAcknowledgedAt:")) {
  s=s.replace(
`  degradationReason: string | null;
};`,
`  degradationReason: string | null;
  incidentAcknowledgedAt: string | null;
  incidentAcknowledgedBy: string | null;
};`
  );
}

s=s.replaceAll(
`    degradationReason:
      null,
  };`,
`    degradationReason:
      null,
    incidentAcknowledgedAt:
      null,
    incidentAcknowledgedBy:
      null,
  };`
);

s=s.replaceAll(
`    degradationReason:
      null,
  });`,
`    degradationReason:
      null,
    incidentAcknowledgedAt:
      null,
    incidentAcknowledgedBy:
      null,
  });`
);

if(!s.includes("export function acknowledgeGoLiveIncident")) {
  const marker="export function clearGoLiveDegraded(";
  const i=s.indexOf(marker);
  if(i<0) throw Error("Unable to locate degraded recovery function.");

  const x=`export function acknowledgeGoLiveIncident(
  gameId: string,
  operator: string | null,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  if (
    current.status !==
    "DEGRADED"
  ) {
    return current;
  }

  return replaceSession({
    ...current,
    incidentAcknowledgedAt:
      new Date().toISOString(),
    incidentAcknowledgedBy:
      operator?.trim() ||
      null,
  });
}

export function clearGoLiveIncidentAcknowledgement(
  gameId: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  return replaceSession({
    ...current,
    incidentAcknowledgedAt:
      null,
    incidentAcknowledgedBy:
      null,
  });
}

`;

  s=s.slice(0,i)+x+s.slice(i);
}

const degradedFn=s.indexOf("export function markGoLiveDegraded");
if(degradedFn>=0) {
  const segmentEnd=s.indexOf("\n}\n", degradedFn);
  if(segmentEnd>degradedFn) {
    let block=s.slice(degradedFn,segmentEnd+3);
    if(!block.includes("incidentAcknowledgedAt:")) {
      block=block.replace(
`    degradationReason:
      reason.trim() ||
      "Live broadcast degraded.",`,
`    degradationReason:
      reason.trim() ||
      "Live broadcast degraded.",
    incidentAcknowledgedAt:
      null,
    incidentAcknowledgedBy:
      null,`
      );
      s=s.slice(0,degradedFn)+block+s.slice(segmentEnd+3);
    }
  }
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/goLiveSessions.ts";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("acknowledgeGoLiveIncident,")) {
  s=s.replace(
`  armGoLiveSession,
  completeGoLiveSession,`,
`  acknowledgeGoLiveIncident,
  armGoLiveSession,
  clearGoLiveIncidentAcknowledgement,
  completeGoLiveSession,`
  );
}

if(!s.includes('"/go-live-sessions/:gameId/incident/acknowledge"')) {
  const marker=`  app.post(
    "/go-live-sessions/:gameId/watchdog",`;
  const i=s.indexOf(marker);
  if(i<0) throw Error("21.5 watchdog route prerequisite missing.");

  const x=`  app.post(
    "/go-live-sessions/:gameId/incident/acknowledge",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          operator?: string | null;
        };

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
        "DEGRADED"
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Only a DEGRADED go-live session can be acknowledged.",
        });
      }

      return {
        success: true,
        data: {
          session:
            acknowledgeGoLiveIncident(
              gameId,
              body.operator ??
              null,
            ),
        },
      };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/incident/retry-watchdog",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const current =
        clearGoLiveIncidentAcknowledgement(
          gameId,
        );

      return {
        success: true,
        data: {
          session:
            current,
          retryRequired:
            true,
        },
      };
    },
  );

`;

  s=s.slice(0,i)+x+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx";
let s=fs.readFileSync(f,"utf8");

const start=s.indexOf("type GoLiveSession = {");
const end=s.indexOf("\n};",start);
if(start<0||end<0) throw Error("GoLiveSession type missing.");
let block=s.slice(start,end+3);

if(!block.includes("incidentAcknowledgedAt:")) {
  block=block.replace(
    "\n};",
    "\n  incidentAcknowledgedAt: string | null;\n  incidentAcknowledgedBy: string | null;\n};"
  );
  s=s.slice(0,start)+block+s.slice(end+3);
}

if(!s.includes("const [incidentOperator")) {
  const marker="  async function runLiveWatchdog() {";
  const i=s.indexOf(marker);
  if(i<0) throw Error("21.5 watchdog dashboard prerequisite missing.");

  const x=`  const [
    incidentOperator,
    setIncidentOperator,
  ] =
    useState("");

  async function acknowledgeIncident() {
    const normalized =
      gameId.trim();

    if (!normalized) return;

    setBusy(true);

    try {
      const response =
        await fetch(
          \`\${API_BASE}/go-live-sessions/\${encodeURIComponent(normalized)}/incident/acknowledge\`,
          {
            method:
              "POST",
            headers: {
              "Content-Type":
                "application/json",
            },
            body:
              JSON.stringify({
                operator:
                  incidentOperator.trim() ||
                  null,
              }),
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          "Unable to acknowledge incident.",
        );
      }

      setGoLiveSession(
        json?.data?.session ??
        null,
      );

      setError(null);
    } catch (ackError) {
      setError(
        ackError instanceof Error
          ? ackError.message
          : "Unable to acknowledge incident.",
      );
    } finally {
      setBusy(false);
    }
  }

  async function retryIncidentWatchdog() {
    const normalized =
      gameId.trim();

    if (!normalized) return;

    setBusy(true);

    try {
      const response =
        await fetch(
          \`\${API_BASE}/go-live-sessions/\${encodeURIComponent(normalized)}/incident/retry-watchdog\`,
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
          "Unable to retry watchdog.",
        );
      }

      setGoLiveSession(
        json?.data?.session ??
        null,
      );

      await runLiveWatchdog();

      setError(null);
    } catch (retryError) {
      setError(
        retryError instanceof Error
          ? retryError.message
          : "Unable to retry incident watchdog.",
      );
    } finally {
      setBusy(false);
    }
  }

`;

  s=s.slice(0,i)+x+s.slice(i);
}

if(!s.includes("Live Incident Controls")) {
  const base=s.indexOf("Live Broadcast Watchdog");
  if(base<0) throw Error("Watchdog UI missing.");

  const anchor='        <div className="mt-4 flex flex-wrap gap-3">';
  const i=s.indexOf(anchor,base);
  if(i<0) throw Error("go-live action controls missing.");

  const x=`        <div className="mt-4 rounded border border-slate-800 p-3">
          <div className="text-sm font-semibold">
            Live Incident Controls
          </div>
          <p className="mt-1 text-xs text-slate-500">
            Acknowledge a degraded broadcast and explicitly retry health evaluation after operator action.
          </p>

          <div className="mt-3 grid gap-3 md:grid-cols-2">
            <label className="text-sm">
              <span className="text-xs text-slate-500">
                Operator / Note
              </span>
              <input
                value={incidentOperator}
                onChange={(event) =>
                  setIncidentOperator(
                    event.target.value,
                  )
                }
                placeholder="Operator name or console"
                className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
              />
            </label>

            <div className="flex flex-wrap items-end gap-3">
              <button
                type="button"
                disabled={
                  busy ||
                  goLiveSession?.status !==
                    "DEGRADED"
                }
                onClick={() =>
                  void acknowledgeIncident()
                }
                className="rounded-lg border border-slate-700 px-4 py-2 text-sm disabled:opacity-50"
              >
                Acknowledge Incident
              </button>

              <button
                type="button"
                disabled={
                  busy ||
                  goLiveSession?.status !==
                    "DEGRADED"
                }
                onClick={() =>
                  void retryIncidentWatchdog()
                }
                className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
              >
                Retry Health Check
              </button>
            </div>
          </div>

          {goLiveSession?.incidentAcknowledgedAt && (
            <div className="mt-3 text-xs text-slate-400">
              Acknowledged: {goLiveSession.incidentAcknowledgedAt}
              {goLiveSession.incidentAcknowledgedBy
                ? \` · \${goLiveSession.incidentAcknowledgedBy}\`
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

## Milestone 21.6 — Live incident acknowledgement and operator recovery controls

A degraded production broadcast now supports explicit operator incident acknowledgement.

Go-live sessions track:

```text
incidentAcknowledgedAt
incidentAcknowledgedBy
```

Endpoints:

```text
POST /go-live-sessions/:gameId/incident/acknowledge
POST /go-live-sessions/:gameId/incident/retry-watchdog
```

Only `DEGRADED` sessions may be acknowledged.

Acknowledgement does not hide or resolve the degradation. It records operator awareness.

Retrying the watchdog clears the acknowledgement and explicitly re-runs runtime/publish health evaluation.

If health is restored, the existing watchdog recovery path returns the go-live session to `LIVE`. If health is still degraded, the session remains `DEGRADED`.
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 21.6 live incident acknowledgement / operator recovery controls", () => {
  const service=fs.readFileSync(new URL("../../../apps/api/src/services/goLiveSession.ts",import.meta.url),"utf8");
  const route=fs.readFileSync(new URL("../../../apps/api/src/routes/goLiveSessions.ts",import.meta.url),"utf8");
  const panel=fs.readFileSync(new URL("../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",import.meta.url),"utf8");

  it("persists incident acknowledgement",()=> {
    expect(service).toContain("incidentAcknowledgedAt");
    expect(service).toContain("incidentAcknowledgedBy");
    expect(service).toContain("acknowledgeGoLiveIncident");
  });

  it("allows acknowledgement only for degraded sessions",()=> {
    expect(route).toContain("Only a DEGRADED go-live session can be acknowledged.");
  });

  it("provides acknowledgement and retry endpoints",()=> {
    expect(route).toContain('"/go-live-sessions/:gameId/incident/acknowledge"');
    expect(route).toContain('"/go-live-sessions/:gameId/incident/retry-watchdog"');
  });

  it("does not treat acknowledgement as recovery",()=> {
    const start=route.indexOf('"/go-live-sessions/:gameId/incident/acknowledge"');
    const end=route.indexOf('"/go-live-sessions/:gameId/incident/retry-watchdog"',start);
    const block=route.slice(start,end);
    expect(block).not.toContain("clearGoLiveDegraded");
  });

  it("provides operator incident controls",()=> {
    expect(panel).toContain("Live Incident Controls");
    expect(panel).toContain("Acknowledge Incident");
    expect(panel).toContain("Retry Health Check");
    expect(panel).toContain("incidentAcknowledgedAt");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 21.6 installed"
echo "============================================================"
echo "Added:"
echo "  - incident acknowledgement timestamp/operator"
echo "  - degraded-only acknowledgement guard"
echo "  - explicit watchdog retry control"
echo "  - acknowledgement does not falsely resolve degradation"
echo "  - operator incident controls"
echo "  - Milestone 21.6 regression tests"
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
echo "  Milestone 21.7 - Emergency Stop / Broadcast Kill Switch"
