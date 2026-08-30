#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-23.4-operator-incident-emergency-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

PAGE="apps/dashboard/app/broadcast/operations/page.tsx"
TEST="packages/core/test/broadcast-operator-incident-emergency-23.4.test.ts"
DOC="docs/BROADCAST-OPERATIONS-CONSOLE.md"

for required in \
  ".git" \
  "$PAGE" \
  "apps/api/src/routes/goLiveSessions.ts" \
  "apps/api/src/routes/broadcastSessionCoordinator.ts" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$PAGE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs=require("fs");
const f="apps/dashboard/app/broadcast/operations/page.tsx";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("const [incidentOperator")) {
  const marker=`  const [
    pendingStartGameId,
    setPendingStartGameId,
  ] =
    useState<string | null>(
      null,
    );`;

  if(!s.includes(marker)) throw Error("23.3 pending-start state missing.");

  s=s.replace(
    marker,
`${marker}

  const [
    incidentOperator,
    setIncidentOperator,
  ] =
    useState("");

  const [
    emergencyReason,
    setEmergencyReason,
  ] =
    useState("");`
  );
}

if(!s.includes("const runGoLiveAction =")) {
  const marker="  const runAction =";
  const idx=s.indexOf(marker);
  if(idx<0) throw Error("23.2 runAction missing.");

  const fn=`  const runGoLiveAction =
    useCallback(
      async (
        gameId: string,
        action:
          | "acknowledge-incident"
          | "retry-health"
          | "emergency-stop",
        body?: Record<string, unknown>,
      ) => {
        setActionGameId(
          gameId,
        );

        setActionMessage(
          null,
        );

        try {
          const response =
            await fetch(
              \`\${API_BASE}/go-live-sessions/\${encodeURIComponent(gameId)}/\${action}\`,
              {
                method:
                  "POST",
                headers: {
                  "Content-Type":
                    "application/json",
                },
                body:
                  JSON.stringify(
                    body ??
                    {},
                  ),
              },
            );

          const json =
            await response.json();

          if (!response.ok) {
            throw new Error(
              json?.error ??
              \`Go-live operator action failed (\${response.status}).\`,
            );
          }

          setActionMessage(
            \`\${action} completed for game \${gameId}.\`,
          );

          await load();
        } catch (actionError) {
          setActionMessage(
            actionError instanceof Error
              ? actionError.message
              : "Go-live operator action failed.",
          );
        } finally {
          setActionGameId(
            null,
          );
        }
      },
      [],
    );

`;

  s=s.slice(0,idx)+fn+s.slice(idx);
}

