#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
REL_ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
ROUTE="${ROOT}/${REL_ROUTE}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-24.2-heartbeat-type-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

[[ -f "$ROUTE" ]] || {
  echo "ERROR: missing $ROUTE" >&2
  exit 1
}

mkdir -p "$BACKUP/$(dirname "$REL_ROUTE")"
cp -a "$REL_ROUTE" "$BACKUP/$REL_ROUTE"

node <<'NODE'
const fs = require("fs");

const file =
  "/mnt/user/appdata/SportsOS-Next/apps/api/src/routes/broadcastSessionCoordinator.ts";

let source =
  fs.readFileSync(
    file,
    "utf8",
  );

const oldBlock = `      const lastActivityAt =
        telemetry.lastOutputAt ??
        telemetry.lastProgressAt ??
        telemetry.updatedAt ??
        session.updatedAt ??
        null;`;

const newBlock = `      const lastActivityAt =
        telemetry.lastProgressAt ??
        null;`;

if (source.includes(oldBlock)) {
  source =
    source.replace(
      oldBlock,
      newBlock,
    );
} else if (
  source.includes(
    "telemetry.lastOutputAt",
  ) ||
  source.includes(
    "telemetry.updatedAt",
  ) ||
  source.includes(
    "session.updatedAt",
  )
) {
  source =
    source.replace(
      /      const lastActivityAt =[\s\S]*?        null;/,
      newBlock,
    );
}

if (
  source.includes(
    "telemetry.lastOutputAt",
  ) ||
  source.includes(
    "telemetry.updatedAt",
  ) ||
  source.includes(
    "session.updatedAt",
  )
) {
  throw new Error(
    "Unsupported heartbeat timestamp references remain after repair.",
  );
}

if (
  !source.includes(
    "telemetry.lastProgressAt",
  )
) {
  throw new Error(
    "Expected existing telemetry.lastProgressAt field was not found.",
  );
}

fs.writeFileSync(
  file,
  source,
);

console.log(
  "24.2 heartbeat route repaired to use EncoderTelemetry.lastProgressAt only.",
);
NODE

echo
echo "============================================================"
echo " SportsOS Milestone 24.2 heartbeat type repair v2 installed"
echo "============================================================"
echo "Changed:"
echo "  - removed unsupported telemetry.lastOutputAt"
echo "  - removed unsupported telemetry.updatedAt"
echo "  - removed unsupported session.updatedAt"
echo "  - heartbeat now uses telemetry.lastProgressAt"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
