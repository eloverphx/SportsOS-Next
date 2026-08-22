#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-17.8-commandid-type-repair-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

FILE="$ROOT/apps/api/src/routes/scoreboardDeviceCommissioning.ts"

[[ -f "$FILE" ]] || {
  echo "ERROR: missing $FILE" >&2
  exit 1
}

cd "$ROOT"

mkdir -p "$BACKUP/apps/api/src/routes"
cp -a "$FILE" "$BACKUP/apps/api/src/routes/scoreboardDeviceCommissioning.ts"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardDeviceCommissioning.ts";

let text =
  fs.readFileSync(file, "utf8");

const telemetryRoute =
  '"/scoreboard-device-commissioning/:deviceId/self-test/telemetry"';

const routeIndex =
  text.indexOf(telemetryRoute);

if (routeIndex === -1) {
  throw new Error(
    "Unable to locate firmware self-test telemetry route.",
  );
}

const bodyTypeStart =
  text.indexOf(
    "const body =",
    routeIndex,
  );

if (bodyTypeStart === -1) {
  throw new Error(
    "Unable to locate telemetry request body type.",
  );
}

const bodyTypeEnd =
  text.indexOf(
    "};",
    bodyTypeStart,
  );

if (bodyTypeEnd === -1) {
  throw new Error(
    "Unable to locate telemetry request body type end.",
  );
}

const bodyType =
  text.slice(
    bodyTypeStart,
    bodyTypeEnd + 2,
  );

if (
  bodyType.includes(
    "commandId?: string;"
  )
) {
  console.log(
    "commandId telemetry type already present.",
  );
  process.exit(0);
}

const anchor =
  "          detail?: string;";

if (!bodyType.includes(anchor)) {
  throw new Error(
    "Unable to locate telemetry detail field for commandId insertion.",
  );
}

const repairedBodyType =
  bodyType.replace(
    anchor,
`          detail?: string;
          commandId?: string;`
  );

text =
  text.slice(
    0,
    bodyTypeStart,
  ) +
  repairedBodyType +
  text.slice(
    bodyTypeEnd + 2,
  );

fs.writeFileSync(
  file,
  text,
);

console.log(
  "Added commandId?: string to firmware telemetry request body type.",
);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 17.8 commandId type repair"
echo "============================================================"
echo
echo "Repair:"
echo "  - adds commandId?: string to self-test telemetry body type"
echo "  - keeps existing 17.8 correlation logic unchanged"
echo "  - fixes TS2339 errors at body.commandId"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo "  bash firmware/esp32-scoreboard/build-in-docker.sh"
