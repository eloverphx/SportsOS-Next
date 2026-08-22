#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.9-useref-import-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

FILE="$ROOT/apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx"

[[ -f "$FILE" ]] || {
  echo "ERROR: missing $FILE" >&2
  exit 1
}

cd "$ROOT"

mkdir -p "$BACKUP/apps/dashboard/app/scoreboards/operations"
cp -a "$FILE" "$BACKUP/apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx";

let text =
  fs.readFileSync(file, "utf8");

const importBlockRegex =
  /import\s*\{([\s\S]*?)\}\s*from\s*"react";/;

const match =
  text.match(importBlockRegex);

if (!match) {
  throw new Error(
    'Unable to locate import { ... } from "react";',
  );
}

const imports =
  match[1]
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);

if (!imports.includes("useRef")) {
  imports.push("useRef");
}

const preferredOrder = [
  "useCallback",
  "useEffect",
  "useRef",
  "useState",
];

imports.sort((a, b) => {
  const ai =
    preferredOrder.indexOf(a);
  const bi =
    preferredOrder.indexOf(b);

  if (ai === -1 && bi === -1) {
    return a.localeCompare(b);
  }

  if (ai === -1) return 1;
  if (bi === -1) return -1;

  return ai - bi;
});

const replacement =
`import {
  ${imports.join(",\n  ")},
} from "react";`;

text =
  text.replace(
    importBlockRegex,
    replacement,
  );

if (
  !/import\s*\{[\s\S]*?\buseRef\b[\s\S]*?\}\s*from\s*"react";/.test(
    text,
  )
) {
  throw new Error(
    "useRef import verification failed.",
  );
}

fs.writeFileSync(file, text);

console.log(
  "Added and verified React useRef import.",
);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 18.9 useRef import repair"
echo "============================================================"
echo
echo "Fixed:"
echo "  - imports useRef from React"
echo "  - no preflight logic changed"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
