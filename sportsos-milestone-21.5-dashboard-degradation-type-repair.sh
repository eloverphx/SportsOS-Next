#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-21.5-dashboard-degradation-type-repair-${STAMP}"

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

const typeStart =
  text.indexOf(
    "type GoLiveSession = {",
  );

if (typeStart === -1) {
  throw new Error(
    "GoLiveSession type not found.",
  );
}

const typeEnd =
  text.indexOf(
    "};",
    typeStart,
  );

if (typeEnd === -1) {
  throw new Error(
    "GoLiveSession type end not found.",
  );
}

const block =
  text.slice(
    typeStart,
    typeEnd + 2,
  );

if (
  !block.includes(
    "degradedAt:"
  )
) {
  const replacement =
    block.replace(
`  healthySinceAt: string | null;`,
`  healthySinceAt: string | null;
  degradedAt: string | null;
  degradationReason: string | null;`,
    );

  if (
    replacement ===
    block
  ) {
    throw new Error(
      "Unable to locate healthySinceAt in GoLiveSession type.",
    );
  }

  text =
    text.slice(
      0,
      typeStart,
    ) +
    replacement +
    text.slice(
      typeEnd + 2,
    );
}

fs.writeFileSync(
  file,
  text,
);

console.log(
  "21.5 dashboard GoLiveSession degradation fields repaired.",
);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 21.5 dashboard type repair"
echo "============================================================"
echo
echo "Fixed:"
echo "  - GoLiveSession.degradedAt"
echo "  - GoLiveSession.degradationReason"
echo "  - watchdog UI typing only"
echo "  - runtime behavior unchanged"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
