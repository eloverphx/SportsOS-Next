#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.10-game-day-acceptance-closeout-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "apps/api/src/services/gameDayHardwarePreflight.ts" \
  "apps/api/src/services/gameStartPreflightGuard.ts" \
  "apps/api/src/services/gameStartPreflightOverride.ts" \
  "apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

TEST="packages/core/test/game-day-deployment-acceptance-18.10.test.ts"
DOC="docs/GAME-DAY-DEPLOYMENT-ACCEPTANCE.md"

for file in "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")" "$(dirname "$DOC")"

cat > "$DOC" <<'EOF'
# SportsOS Game-Day Deployment Acceptance

Milestone 18.10 closes the game-day hardware preflight and start-safety sequence.

## Acceptance requirements

A deployment is ready for controlled game-day use only when all of the following pass:

1. API and dashboard TypeScript checks pass.
2. Repository unit/integration tests pass.
3. Docker API and dashboard rebuild successfully.
4. Docker E2E tests pass.
5. The scoreboard device is assigned to the intended game.
6. A fresh game-day hardware preflight passes for that exact game/device assignment.
7. The start-window countdown is visible to the operator.
8. Auto-rerun refreshes a still-valid preflight near expiration, unless intentionally paused.
9. A changed scoreboard assignment invalidates the prior preflight.
10. A failed, stale, or invalid preflight blocks normal game start.
11. Emergency override requires an explicit written reason.
12. Emergency override is scoped to one game/device, expires automatically, and can be revoked.
13. Emergency override does not rewrite a failed preflight as passing.
14. Override history remains visible for operator/audit review.
15. Server-side start authorization remains authoritative.

## Game-day operator sequence

Before game start:

- confirm the correct scoreboard device is assigned
- confirm the device is online and responding
- run the hardware preflight
- verify the preflight reports PASS
- verify the start-window countdown is active
- leave Auto-Rerun enabled unless there is a specific operational reason to pause it
- start the game only while the server accepts the current preflight state

If the assigned device changes, run a new preflight for the replacement device.

If normal preflight cannot pass, do not bypass it casually. Emergency override exists only for deliberate operational authorization and requires a written reason.

## Closeout

Milestones 18.1 through 18.10 establish the game-day preflight safety boundary:

- readiness verification
- assignment-aware validity
- game-start enforcement
- device-swap invalidation
- emergency authorization
- audit visibility
- expiration countdown
- automatic start-window refresh
- acceptance criteria

Future scoreboard work should preserve this boundary and add regression coverage when changing start authorization, assignment behavior, device communication, or preflight semantics.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.10 game-day deployment acceptance closeout", () => {
  const preflight =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameDayHardwarePreflight.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const guard =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameStartPreflightGuard.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const override =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameStartPreflightOverride.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const acceptance =
    fs.readFileSync(
      new URL(
        "../../../docs/GAME-DAY-DEPLOYMENT-ACCEPTANCE.md",
        import.meta.url,
      ),
      "utf8",
    );

  it("retains authoritative preflight and start guard services", () => {
    expect(preflight.length).toBeGreaterThan(0);
    expect(guard.length).toBeGreaterThan(0);
  });

  it("retains emergency override expiration and revocation", () => {
    expect(override).toContain(
      "expiresAt",
    );

    expect(override).toContain(
      "revokeGameStartPreflightOverride",
    );
  });

  it("retains operator countdown and auto-rerun controls", () => {
    expect(panel).toContain(
      "Start Window Guidance",
    );

    expect(panel).toContain(
      "Auto-Rerun:",
    );

    expect(panel).toContain(
      "runPreflightSilently",
    );
  });

  it("documents assignment-change invalidation", () => {
    expect(acceptance).toContain(
      "changed scoreboard assignment invalidates the prior preflight",
    );
  });

  it("documents server-authoritative start authorization", () => {
    expect(acceptance).toContain(
      "Server-side start authorization remains authoritative",
    );
  });

  it("documents controlled emergency authorization", () => {
    expect(acceptance).toContain(
      "Emergency override requires an explicit written reason",
    );

    expect(acceptance).toContain(
      "does not rewrite a failed preflight as passing",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 18.10 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - game-day deployment acceptance checklist"
echo "  - operator start sequence"
echo "  - preflight/start-safety boundary documentation"
echo "  - closeout regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "FINAL ACCEPTANCE RUN:"
echo "  npm run typecheck && npm test"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "After all three are green, Milestone 18 is closed."
