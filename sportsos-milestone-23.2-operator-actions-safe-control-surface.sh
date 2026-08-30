#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-23.2-operator-actions-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

PAGE="apps/dashboard/app/broadcast/operations/page.tsx"
TEST="packages/core/test/broadcast-operator-actions-23.2.test.ts"
DOC="docs/BROADCAST-OPERATIONS-CONSOLE.md"

for required in \
  ".git" \
  "$PAGE" \
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

if(!s.includes("const [actionGameId")) {
  const marker=`  const [
    error,
    setError,
  ] =
    useState<string | null>(
      null,
    );`;

  if(!s.includes(marker)) throw Error("Unable to locate error state.");

  s=s.replace(
    marker,
`${marker}

  const [
    actionGameId,
    setActionGameId,
  ] =
    useState<string | null>(
      null,
    );

  const [
    actionMessage,
    setActionMessage,
  ] =
    useState<string | null>(
      null,
    );`
  );
}

if(!s.includes("const runAction =")) {
  const marker="  const load =";
  const idx=s.indexOf(marker);
  if(idx<0) throw Error("Unable to locate load callback.");

  const fn=`  const runAction =
    useCallback(
      async (
        gameId: string,
        action:
          | "prepare"
          | "reconcile"
          | "retry/execute"
          | "stop",
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
              \`\${API_BASE}/broadcast-coordinator/\${encodeURIComponent(gameId)}/\${action}\`,
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
              \`Operator action failed (\${response.status}).\`,
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
              : "Operator action failed.",
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

if(!s.includes("Safe Operator Actions")) {
  const marker=`                {item.health.issues.length > 0 && (`;
  const idx=s.indexOf(marker);
  if(idx<0) throw Error("Unable to locate operations card insertion point.");

  const block=`                <div className="mt-4 rounded border border-slate-800 p-3">
                  <div className="text-xs font-semibold">
                    Safe Operator Actions
                  </div>
                  <p className="mt-1 text-xs text-slate-500">
                    Actions are routed through the existing broadcast coordinator safety layer.
                  </p>

                  <div className="mt-3 flex flex-wrap gap-2">
                    <button
                      type="button"
                      disabled={
                        actionGameId ===
                        item.gameId
                      }
                      onClick={() =>
                        void runAction(
                          item.gameId,
                          "prepare",
                        )
                      }
                      className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
                    >
                      Prepare
                    </button>

                    <button
                      type="button"
                      disabled={
                        actionGameId ===
                        item.gameId
                      }
                      onClick={() =>
                        void runAction(
                          item.gameId,
                          "reconcile",
                        )
                      }
                      className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
                    >
                      Reconcile
                    </button>

                    <button
                      type="button"
                      disabled={
                        actionGameId ===
                        item.gameId ||
                        item.retry.state !==
                          "SCHEDULED"
                      }
                      onClick={() =>
                        void runAction(
                          item.gameId,
                          "retry/execute",
                        )
                      }
                      className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
                    >
                      Execute Retry
                    </button>

                    <button
                      type="button"
                      disabled={
                        actionGameId ===
                        item.gameId
                      }
                      onClick={() =>
                        void runAction(
                          item.gameId,
                          "stop",
                        )
                      }
                      className="rounded-lg border border-slate-800 px-3 py-2 text-xs disabled:opacity-50"
                    >
                      Stop Broadcast
                    </button>
                  </div>
                </div>

`;

  s=s.slice(0,idx)+block+s.slice(idx);
}

if(!s.includes("{actionMessage && (")) {
  const marker=`      {error && (
        <div className="mt-4 rounded-lg border border-red-900/50 bg-red-950/20 p-4 text-sm text-red-300">
          {error}
        </div>
      )}`;

  if(!s.includes(marker)) throw Error("Unable to locate error banner.");

  s=s.replace(
    marker,
`${marker}

      {actionMessage && (
        <div className="mt-4 rounded-lg border border-slate-800 p-4 text-sm text-slate-300">
          {actionMessage}
        </div>
      )}`
  );
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 23.2 — Operator actions / safe control surface

The broadcast operations console now exposes bounded operator actions:

```text
Prepare
Reconcile
Execute Retry
Stop Broadcast
```

All actions call the existing coordinator endpoints.

The dashboard does not call encoder runtime services directly and does not duplicate safety logic.

Action mapping:

```text
Prepare       -> POST /broadcast-coordinator/:gameId/prepare
Reconcile     -> POST /broadcast-coordinator/:gameId/reconcile
Execute Retry -> POST /broadcast-coordinator/:gameId/retry/execute
Stop Broadcast-> POST /broadcast-coordinator/:gameId/stop
```

Retry execution is disabled unless the coordinator retry state is `SCHEDULED`.

Operator action results are surfaced in the console and the summary refreshes after successful actions.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.2 operator actions / safe control surface", () => {
  const page=
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("provides safe operator action controls",()=> {
    expect(page).toContain("Safe Operator Actions");
    expect(page).toContain("Prepare");
    expect(page).toContain("Reconcile");
    expect(page).toContain("Execute Retry");
    expect(page).toContain("Stop Broadcast");
  });

  it("routes controls through coordinator API",()=> {
    expect(page).toContain("/broadcast-coordinator/");
    expect(page).toContain('"prepare"');
    expect(page).toContain('"reconcile"');
    expect(page).toContain('"retry/execute"');
    expect(page).toContain('"stop"');
  });

  it("does not call encoder runtime directly",()=> {
    expect(page).not.toContain("startEncoderRuntime");
    expect(page).not.toContain("stopEncoderRuntime");
  });

  it("guards retry execution by scheduled state",()=> {
    expect(page).toContain('item.retry.state !==');
    expect(page).toContain('"SCHEDULED"');
  });

  it("refreshes after successful operator action",()=> {
    expect(page).toContain("await load()");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 23.2 installed"
echo "============================================================"
echo "Added:"
echo "  - Prepare action"
echo "  - Reconcile action"
echo "  - Execute Retry action"
echo "  - Stop Broadcast action"
echo "  - action feedback banner"
echo "  - coordinator-only action routing"
echo "  - no direct encoder control from dashboard"
echo "  - Milestone 23.2 regression tests"
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
echo "  Milestone 23.3 - Start Broadcast Confirmation / Guarded Operator Flow"
