#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-18.8-countdown-scope-repair-${STAMP}"

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

if (text.includes("const remainingFreshnessMs =")) {
  console.log("Countdown derived variables already present.");
  process.exit(0);
}

const returnMarker = "\n  return (";
const idx = text.lastIndexOf(returnMarker);

if (idx === -1) {
  throw new Error("Unable to locate component return.");
}

const block = `
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
  text.slice(0, idx) +
  block +
  text.slice(idx);

fs.writeFileSync(file, text);

console.log("Inserted countdown derived state immediately before component return.");
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 18.8 countdown scope repair"
echo "============================================================"
echo
echo "Fixed:"
echo "  - remainingFreshnessMs"
echo "  - remainingFreshnessSeconds"
echo "  - remainingFreshnessMinutes"
echo "  - remainingFreshnessRemainderSeconds"
echo "  - preflightGuidance"
echo "  - keeps existing 18.8 UI and countdown behavior unchanged"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