if(!s.includes("Incident / Emergency Controls")) {
  const marker=`                {item.health.issues.length > 0 && (`;
  const idx=s.indexOf(marker);
  if(idx<0) throw Error("Unable to locate issue section.");

  const block=`                {(item.snapshot.goLive.status === "DEGRADED" ||
                  item.snapshot.goLive.status === "EMERGENCY_STOPPED" ||
                  item.snapshot.goLive.status === "LIVE") && (
                  <div className="mt-4 rounded border border-red-900/40 bg-red-950/10 p-3">
                    <div className="text-xs font-semibold text-red-300">
                      Incident / Emergency Controls
                    </div>

                    {item.snapshot.goLive.status === "DEGRADED" && (
                      <>
                        <p className="mt-1 text-xs text-slate-500">
                          Acknowledge awareness or retry the existing live-health evaluation.
                        </p>

                        <div className="mt-3 grid gap-3 md:grid-cols-2">
                          <input
                            value={incidentOperator}
                            onChange={(event) =>
                              setIncidentOperator(
                                event.target.value,
                              )
                            }
                            placeholder="Operator name"
                            className="rounded-lg border border-slate-800 bg-transparent px-3 py-2 text-xs"
                          />

                          <div className="flex flex-wrap gap-2">
                            <button
                              type="button"
                              disabled={
                                actionGameId === item.gameId ||
                                !incidentOperator.trim()
                              }
                              onClick={() =>
                                void runGoLiveAction(
                                  item.gameId,
                                  "acknowledge-incident",
                                  {
                                    operator:
                                      incidentOperator.trim(),
                                  },
                                )
                              }
                              className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
                            >
                              Acknowledge Incident
                            </button>

                            <button
                              type="button"
                              disabled={
                                actionGameId === item.gameId
                              }
                              onClick={() =>
                                void runGoLiveAction(
                                  item.gameId,
                                  "retry-health",
                                )
                              }
                              className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
                            >
                              Retry Health Check
                            </button>
                          </div>
                        </div>
                      </>
                    )}

                    {item.snapshot.goLive.status !== "EMERGENCY_STOPPED" && (
                      <div className="mt-4 grid gap-3 md:grid-cols-2">
                        <input
                          value={emergencyReason}
                          onChange={(event) =>
                            setEmergencyReason(
                              event.target.value,
                            )
                          }
                          placeholder="Emergency stop reason"
                          className="rounded-lg border border-red-900/50 bg-transparent px-3 py-2 text-xs"
                        />

                        <button
                          type="button"
                          disabled={
                            actionGameId === item.gameId
                          }
                          onClick={() =>
                            void runGoLiveAction(
                              item.gameId,
                              "emergency-stop",
                              {
                                reason:
                                  emergencyReason.trim() ||
                                  null,
                              },
                            )
                          }
                          className="rounded-lg border border-red-800 px-3 py-2 text-xs font-semibold text-red-300 disabled:opacity-50"
                        >
                          Emergency Stop Broadcast
                        </button>
                      </div>
                    )}

                    {item.snapshot.goLive.status === "EMERGENCY_STOPPED" && (
                      <div className="mt-3 text-xs text-red-300">
                        Emergency stop is active
                        {item.snapshot.goLive.emergencyStopReason
                          ? \`: \${item.snapshot.goLive.emergencyStopReason}\`
                          : "."}
                      </div>
                    )}
                  </div>
                )}

`;

  s=s.slice(0,idx)+block+s.slice(idx);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 23.4 — Operator incident / emergency controls

The broadcast operations console now surfaces the existing production incident and emergency controls.

Available incident controls while go-live status is `DEGRADED`:

```text
Acknowledge Incident
Retry Health Check
```

Available emergency control while a broadcast is active or degraded:

```text
Emergency Stop Broadcast
```

Action mapping:

```text
POST /go-live-sessions/:gameId/acknowledge-incident
POST /go-live-sessions/:gameId/retry-health
POST /go-live-sessions/:gameId/emergency-stop
```

The dashboard does not implement incident-state transitions itself. All enforcement remains in the existing go-live API/service layer.

Incident acknowledgement requires an operator name.

Emergency-stop reason is operator-supplied and the resulting `EMERGENCY_STOPPED` state is displayed in the operations console.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.4 operator incident / emergency controls", () => {
  const page=
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("provides incident controls for degraded broadcasts",()=> {
    expect(page).toContain("Incident / Emergency Controls");
    expect(page).toContain("Acknowledge Incident");
    expect(page).toContain("Retry Health Check");
    expect(page).toContain('"DEGRADED"');
  });

  it("requires operator identity for acknowledgement",()=> {
    expect(page).toContain("incidentOperator");
    expect(page).toContain("!incidentOperator.trim()");
  });

  it("provides emergency stop control",()=> {
    expect(page).toContain("Emergency Stop Broadcast");
    expect(page).toContain("emergencyReason");
    expect(page).toContain('"emergency-stop"');
  });

  it("routes through existing go-live API",()=> {
    expect(page).toContain("/go-live-sessions/");
    expect(page).toContain('"acknowledge-incident"');
    expect(page).toContain('"retry-health"');
  });

  it("does not implement encoder control directly",()=> {
    expect(page).not.toContain("stopEncoderRuntime");
    expect(page).not.toContain("startEncoderRuntime");
  });

  it("shows emergency-stopped state",()=> {
    expect(page).toContain('"EMERGENCY_STOPPED"');
    expect(page).toContain("Emergency stop is active");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 23.4 installed"
echo "============================================================"
echo "Added:"
echo "  - degraded incident controls"
echo "  - operator acknowledgement"
echo "  - retry health check"
echo "  - emergency stop reason"
echo "  - emergency broadcast stop"
echo "  - EMERGENCY_STOPPED visibility"
echo "  - go-live API-only enforcement"
echo "  - Milestone 23.4 regression tests"
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
echo "  Milestone 23.5 - Operator Audit Timeline / Action History"
