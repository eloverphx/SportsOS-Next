#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-21.7-dashboard-status-union-repair-${STAMP}"

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

const file =
  "apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const start =
  text.indexOf(
    "type GoLiveSession = {",
  );

if (start === -1) {
  throw new Error(
    "GoLiveSession type not found.",
  );
}

const end =
  text.indexOf(
    "\n};",
    start,
  );

if (end === -1) {
  throw new Error(
    "GoLiveSession type closing brace not found.",
  );
}

let block =
  text.slice(
    start,
    end + 3,
  );

/*
 * Remove the bad fallback line added by the previous repair.
 */
block =
  block.replace(
    /\n\s*status:\s*GoLiveSession\["status"\]\s*\|\s*"EMERGENCY_STOPPED";\s*/g,
    "\n",
  );

/*
 * Extend the existing status union instead.
 */
if (
  !block.includes(
    '| "EMERGENCY_STOPPED"'
  )
) {
  const candidates = [
    '    | "ERROR"\n',
    '    | "COMPLETE"\n',
    '    | "DEGRADED"\n',
    '    | "LIVE"\n',
  ];

  let patched =
    false;

  for (
    const candidate of
      candidates
  ) {
    if (
      block.includes(
        candidate,
      )
    ) {
      block =
        block.replace(
          candidate,
          candidate +
            '    | "EMERGENCY_STOPPED"\n',
        );

      patched =
        true;
      break;
    }
  }

  if (!patched) {
    throw new Error(
      "Unable to extend existing GoLiveSession status union.",
    );
  }
}

/*
 * Ensure only one status property remains in the type block.
 */
const statusCount =
  (
    block.match(
      /^\s*status:/gm,
    ) ??
    []
  ).length;

if (
  statusCount !== 1
) {
  throw new Error(
    `Expected exactly one GoLiveSession status property, found ${statusCount}.`,
  );
}

if (
  !block.includes(
    '| "EMERGENCY_STOPPED"'
  )
) {
  throw new Error(
    "EMERGENCY_STOPPED is still missing from status union.",
  );
}

text =
  text.slice(
    0,
    start,
  ) +
  block +
  text.slice(
    end + 3,
  );

fs.writeFileSync(
  file,
  text,
);

console.log(
  "21.7 dashboard status union repaired.",
);
console.log(
  block,
);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 21.7 dashboard status union repair"
echo "============================================================"
echo
echo "Fixed:"
echo "  - removes duplicate GoLiveSession status property"
echo "  - adds EMERGENCY_STOPPED to the original status union"
echo "  - resolves TS2300 / TS2717 duplicate identifier errors"
echo "  - resolves TS2367 impossible comparison errors"
echo "  - no runtime/API behavior changed"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
