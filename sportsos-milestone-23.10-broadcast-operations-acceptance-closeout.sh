#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-23.10-broadcast-operations-closeout-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

OPS_PAGE="apps/dashboard/app/broadcast/operations/page.tsx"
FOCUS_PAGE="apps/dashboard/app/broadcast/operations/[gameId]/page.tsx"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
NOTES="apps/api/src/services/broadcastOperatorNotes.ts"
TEST="packages/core/test/broadcast-operations-acceptance-23.10.test.ts"
REPORT="docs/MILESTONE-23-BROADCAST-OPERATIONS-ACCEPTANCE.md"
DOC="docs/BROADCAST-OPERATIONS-CONSOLE.md"

for required in \
  ".git" \
  "$OPS_PAGE" \
  "$FOCUS_PAGE" \
  "$ROUTE" \
  "$NOTES" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$TEST" "$REPORT" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

# Fail before modification if Milestone 23 wiring is incomplete.
node <<'NODE'
const fs=require("fs");

const files = {
  operations: fs.readFileSync("apps/dashboard/app/broadcast/operations/page.tsx","utf8"),
  focus: fs.readFileSync("apps/dashboard/app/broadcast/operations/[gameId]/page.tsx","utf8"),
  route: fs.readFileSync("apps/api/src/routes/broadcastSessionCoordinator.ts","utf8"),
  notes: fs.readFileSync("apps/api/src/services/broadcastOperatorNotes.ts","utf8"),
};

const checks = [
  ["23.1 operations console", files.operations, "Broadcast Operations"],
  ["23.2 safe actions", files.operations, "Safe Operator Actions"],
  ["23.3 start confirmation", files.operations, "Confirm Start Broadcast"],
  ["23.4 incident controls", files.operations, "Incident / Emergency Controls"],
  ["23.5 operator timeline", files.operations, "Operator Timeline"],
  ["23.6 attention queue", files.operations, "Operator Attention Queue"],
  ["23.7 focus mode link", files.operations, "Open Focus Mode"],
  ["23.7 focus workspace", files.focus, "Broadcast Focus"],
  ["23.8 shift handoff notes", files.focus, "Shift Handoff Notes"],
  ["23.9 handoff snapshot", files.focus, "Shift Handoff Snapshot"],
  ["23.1 summary API", files.route, '"/broadcast-coordinator/operations-summary"'],
  ["23.5 timeline API", files.route, '"/broadcast-coordinator/:gameId/operator-timeline"'],
  ["23.6 attention API", files.route, '"/broadcast-coordinator/attention-queue"'],
  ["23.8 notes API", files.route, '"/broadcast-coordinator/:gameId/operator-notes"'],
  ["23.9 handoff API", files.route, '"/broadcast-coordinator/:gameId/handoff-summary"'],
  ["notes persistence", files.notes, "broadcast-operator-notes.json"],
];

for (const [name, source, needle] of checks) {
  if (!source.includes(needle)) {
    throw new Error(`Milestone 23 prerequisite missing: ${name} (${needle})`);
  }
}
NODE

