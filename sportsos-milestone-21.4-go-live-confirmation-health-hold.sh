#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-21.4-go-live-health-hold-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/goLiveSession.ts"
ROUTE="apps/api/src/routes/goLiveSessions.ts"
PANEL="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
TEST="packages/core/test/go-live-health-hold-21.4.test.ts"
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

if(!s.includes("healthHoldSeconds: number;")) {
  s=s.replace(
    "  autoArmLeadMinutes: number;\n};",
    "  autoArmLeadMinutes: number;\n  healthHoldSeconds: number;\n  healthySinceAt: string | null;\n};"
  );
}

s=s.replaceAll(
`    autoArmLeadMinutes:
      30,
  };`,
`    autoArmLeadMinutes:
      30,
    healthHoldSeconds:
      10,
    healthySinceAt:
      null,
  };`
);

s=s.replaceAll(
`    autoArmLeadMinutes:
      30,
  });`,
`    autoArmLeadMinutes:
      30,
    healthHoldSeconds:
      10,
    healthySinceAt:
      null,
  });`
);

if(!s.includes("export function configureGoLiveHealthHold")) {
  const marker="export function configureGoLiveAutoArm";
  const i=s.indexOf(marker);
  if(i<0) throw Error("21.3 auto-arm service prerequisite missing.");

  const x=`export function configureGoLiveHealthHold(
  gameId: string,
  healthHoldSeconds: number,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  const normalized =
    Math.max(
      0,
      Math.min(
        120,
        Math.floor(
          Number.isFinite(
            healthHoldSeconds,
          )
            ? healthHoldSeconds
            : current.healthHoldSeconds,
        ),
      ),
    );

  return replaceSession({
    ...current,
    healthHoldSeconds:
      normalized,
    healthySinceAt:
      null,
    lastTransitionAt:
      new Date().toISOString(),
  });
}

export function evaluateGoLiveHealthHold(input: {
  gameId: string;
  encoderLive: boolean;
  publishHealthy: boolean;
  now?: Date;
}): {
  readyToConfirm: boolean;
  healthySinceAt: string | null;
  holdSeconds: number;
  healthyForSeconds: number;
  remainingSeconds: number;
} {
  const current =
    getGoLiveSession(
      input.gameId,
    );

  const now =
    input.now ??
    new Date();

  if (
    !input.encoderLive ||
    !input.publishHealthy
  ) {
    if (
      current.healthySinceAt !==
      null
    ) {
      replaceSession({
        ...current,
        healthySinceAt:
          null,
      });
    }

    return {
      readyToConfirm:
        false,
      healthySinceAt:
        null,
      holdSeconds:
        current.healthHoldSeconds,
      healthyForSeconds:
        0,
      remainingSeconds:
        current.healthHoldSeconds,
    };
  }

  const healthySinceAt =
    current.healthySinceAt ??
    now.toISOString();

  if (
    current.healthySinceAt ===
    null
  ) {
    replaceSession({
      ...current,
      healthySinceAt,
    });
  }

  const elapsedMs =
    Math.max(
      0,
      now.getTime() -
        Date.parse(
          healthySinceAt,
        ),
    );

  const healthyForSeconds =
    Math.floor(
      elapsedMs /
        1000,
    );

  const remainingSeconds =
    Math.max(
      0,
      current.healthHoldSeconds -
        healthyForSeconds,
    );

  return {
    readyToConfirm:
      elapsedMs >=
      current.healthHoldSeconds *
        1000,
    healthySinceAt,
    holdSeconds:
      current.healthHoldSeconds,
    healthyForSeconds,
    remainingSeconds,
  };
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

if(!s.includes("configureGoLiveHealthHold,")) {
  s=s.replace(
    "  configureGoLiveAutoArm,\n",
    "  configureGoLiveAutoArm,\n  configureGoLiveHealthHold,\n  evaluateGoLiveHealthHold,\n"
  );
}

if(!s.includes('"/go-live-sessions/:gameId/health-hold"')) {
  const marker=`  app.put(
    "/go-live-sessions/:gameId/auto-arm",`;
  const i=s.indexOf(marker);
  if(i<0) throw Error("21.3 auto-arm route prerequisite missing.");

  const x=`  app.put(
    "/go-live-sessions/:gameId/health-hold",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          seconds?: number;
        };

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
            configureGoLiveHealthHold(
              gameId,
              Number(
                body.seconds ??
                10,
              ),
            ),
        },
      };
    },
  );

  app.get(
    "/go-live-sessions/:gameId/health-hold",
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

      const runtime =
        encoderRuntimeSnapshot(
          gameId,
        );

      const hold =
        evaluateGoLiveHealthHold({
          gameId,
          encoderLive:
            runtime.session.status ===
            "LIVE",
          publishHealthy:
            runtime.telemetry.health ===
            "HEALTHY",
        });

      return {
        success: true,
        data: {
          session:
            getGoLiveSession(
              gameId,
            ),
          runtime,
          healthHold:
            hold,
        },
      };
    },
  );

