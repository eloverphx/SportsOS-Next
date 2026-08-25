#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-23.3-start-confirmation-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

PAGE="apps/dashboard/app/broadcast/operations/page.tsx"
TEST="packages/core/test/broadcast-start-confirmation-23.3.test.ts"
DOC="docs/BROADCAST-OPERATIONS-CONSOLE.md"

for required in ".git" "$PAGE" "$DOC"; do
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

if(!s.includes("const [pendingStartGameId")) {
  const marker=`  const [
    actionMessage,
    setActionMessage,
  ] =
    useState<string | null>(
      null,
    );`;

  if(!s.includes(marker)) throw Error("23.2 action state missing.");

  s=s.replace(
    marker,
`${marker}

  const [
    pendingStartGameId,
    setPendingStartGameId,
  ] =
    useState<string | null>(
      null,
    );`
  );
}

if(!s.includes('"start"')) {
  s=s.replace(
`          | "retry/execute"
          | "stop",`,
`          | "retry/execute"
          | "start"
          | "stop",`
  );
}

if(!s.includes("Confirm Start Broadcast")) {
  const marker=`                    <button
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
                      }`;

  const idx=s.indexOf(marker);
  if(idx<0) throw Error("23.2 stop action button missing.");

  const block=`                    {pendingStartGameId === item.gameId ? (
                      <>
                        <button
                          type="button"
                          disabled={
                            actionGameId ===
                            item.gameId ||
                            !item.health.healthy ||
                            item.snapshot.coordinator.intent !==
                              "PREPARE"
                          }
                          onClick={async () => {
                            await runAction(
                              item.gameId,
                              "start",
                            );

                            setPendingStartGameId(
                              null,
                            );
                          }}
                          className="rounded-lg border border-emerald-800 px-3 py-2 text-xs font-semibold text-emerald-300 disabled:opacity-50"
                        >
                          Confirm Start Broadcast
                        </button>

                        <button
                          type="button"
                          disabled={
                            actionGameId ===
                            item.gameId
                          }
                          onClick={() =>
                            setPendingStartGameId(
                              null,
                            )
                          }
                          className="rounded-lg border border-slate-800 px-3 py-2 text-xs disabled:opacity-50"
                        >
                          Cancel Start
                        </button>
                      </>
                    ) : (
                      <button
                        type="button"
                        disabled={
                          actionGameId ===
                            item.gameId ||
                          !item.health.healthy ||
                          item.snapshot.coordinator.intent !==
                            "PREPARE"
                        }
                        onClick={() =>
                          setPendingStartGameId(
                            item.gameId,
                          )
                        }
                        className="rounded-lg border border-emerald-900/60 px-3 py-2 text-xs font-semibold disabled:opacity-50"
                      >
                        Start Broadcast
                      </button>
                    )}

`;

  s=s.slice(0,idx)+block+s.slice(idx);
}

if(!s.includes("Start requires PREPARE + healthy coordinator")) {
  const marker=`                  <p className="mt-1 text-xs text-slate-500">
                    Actions are routed through the existing broadcast coordinator safety layer.
                  </p>`;

  if(!s.includes(marker)) throw Error("Safe Operator Actions description missing.");

  s=s.replace(
    marker,
`${marker}
                  <p className="mt-1 text-xs text-slate-500">
                    Start requires PREPARE + healthy coordinator and a second operator confirmation.
                  </p>`
  );
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 23.3 — Start broadcast confirmation / guarded operator flow

The operations console now exposes a guarded start flow.

Start is available only when:

```text
coordinator intent = PREPARE
coordinator health = healthy
```

Operator sequence:

```text
Prepare
Review status
Start Broadcast
Confirm Start Broadcast
```

The first click only opens the confirmation state.

The second click sends:

```text
POST /broadcast-coordinator/:gameId/start
```

The dashboard still does not call encoder runtime services directly.

Cancel Start clears the pending confirmation without changing broadcast state.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.3 start broadcast confirmation / guarded operator flow", () => {
  const page=
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("provides two-step start confirmation",()=> {
    expect(page).toContain("Start Broadcast");
    expect(page).toContain("Confirm Start Broadcast");
    expect(page).toContain("Cancel Start");
    expect(page).toContain("pendingStartGameId");
  });

  it("requires healthy coordinator",()=> {
    expect(page).toContain("!item.health.healthy");
  });

  it("requires PREPARE intent",()=> {
    expect(page).toContain('item.snapshot.coordinator.intent !==');
    expect(page).toContain('"PREPARE"');
  });

  it("routes confirmed start through coordinator API",()=> {
    expect(page).toContain('"start"');
    expect(page).toContain("runAction");
    expect(page).toContain("/broadcast-coordinator/");
  });

  it("does not directly start encoder",()=> {
    expect(page).not.toContain("startEncoderRuntime");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 23.3 installed"
echo "============================================================"
echo "Added:"
echo "  - Start Broadcast action"
echo "  - second confirmation step"
echo "  - PREPARE intent guard"
echo "  - coordinator health guard"
echo "  - Cancel Start"
echo "  - coordinator-only start routing"
echo "  - Milestone 23.3 regression tests"
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
echo "  Milestone 23.4 - Operator Incident / Emergency Controls"
