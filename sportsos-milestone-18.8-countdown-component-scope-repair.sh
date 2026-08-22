#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.8-countdown-component-scope-repair-${STAMP}"

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

const componentMarker =
  "export function GameDayHardwarePreflightPanel()";

const componentStart =
  text.indexOf(componentMarker);

if (componentStart === -1) {
  throw new Error(
    "Unable to locate GameDayHardwarePreflightPanel component.",
  );
}

/*
 * Remove any previously inserted derived countdown block anywhere in the file.
 * This prevents an out-of-scope copy from fooling future repairs.
 */
const derivedStartMarker =
  "  const remainingFreshnessMs =";

const derivedEndMarker =
  '            : "Preflight is fresh and within the normal game-start window.";';

while (true) {
  const start =
    text.indexOf(derivedStartMarker);

  if (start === -1) {
    break;
  }

  const end =
    text.indexOf(
      derivedEndMarker,
      start,
    );

  if (end === -1) {
    throw new Error(
      "Found partial countdown derived block but could not determine its end.",
    );
  }

  const removeEnd =
    end +
    derivedEndMarker.length;

  text =
    text.slice(0, start) +
    text.slice(removeEnd);
}

const refreshedComponentStart =
  text.indexOf(componentMarker);

const returnIndex =
  text.indexOf(
    "\n  return (",
    refreshedComponentStart,
  );

if (returnIndex === -1) {
  throw new Error(
    "Unable to locate component JSX return.",
  );
}

const block =
`
  const remainingFreshnessMs =
    freshness?.expiresAt
      ? Math.max(
          0,
          Date.parse(
            freshness.expiresAt,
          ) -
            countdownNow,
        )
      : null;

  const remainingFreshnessSeconds =
    remainingFreshnessMs == null
      ? null
      : Math.ceil(
          remainingFreshnessMs /
            1000,
        );

  const remainingFreshnessMinutes =
    remainingFreshnessSeconds == null
      ? null
      : Math.floor(
          remainingFreshnessSeconds /
            60,
        );

  const remainingFreshnessRemainderSeconds =
    remainingFreshnessSeconds == null
      ? null
      : remainingFreshnessSeconds %
        60;

  const preflightGuidance =
    !freshness
      ? "Run a game-day preflight before starting the game."
      : !freshness.fresh
        ? "Preflight is expired or invalid. Rerun it before game start."
        : remainingFreshnessMs != null &&
            remainingFreshnessMs <=
              120000
          ? "Preflight is close to expiration. Rerun now to avoid a start delay."
          : remainingFreshnessMs != null &&
              remainingFreshnessMs <=
                300000
            ? "Preflight is still valid, but the start window is getting short."
            : "Preflight is fresh and within the normal game-start window.";

`;

text =
  text.slice(0, returnIndex) +
  block +
  text.slice(returnIndex);

/*
 * Verify each symbol is declared between the component declaration and JSX return.
 */
const verifyComponentStart =
  text.indexOf(componentMarker);

const verifyReturn =
  text.indexOf(
    "\n  return (",
    verifyComponentStart,
  );

const componentPrefix =
  text.slice(
    verifyComponentStart,
    verifyReturn,
  );

for (const symbol of [
  "const remainingFreshnessMs =",
  "const remainingFreshnessSeconds =",
  "const remainingFreshnessMinutes =",
  "const remainingFreshnessRemainderSeconds =",
  "const preflightGuidance =",
]) {
  if (!componentPrefix.includes(symbol)) {
    throw new Error(
      `Countdown symbol was not inserted in component scope: ${symbol}`,
    );
  }
}

fs.writeFileSync(file, text);

console.log(
  "18.8 countdown variables are now verified inside GameDayHardwarePreflightPanel scope.",
);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 18.8 component-scope repair"
echo "============================================================"
echo
echo "Fixed:"
echo "  - removes stray/out-of-scope countdown declarations"
echo "  - inserts all five derived values inside GameDayHardwarePreflightPanel"
echo "  - verifies declarations appear before the component JSX return"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
