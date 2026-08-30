#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-21.2-reset-schedule-fields-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

FILE="apps/api/src/services/goLiveSession.ts"

[[ -f "$FILE" ]] || {
  echo "ERROR: missing $ROOT/$FILE" >&2
  exit 1
}

mkdir -p "$BACKUP/$(dirname "$FILE")"
cp -a "$FILE" "$BACKUP/$FILE"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/goLiveSession.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const marker =
`    lastError:
      null,
  });
}`;

const replacement =
`    lastError:
      null,
    scheduledStartAt:
      null,
    startWindowEarlyMinutes:
      15,
    startWindowLateMinutes:
      15,
  });
}`;

const resetIdx =
  text.indexOf(
    "export function resetGoLiveSession",
  );

if (resetIdx === -1) {
  throw new Error(
    "Unable to locate resetGoLiveSession.",
  );
}

const tail =
  text.slice(
    resetIdx,
  );

if (
  tail.includes(
    "scheduledStartAt:"
  )
) {
  console.log(
    "resetGoLiveSession already contains schedule fields.",
  );
} else {
  const relative =
    tail.indexOf(
      marker,
    );

  if (relative === -1) {
    throw new Error(
      "Unable to locate resetGoLiveSession return shape.",
    );
  }

  const absolute =
    resetIdx +
    relative;

  text =
    text.slice(
      0,
      absolute,
    ) +
    replacement +
    text.slice(
      absolute +
      marker.length,
    );
}

fs.writeFileSync(
  file,
  text,
);

console.log(
  "21.2 reset schedule fields repaired.",
);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 21.2 reset repair"
echo "============================================================"
echo
echo "Fixed:"
echo "  - resetGoLiveSession now returns scheduledStartAt"
echo "  - reset defaults early window to 15 minutes"
echo "  - reset defaults late window to 15 minutes"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
