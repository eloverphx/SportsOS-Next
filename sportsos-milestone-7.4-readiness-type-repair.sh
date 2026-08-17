#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.4-readiness-type-repair"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/${MILESTONE}-${STAMP}"

cd "$ROOT"

READINESS_LIB="apps/dashboard/lib/tournament-pregame-readiness.ts"
READINESS_TEST="apps/dashboard/test/tournament-pregame-readiness-7.2.test.ts"

for file in "$READINESS_LIB" "$READINESS_TEST"; do
  [[ -f "$file" ]] || { echo "ERROR: required file missing: $file" >&2; exit 1; }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$READINESS_LIB")" \
  "$BACKUP_DIR/$(dirname "$READINESS_TEST")"

cp -a "$READINESS_LIB" "$BACKUP_DIR/$READINESS_LIB"
cp -a "$READINESS_TEST" "$BACKUP_DIR/$READINESS_TEST"

node <<'NODE'
const fs = require("fs");

const file = "apps/dashboard/lib/tournament-pregame-readiness.ts";
let text = fs.readFileSync(file, "utf8");

const signatures = [
  "buildPregameReadinessChecks",
  "buildPregameReadinessSummary",
];

for (const fn of signatures) {
  const re = new RegExp(
    `(export function ${fn}\\([\\s\\S]*?operationalState:\\s*\\{)([\\s\\S]*?)(\\}\\s*=\\s*\\{\\},)`
  );

  const match = text.match(re);

  if (!match) {
    throw new Error(`Could not locate operationalState type for ${fn}.`);
  }

  let body = match[2];

  if (!body.includes("teamCheckInReady?: boolean;")) {
    body += `\n    teamCheckInReady?: boolean;`;
  }

  if (!body.includes("rosterLockReady?: boolean;")) {
    body += `\n    rosterLockReady?: boolean;`;
  }

  const replacement = `${match[1]}${body}${match[3]}`;
  text = text.replace(match[0], replacement);
}

if (!text.includes('"rosterLock"')) {
  throw new Error("Roster lock readiness check is missing.");
}

if (!text.includes("operationalState.rosterLockReady === true")) {
  throw new Error("Roster lock readiness mapping is missing.");
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");

const file = "apps/dashboard/test/tournament-pregame-readiness-7.2.test.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("accepts roster-lock operational readiness")) {
  text += `

describe("Milestone 7.4 readiness integration", () => {
  it("accepts roster-lock operational readiness", () => {
    const summary = buildPregameReadinessSummary(
      game(),
      false,
      {
        teamCheckInReady: true,
        rosterLockReady: true,
      },
    );

    expect(
      summary.checks.find((check) => check.id === "teamCheckIn")?.state,
    ).toBe("PASS");

    expect(
      summary.checks.find((check) => check.id === "rosterLock")?.state,
    ).toBe("PASS");
  });
});
`;
}

fs.writeFileSync(file, text);
NODE

echo
echo "Milestone 7.4 readiness type repair complete."
echo
echo "Fixed:"
echo "  - buildPregameReadinessChecks operationalState type"
echo "  - buildPregameReadinessSummary operationalState type"
echo "  - rosterLockReady accepted in both"
echo "  - regression test added"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
