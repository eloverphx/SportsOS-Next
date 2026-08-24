#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-21.8-duplicate-audit-state-repair-${STAMP}"

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

const pattern =
`  const [
    goLiveAudit,
    setGoLiveAudit,
  ] =
    useState<GoLiveAuditEvent[]>(
      [],
    );`;

const first =
  text.indexOf(
    pattern,
  );

if (
  first === -1
) {
  throw new Error(
    "goLiveAudit state declaration not found.",
  );
}

const second =
  text.indexOf(
    pattern,
    first +
    pattern.length,
  );

if (
  second === -1
) {
  console.log(
    "No duplicate goLiveAudit state block found; no change required.",
  );
} else {
  text =
    text.slice(
      0,
      second,
    ) +
    text.slice(
      second +
      pattern.length,
    );

  const third =
    text.indexOf(
      pattern,
      first +
      pattern.length,
    );

  if (
    third !== -1
  ) {
    throw new Error(
      "More than two goLiveAudit state declarations found; refusing broad repair.",
    );
  }

  fs.writeFileSync(
    file,
    text,
  );

  console.log(
    "Removed duplicate goLiveAudit state declaration.",
  );
}

const count =
  (
    text.match(
      /goLiveAudit,\s*\n\s*setGoLiveAudit,/g,
    ) ??
    []
  ).length;

if (
  count !== 1
) {
  throw new Error(
    `Expected exactly one goLiveAudit state declaration after repair, found ${count}.`,
  );
}
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 21.8 duplicate audit state repair"
echo "============================================================"
echo
echo "Fixed:"
echo "  - removes second goLiveAudit/useState declaration"
echo "  - keeps existing audit API/UI logic intact"
echo "  - no runtime behavior changed"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
