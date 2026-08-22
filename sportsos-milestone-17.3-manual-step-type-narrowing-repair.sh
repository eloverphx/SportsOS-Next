#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-17.3-manual-step-type-narrowing-repair-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

FILE="$ROOT/apps/dashboard/app/scoreboards/operations/ScoreboardCommissioningWizard.tsx"

[[ -f "$FILE" ]] || {
  echo "ERROR: missing $FILE" >&2
  exit 1
}

cd "$ROOT"

mkdir -p "$BACKUP/apps/dashboard/app/scoreboards/operations"
cp -a "$FILE" "$BACKUP/apps/dashboard/app/scoreboards/operations/ScoreboardCommissioningWizard.tsx"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/ScoreboardCommissioningWizard.tsx";

let text =
  fs.readFileSync(file, "utf8");

const replacements = [
  [
`                          void setManualStep(
                            step.id,
                            true,
                          )`,
`                          void setManualStep(
                            step.id as
                              | "FLASHED"
                              | "PROVISIONED",
                            true,
                          )`
  ],
  [
`                          void setManualStep(
                            step.id,
                            false,
                          )`,
`                          void setManualStep(
                            step.id as
                              | "FLASHED"
                              | "PROVISIONED",
                            false,
                          )`
  ],
];

let changed = false;

for (const [oldText, newText] of replacements) {
  if (text.includes(oldText)) {
    text = text.replace(oldText, newText);
    changed = true;
  }
}

if (!changed) {
  const alreadyApplied =
    text.includes('step.id as\n                              | "FLASHED"\n                              | "PROVISIONED"');

  if (!alreadyApplied) {
    throw new Error(
      "Unable to locate manual commissioning step calls.",
    );
  }

  console.log("Repair already applied.");
}

fs.writeFileSync(file, text);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 17.3 type narrowing repair installed"
echo "============================================================"
echo
echo "Repair:"
echo "  - explicitly narrows manual step IDs to FLASHED | PROVISIONED"
echo "  - no commissioning behavior changed"
echo "  - fixes dashboard TypeScript errors at the manual-step buttons"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