mkdir -p "$(dirname "$TEST")" "$(dirname "$REPORT")"

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.10 broadcast operations acceptance", () => {
  const operations =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const focus =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/[gameId]/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const notes =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastOperatorNotes.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("retains consolidated broadcast operations visibility",()=> {
    expect(operations).toContain("Broadcast Operations");
    expect(operations).toContain("Operator Attention Queue");
    expect(operations).toContain("Coordinator Issues");
  });

  it("retains guarded operator controls",()=> {
    expect(operations).toContain("Safe Operator Actions");
    expect(operations).toContain("Confirm Start Broadcast");
    expect(operations).toContain("Acknowledge Incident");
    expect(operations).toContain("Emergency Stop Broadcast");
  });

  it("retains focus mode workspace",()=> {
    expect(operations).toContain("Open Focus Mode");
    expect(focus).toContain("Broadcast Focus");
    expect(focus).toContain("Safe Operator Actions");
    expect(focus).toContain("Operator Timeline");
  });

  it("retains shift handoff features",()=> {
    expect(focus).toContain("Shift Handoff Notes");
    expect(focus).toContain("Shift Handoff Snapshot");
    expect(focus).toContain("Generate Handoff Snapshot");
  });

  it("retains operator-facing APIs",()=> {
    expect(route).toContain('"/broadcast-coordinator/operations-summary"');
    expect(route).toContain('"/broadcast-coordinator/attention-queue"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/operator-timeline"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/operator-notes"');
    expect(route).toContain('"/broadcast-coordinator/:gameId/handoff-summary"');
  });

  it("keeps notes separate from control state",()=> {
    expect(notes).toContain("broadcast-operator-notes.json");
    expect(notes).not.toContain("startEncoderRuntime");
    expect(notes).not.toContain("stopEncoderRuntime");
    expect(notes).not.toContain("setBroadcastCoordinatorIntent");
  });

  it("does not let dashboard directly control encoder runtime",()=> {
    expect(operations).not.toContain("startEncoderRuntime");
    expect(operations).not.toContain("stopEncoderRuntime");
    expect(focus).not.toContain("startEncoderRuntime");
    expect(focus).not.toContain("stopEncoderRuntime");
  });

  it("keeps five-second operational refresh",()=> {
    expect(operations).toContain("5000");
    expect(focus).toContain("5000");
  });
});
EOF

cat > "$REPORT" <<'EOF'
# SportsOS Milestone 23 — Broadcast Operations Acceptance

Milestone 23 completes the first operator-experience pass for production broadcast operations.

## Accepted capabilities

- consolidated broadcast operations console
- safe operator control surface
- guarded two-step broadcast start
- degraded incident controls
- emergency-stop controls
- combined operator timeline
- ranked attention queue
- per-broadcast Focus Mode
- persistent shift-handoff notes
- on-demand handoff snapshot

## Operator safety invariants

The dashboard must not directly:

- start FFmpeg
- stop FFmpeg
- mutate encoder runtime state
- bypass coordinator preflight
- bypass go-live incident controls
- create a second authoritative broadcast lifecycle

Operator notes and handoff summaries are context only.

## Production acceptance gate

Milestone 23 is accepted only when all of the following are green:

```text
npm run typecheck
npm test
docker compose up -d --build api dashboard
docker compose ps
curl -fsS http://127.0.0.1:4001/health
npm run test:e2e:docker
```

The API and dashboard must both be running normally after the combined Docker Compose command.

## Closeout

After acceptance, commit and tag Milestone 23 before beginning Milestone 24.
EOF

cat >> "$DOC" <<'EOF'

## Milestone 23.10 — Broadcast operations acceptance / closeout

Milestone 23 acceptance is documented in:

```text
docs/MILESTONE-23-BROADCAST-OPERATIONS-ACCEPTANCE.md
```

The closeout regression suite verifies the operations console, guarded controls, incident/emergency actions, attention queue, Focus Mode, audit timeline, shift notes, handoff snapshot, and the rule that dashboard code never directly controls the encoder runtime.

Milestone 23 is complete only after typecheck, unit tests, combined API/dashboard Docker startup, API health verification, and Docker E2E tests are all green.
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 23.10 installed"
echo "============================================================"
echo "Added:"
echo "  - Milestone 23 prerequisite validation"
echo "  - operations acceptance regression suite"
echo "  - operator safety invariant checks"
echo "  - production Docker health acceptance"
echo "  - Milestone 23 acceptance document"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Acceptance run:"
echo "  npm run typecheck && npm test"
echo "  docker compose up -d --build api dashboard"
echo "  docker compose ps"
echo "  curl -fsS http://127.0.0.1:4001/health"
echo "  npm run test:e2e:docker"
echo
echo "If everything is green:"
echo '  git add -A'
echo '  git commit -m "feat(broadcast): complete milestone 23 operator experience"'
echo '  git tag -a sportsos-m23-complete -m "SportsOS Milestone 23 complete"'
echo
echo "Next after commit/tag:"
echo "  Milestone 24 - Broadcast Resilience / Production Hardening"