`;

  s=s.slice(0,i)+x+s.slice(i);
}

const confirmMarker='"/go-live-sessions/:gameId/confirm-live"';
const confirmStart=s.indexOf(confirmMarker);
if(confirmStart<0) throw Error("confirm-live route missing.");

if(!s.slice(confirmStart).includes("GO_LIVE_HEALTH_HOLD_21_4")) {
  const runtimeMarker=`      const runtime =
        encoderRuntimeSnapshot(
          gameId,
        );`;
  const runtimeIdx=s.indexOf(runtimeMarker,confirmStart);
  if(runtimeIdx<0) throw Error("confirm-live runtime block missing.");

  const after=runtimeIdx+runtimeMarker.length;
  const guard=`

      // GO_LIVE_HEALTH_HOLD_21_4
      const healthHold =
        evaluateGoLiveHealthHold({
          gameId,
          encoderLive:
            runtime.session.status ===
            "LIVE",
          publishHealthy:
            runtime.telemetry.health ===
            "HEALTHY",
        });

      if (
        !healthHold.readyToConfirm
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Publish health has not remained healthy for the required confirmation hold.",
          data: {
            runtime,
            healthHold,
          },
        });
      }
`;

  s=s.slice(0,after)+guard+s.slice(after);
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("healthHoldSeconds: number;")) {
  s=s.replace(
    "  autoArmLeadMinutes: number;\n};",
    "  autoArmLeadMinutes: number;\n  healthHoldSeconds: number;\n  healthySinceAt: string | null;\n};"
  );
}

if(!s.includes("const [healthHoldSeconds")) {
  const marker="  async function saveAutoArmSettings() {";
  const i=s.indexOf(marker);
  if(i<0) throw Error("21.3 auto-arm dashboard prerequisite missing.");

  const x=`  const [
    healthHoldSeconds,
    setHealthHoldSeconds,
  ] =
    useState(10);

  const [
    goLiveHealthHold,
    setGoLiveHealthHold,
  ] =
    useState<{
      readyToConfirm: boolean;
      healthySinceAt: string | null;
      holdSeconds: number;
      healthyForSeconds: number;
      remainingSeconds: number;
    } | null>(
      null,
    );

  async function saveHealthHold() {
    const normalized =
      gameId.trim();

    if (!normalized) return;

    setBusy(true);

    try {
      const response =
        await fetch(
          \`\${API_BASE}/go-live-sessions/\${encodeURIComponent(normalized)}/health-hold\`,
          {
            method:
              "PUT",
            headers: {
              "Content-Type":
                "application/json",
            },
            body:
              JSON.stringify({
                seconds:
                  healthHoldSeconds,
              }),
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          "Unable to save health hold.",
        );
      }

      setGoLiveSession(
        json?.data?.session ??
        null,
      );

      setError(null);
    } catch (holdError) {
      setError(
        holdError instanceof Error
          ? holdError.message
          : "Unable to save health hold.",
      );
    } finally {
      setBusy(false);
    }
  }

  async function refreshHealthHold() {
    const normalized =
      gameId.trim();

    if (!normalized) return;

    const response =
      await fetch(
        \`\${API_BASE}/go-live-sessions/\${encodeURIComponent(normalized)}/health-hold\`,
        {
          cache:
            "no-store",
        },
      );

    if (!response.ok) return;

    const json =
      await response.json();

    setGoLiveSession(
      json?.data?.session ??
      null,
    );

    setGoLiveHealthHold(
      json?.data?.healthHold ??
      null,
    );
  }

`;

  s=s.slice(0,i)+x+s.slice(i);
}

if(!s.includes("Go-Live Health Hold")) {
  const base=s.indexOf("Auto-Arm Countdown");
  if(base<0) throw Error("Auto-Arm Countdown UI missing.");

  const anchor='        <div className="mt-4 flex flex-wrap gap-3">';
  const i=s.indexOf(anchor,base);
  if(i<0) throw Error("go-live action controls missing.");

  const x=`        <div className="mt-4 rounded border border-slate-800 p-3">
          <div className="text-sm font-semibold">
            Go-Live Health Hold
          </div>
          <p className="mt-1 text-xs text-slate-500">
            Requires continuous healthy publish telemetry before the broadcast can be confirmed live.
          </p>

          <div className="mt-3 flex flex-wrap items-end gap-3">
            <label className="text-sm">
              <span className="text-xs text-slate-500">
                Confirmation Hold (seconds)
              </span>
              <input
                type="number"
                min={0}
                max={120}
                value={healthHoldSeconds}
                onChange={(event) =>
                  setHealthHoldSeconds(
                    Number(event.target.value) || 0,
                  )
                }
                className="mt-1 block rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
              />
            </label>

            <button
              type="button"
              disabled={
                busy ||
                !gameId.trim()
              }
              onClick={() =>
                void saveHealthHold()
              }
              className="rounded-lg border border-slate-700 px-4 py-2 text-sm disabled:opacity-50"
            >
              Save Health Hold
            </button>

            <button
              type="button"
              disabled={
                busy ||
                !gameId.trim()
              }
              onClick={() =>
                void refreshHealthHold()
              }
              className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
            >
              Refresh Health Hold
            </button>
          </div>

          {goLiveHealthHold && (
            <div className="mt-3 text-xs text-slate-400">
              <div>
                Confirmation: {goLiveHealthHold.readyToConfirm ? "READY" : "HOLDING"}
              </div>
              <div className="mt-1">
                Healthy for: {goLiveHealthHold.healthyForSeconds}s / {goLiveHealthHold.holdSeconds}s
              </div>
              <div className="mt-1">
                Remaining: {goLiveHealthHold.remainingSeconds}s
              </div>
            </div>
          )}
        </div>

`;

  s=s.slice(0,i)+x+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 21.4 — Go-live confirmation health hold

A momentary encoder `LIVE` state is no longer enough to confirm a production broadcast.

The go-live session now tracks:

```text
healthHoldSeconds
healthySinceAt
```

Default confirmation hold:

```text
10 seconds
```

Allowed range:

```text
0–120 seconds
```

The health timer only advances while both conditions remain true:

```text
encoder session = LIVE
publish telemetry = HEALTHY
```

If either condition fails, the continuous-health timer resets.

Endpoints:

```text
PUT /go-live-sessions/:gameId/health-hold
GET /go-live-sessions/:gameId/health-hold
```

`POST /go-live-sessions/:gameId/confirm-live` now requires the configured continuous health hold to complete before the go-live session may transition to `LIVE`.
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 21.4 go-live confirmation health hold", () => {
  const service=fs.readFileSync(new URL("../../../apps/api/src/services/goLiveSession.ts",import.meta.url),"utf8");
  const route=fs.readFileSync(new URL("../../../apps/api/src/routes/goLiveSessions.ts",import.meta.url),"utf8");
  const panel=fs.readFileSync(new URL("../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",import.meta.url),"utf8");

  it("persists health hold state",()=> {
    expect(service).toContain("healthHoldSeconds");
    expect(service).toContain("healthySinceAt");
  });

  it("evaluates continuous publish health",()=> {
    expect(service).toContain("evaluateGoLiveHealthHold");
    expect(service).toContain("readyToConfirm");
    expect(service).toContain("remainingSeconds");
  });

  it("resets hold when runtime is unhealthy",()=> {
    expect(service).toContain("!input.encoderLive");
    expect(service).toContain("!input.publishHealthy");
    expect(service).toContain("healthySinceAt:");
  });

  it("guards live confirmation",()=> {
    expect(route).toContain("GO_LIVE_HEALTH_HOLD_21_4");
    expect(route).toContain("Publish health has not remained healthy for the required confirmation hold.");
  });

  it("provides health hold API and operator UI",()=> {
    expect(route).toContain('"/go-live-sessions/:gameId/health-hold"');
    expect(panel).toContain("Go-Live Health Hold");
    expect(panel).toContain("Confirmation Hold (seconds)");
    expect(panel).toContain("Refresh Health Hold");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 21.4 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - configurable 0-120 second health hold"
echo "  - continuous HEALTHY publish timer"
echo "  - automatic hold reset on unhealthy runtime"
echo "  - health-hold status API"
echo "  - confirm-live health-hold enforcement"
echo "  - operator confirmation countdown"
echo "  - Milestone 21.4 regression tests"
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
echo "  Milestone 21.5 - Live Broadcast Watchdog / Degraded-State Detection"
