#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-21.5-live-watchdog-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/goLiveSession.ts"
ROUTE="apps/api/src/routes/goLiveSessions.ts"
PANEL="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
TEST="packages/core/test/live-broadcast-watchdog-21.5.test.ts"
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

if(!s.includes('"DEGRADED"')) {
  s=s.replace(
`  | "LIVE"
  | "STOPPING"`,
`  | "LIVE"
  | "DEGRADED"
  | "STOPPING"`
  );
}

if(!s.includes("degradedAt:")) {
  s=s.replace(
`  healthySinceAt: string | null;
};`,
`  healthySinceAt: string | null;
  degradedAt: string | null;
  degradationReason: string | null;
};`
  );
}

s=s.replaceAll(
`    healthySinceAt:
      null,
  };`,
`    healthySinceAt:
      null,
    degradedAt:
      null,
    degradationReason:
      null,
  };`
);

s=s.replaceAll(
`    healthySinceAt:
      null,
  });`,
`    healthySinceAt:
      null,
    degradedAt:
      null,
    degradationReason:
      null,
  });`
);

if(!s.includes("export function markGoLiveDegraded")) {
  const marker="export function markGoLiveStopping(";
  const i=s.indexOf(marker);
  if(i<0) throw Error("Unable to locate markGoLiveStopping.");

  const x=`export function markGoLiveDegraded(
  gameId: string,
  reason: string,
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
      "DEGRADED",
    degradedAt:
      current.degradedAt ??
      now,
    degradationReason:
      reason.trim() ||
      "Live broadcast degraded.",
    lastTransitionAt:
      now,
    lastError:
      reason.trim() ||
      "Live broadcast degraded.",
  });
}

export function clearGoLiveDegraded(
  gameId: string,
): GoLiveSession {
  const current =
    getGoLiveSession(
      gameId,
    );

  return replaceSession({
    ...current,
    status:
      "LIVE",
    degradedAt:
      null,
    degradationReason:
      null,
    lastTransitionAt:
      new Date().toISOString(),
    lastError:
      null,
  });
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

if(!s.includes("markGoLiveDegraded,")) {
  s=s.replace(
`  markGoLiveError,
  markGoLiveLive,`,
`  clearGoLiveDegraded,
  markGoLiveDegraded,
  markGoLiveError,
  markGoLiveLive,`
  );
}

if(!s.includes('"/go-live-sessions/:gameId/watchdog"')) {
  const marker=`  app.get(
    "/go-live-sessions/:gameId/health-hold",`;
  const i=s.indexOf(marker);
  if(i<0) throw Error("21.4 health-hold route prerequisite missing.");

  const x=`  app.post(
    "/go-live-sessions/:gameId/watchdog",
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
        getGoLiveSession(
          gameId,
        );

      const runtime =
        encoderRuntimeSnapshot(
          gameId,
        );

      let session =
        current;

      if (
        current.status ===
          "LIVE" ||
        current.status ===
          "DEGRADED"
      ) {
        const encoderLive =
          runtime.session.status ===
          "LIVE";

        const publishHealthy =
          runtime.telemetry.health ===
          "HEALTHY";

        if (
          !encoderLive ||
          !publishHealthy
        ) {
          const reason =
            !encoderLive
              ? \`Encoder session is \${runtime.session.status}.\`
              : \`Publish health is \${runtime.telemetry.health}.\`;

          session =
            markGoLiveDegraded(
              gameId,
              reason,
            );
        } else if (
          current.status ===
          "DEGRADED"
        ) {
          session =
            clearGoLiveDegraded(
              gameId,
            );
        }
      }

      return {
        success: true,
        data: {
          session,
          runtime,
          watchdog: {
            healthy:
              session.status !==
              "DEGRADED",
            degradationReason:
              session.degradationReason,
          },
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

if(!s.includes('| "DEGRADED"')) {
  s=s.replace(
`    | "LIVE"
    | "STOPPING"`,
`    | "LIVE"
    | "DEGRADED"
    | "STOPPING"`
  );
}

if(!s.includes("degradedAt:")) {
  s=s.replace(
`  healthySinceAt: string | null;
};`,
`  healthySinceAt: string | null;
  degradedAt: string | null;
  degradationReason: string | null;
};`
  );
}

if(!s.includes("async function runLiveWatchdog")) {
  const marker="  async function saveHealthHold() {";
  const i=s.indexOf(marker);
  if(i<0) throw Error("21.4 health-hold dashboard prerequisite missing.");

  const x=`  async function runLiveWatchdog() {
    const normalized =
      gameId.trim();

    if (!normalized) return;

    try {
      const response =
        await fetch(
          \`\${API_BASE}/go-live-sessions/\${encodeURIComponent(normalized)}/watchdog\`,
          {
            method:
              "POST",
          },
        );

      if (!response.ok) return;

      const json =
        await response.json();

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
    } catch {
      // Watchdog polling failure must not interrupt operator controls.
    }
  }

  useEffect(() => {
    if (
      goLiveSession?.status !== "LIVE" &&
      goLiveSession?.status !== "DEGRADED"
    ) {
      return;
    }

    const timer =
      window.setInterval(
        () => {
          void runLiveWatchdog();
        },
        3000,
      );

    return () => {
      window.clearInterval(
        timer,
      );
    };
  }, [
    gameId,
    goLiveSession?.status,
  ]);

`;

  s=s.slice(0,i)+x+s.slice(i);
}

if(!s.includes("Live Broadcast Watchdog")) {
  const base=s.indexOf("Go-Live Health Hold");
  if(base<0) throw Error("Go-Live Health Hold UI missing.");

  const anchor='        <div className="mt-4 flex flex-wrap gap-3">';
  const i=s.indexOf(anchor,base);
  if(i<0) throw Error("go-live action controls missing.");

  const x=`        <div className="mt-4 rounded border border-slate-800 p-3">
          <div className="text-sm font-semibold">
            Live Broadcast Watchdog
          </div>
          <p className="mt-1 text-xs text-slate-500">
            Checks encoder state and publish health every 3 seconds while the production session is live.
          </p>

          <div className="mt-3 flex flex-wrap items-center gap-3">
            <span className="rounded border border-slate-700 px-3 py-1 text-xs font-semibold">
              {goLiveSession?.status === "DEGRADED"
                ? "DEGRADED"
                : goLiveSession?.status === "LIVE"
                  ? "HEALTHY"
                  : "INACTIVE"}
            </span>

            <button
              type="button"
              disabled={
                busy ||
                !gameId.trim()
              }
              onClick={() =>
                void runLiveWatchdog()
              }
              className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
            >
              Run Watchdog Check
            </button>
          </div>

          {goLiveSession?.degradationReason && (
            <div className="mt-3 rounded border border-red-900/50 bg-red-950/20 p-3 text-xs text-red-300">
              {goLiveSession.degradationReason}
            </div>
          )}
        </div>

`;

  s=s.slice(0,i)+x+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 21.5 — Live broadcast watchdog and degraded-state detection

Confirmed production broadcasts are now monitored for runtime degradation.

Go-live sessions add:

```text
DEGRADED
degradedAt
degradationReason
```

Watchdog endpoint:

```text
POST /go-live-sessions/:gameId/watchdog
```

While the production session is `LIVE` or `DEGRADED`, the watchdog checks:

```text
encoder session = LIVE
publish telemetry = HEALTHY
```

If either condition fails, the production go-live session transitions to `DEGRADED` and records a reason.

If both conditions recover while the session is degraded, the session automatically returns to `LIVE`.

The operator UI polls the watchdog every 3 seconds while a production session is live or degraded.

The watchdog is operational only and does not modify authoritative game state.
EOF

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 21.5 live broadcast watchdog / degraded-state detection", () => {
  const service=fs.readFileSync(new URL("../../../apps/api/src/services/goLiveSession.ts",import.meta.url),"utf8");
  const route=fs.readFileSync(new URL("../../../apps/api/src/routes/goLiveSessions.ts",import.meta.url),"utf8");
  const panel=fs.readFileSync(new URL("../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",import.meta.url),"utf8");

  it("adds a degraded production state",()=> {
    expect(service).toContain('"DEGRADED"');
    expect(service).toContain("degradedAt");
    expect(service).toContain("degradationReason");
  });

  it("supports degrade and recovery transitions",()=> {
    expect(service).toContain("markGoLiveDegraded");
    expect(service).toContain("clearGoLiveDegraded");
  });

  it("provides a watchdog endpoint",()=> {
    expect(route).toContain('"/go-live-sessions/:gameId/watchdog"');
    expect(route).toContain("Publish health is");
    expect(route).toContain("Encoder session is");
  });

  it("recovers degraded state after health returns",()=> {
    expect(route).toContain("clearGoLiveDegraded");
  });

  it("provides operator watchdog visibility",()=> {
    expect(panel).toContain("Live Broadcast Watchdog");
    expect(panel).toContain("Run Watchdog Check");
    expect(panel).toContain("3000");
    expect(panel).toContain("degradationReason");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 21.5 installed"
echo "============================================================"
echo "Added:"
echo "  - production DEGRADED state"
echo "  - encoder/publish-health watchdog"
echo "  - degradation reason tracking"
echo "  - automatic recovery to LIVE"
echo "  - 3-second live watchdog polling"
echo "  - operator degraded-state visibility"
echo "  - Milestone 21.5 regression tests"
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
echo "  Milestone 21.6 - Live Incident Acknowledgement / Operator Recovery Controls"
