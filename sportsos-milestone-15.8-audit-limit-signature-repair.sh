#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-15.8-audit-limit-signature-repair-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

FILE="$ROOT/apps/api/src/services/scoreboardControlAudit.ts"

[[ -f "$FILE" ]] || {
  echo "ERROR: missing $FILE" >&2
  exit 1
}

cd "$ROOT"

mkdir -p "$BACKUP/apps/api/src/services"
cp -a "$FILE" "$BACKUP/apps/api/src/services/scoreboardControlAudit.ts"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/scoreboardControlAudit.ts";

let text =
  fs.readFileSync(file, "utf8");

const oldBlock =
`  return listScoreboardControlAudit(
    Math.max(
      100,
      Math.min(
        limit * 5,
        1000,
      ),
    ),
  )`;

const newBlock =
`  return listScoreboardControlAudit({
    limit:
      Math.max(
        100,
        Math.min(
          limit * 5,
          1000,
        ),
      ),
  })`;

if (text.includes(newBlock)) {
  console.log("Repair already applied.");
  process.exit(0);
}

if (!text.includes(oldBlock)) {
  throw new Error(
    "Unable to locate the Milestone 15.8 incident audit call.",
  );
}

text =
  text.replace(
    oldBlock,
    newBlock,
  );

fs.writeFileSync(file, text);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 15.8 audit signature repair installed"
echo "============================================================"
echo
echo "Repair:"
echo "  - listScoreboardControlAudit(number)"
echo "    -> listScoreboardControlAudit({ limit: number })"
echo "  - incident filtering behavior unchanged"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
