#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-21.5-dashboard-degradation-type-repair-v2-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

FILE="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"

[[ -f "$FILE" ]] || {
  echo "ERROR: missing $ROOT/$FILE" >&2
  exit 1
}

mkdir -p "$BACKUP/$(dirname "$FILE")"
cp -a "$FILE" "$BACKUP/$FILE"

node <<'NODE'
const fs = require("fs");
const file = "apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx";
let text = fs.readFileSync(file, "utf8");

const start = text.indexOf("type GoLiveSession = {");
if (start === -1) throw new Error("GoLiveSession type not found.");

const end = text.indexOf("\n};", start);
if (end === -1) throw new Error("GoLiveSession type closing brace not found.");

let block = text.slice(start, end + 3);

if (!block.includes('| "DEGRADED"')) {
  block = block.replace(
    '    | "LIVE"\n',
    '    | "LIVE"\n    | "DEGRADED"\n',
  );
}

if (!block.includes("degradedAt:")) {
  block = block.replace(
    "\n};",
    "\n  degradedAt: string | null;\n  degradationReason: string | null;\n};",
  );
}

if (!block.includes("degradationReason:")) {
  throw new Error("Failed to add degradationReason to GoLiveSession.");
}

text = text.slice(0, start) + block + text.slice(end + 3);
fs.writeFileSync(file, text);

console.log("GoLiveSession type block repaired.");
console.log(block);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 21.5 dashboard type repair v2"
echo "============================================================"
echo
echo "Fixed:"
echo "  - structurally patches GoLiveSession type"
echo "  - adds DEGRADED status if missing"
echo "  - adds degradedAt"
echo "  - adds degradationReason"
echo "  - no runtime/watchdog logic changed"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
