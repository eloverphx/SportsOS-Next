#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-16.1-device-id-readiness-repair-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

FILE="$ROOT/apps/api/src/services/scoreboardControlReadiness.ts"
REPO="$ROOT/apps/api/src/modules/scoreboard-devices/repository.ts"

for required in "$FILE" "$REPO"; do
  [[ -f "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

mkdir -p "$BACKUP/apps/api/src/services"
cp -a "$FILE" "$BACKUP/apps/api/src/services/scoreboardControlReadiness.ts"

node <<'NODE'
const fs = require("fs");

const repoFile =
  "apps/api/src/modules/scoreboard-devices/repository.ts";

const serviceFile =
  "apps/api/src/services/scoreboardControlReadiness.ts";

const repo =
  fs.readFileSync(
    repoFile,
    "utf8",
  );

let service =
  fs.readFileSync(
    serviceFile,
    "utf8",
  );

const exportNames = [
  ...repo.matchAll(
    /export\s+(?:async\s+)?function\s+([A-Za-z0-9_]+)/g,
  ),
  ...repo.matchAll(
    /export\s+const\s+([A-Za-z0-9_]+)/g,
  ),
].map(
  (match) =>
    match[1],
);

const preferred = [
  "findScoreboardDeviceByDeviceId",
  "findScoreboardDeviceByExternalId",
  "findScoreboardDeviceByHardwareId",
  "findScoreboardDeviceByIdentifier",
  "findScoreboardDeviceByKey",
];

let lookup =
  preferred.find(
    (name) =>
      exportNames.includes(name),
  ) ??
  null;

if (!lookup) {
  const candidate =
    exportNames.find(
      (name) =>
        /find.*scoreboard.*device/i.test(
          name,
        ) &&
        name !==
          "findScoreboardDeviceById",
    );

  if (candidate) {
    lookup =
      candidate;
  }
}

if (lookup) {
  service =
    service.replace(
      /import\s*\{\s*findScoreboardDeviceById,\s*\}\s*from\s*"\.\.\/modules\/scoreboard-devices\/repository\.js";/,
      `import { ${lookup} } from "../modules/scoreboard-devices/repository.js";`,
    );

  service =
    service.replace(
      /await findScoreboardDeviceById\(\s*deviceId,\s*\)/,
      `await ${lookup}(
      deviceId,
    )`,
    );

  fs.writeFileSync(
    serviceFile,
    service,
  );

  console.log(
    `Using repository lookup: ${lookup}`,
  );

  process.exit(0);
}

if (
  !exportNames.includes(
    "listScoreboardDevices",
  )
) {
  throw new Error(
    "No string-compatible scoreboard-device lookup or listScoreboardDevices() export was found.",
  );
}

service =
  service.replace(
    /import\s*\{\s*findScoreboardDeviceById,\s*\}\s*from\s*"\.\.\/modules\/scoreboard-devices\/repository\.js";/,
    'import { listScoreboardDevices } from "../modules/scoreboard-devices/repository.js";',
  );

service =
  service.replace(
    /const device\s*=\s*await findScoreboardDeviceById\(\s*deviceId,\s*\);/,
`const devices =
    await listScoreboardDevices();

  const device =
    devices.find(
      (candidate) => {
        const record =
          candidate as unknown as
            Record<string, unknown>;

        return [
          record.deviceId,
          record.externalId,
          record.hardwareId,
          record.identifier,
          record.key,
          record.serialNumber,
        ].some(
          (value) =>
            typeof value ===
              "string" &&
            value ===
              deviceId,
        );
      },
    ) ?? null;`,
  );

fs.writeFileSync(
  serviceFile,
  service,
);

console.log(
  "Using listScoreboardDevices() fallback for string device ID resolution.",
);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 16.1 device-ID readiness repair installed"
echo "============================================================"
echo
echo "Repair:"
echo "  - removes numeric-ID lookup misuse"
echo "  - discovers an existing string device lookup when available"
echo "  - otherwise matches deviceId through listScoreboardDevices()"
echo "  - heartbeat readiness logic unchanged"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
