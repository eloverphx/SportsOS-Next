#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
ROUTE="${ROOT}/apps/api/src/routes/broadcastSessionCoordinator.ts"
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

mkdir -p "$BACKUP/apps/api/src/routes"
cp -a "$ROUTE" "$BACKUP/$ROUTE"

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
} else {
  // Defensive recovery for partially edited copies.
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
echo " SportsOS Milestone 24.2 heartbeat type repair installed"
echo "============================================================"
echo "Changed:"
echo "  - removed unsupported telemetry.lastOutputAt"
echo "  - removed unsupported telemetry.updatedAt"
echo "  - removed unsupported session.updatedAt"
echo "  - heartbeat now uses existing telemetry.lastProgressAt"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
