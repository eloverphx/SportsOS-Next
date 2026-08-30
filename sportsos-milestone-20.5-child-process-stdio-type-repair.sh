#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-20.5-child-process-type-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

FILE="apps/api/src/services/encoderRuntime.ts"

[[ -f "$FILE" ]] || {
  echo "ERROR: missing $ROOT/$FILE" >&2
  exit 1
}

mkdir -p "$BACKUP/$(dirname "$FILE")"
cp -a "$FILE" "$BACKUP/$FILE"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/encoderRuntime.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

text =
  text.replace(
`import {
  spawn,
  type ChildProcessWithoutNullStreams,
} from "node:child_process";`,
`import {
  spawn,
  type ChildProcessByStdio,
} from "node:child_process";

import type {
  Readable,
} from "node:stream";`,
  );

text =
  text.replace(
`  process:
    ChildProcessWithoutNullStreams;`,
`  process:
    ChildProcessByStdio<
      null,
      Readable,
      Readable
    >;`,
  );

if (
  text.includes(
    "ChildProcessWithoutNullStreams",
  )
) {
  throw new Error(
    "Old child-process type still present.",
  );
}

if (
  !text.includes(
    "ChildProcessByStdio<"
  )
) {
  throw new Error(
    "Replacement child-process type missing.",
  );
}

fs.writeFileSync(
  file,
  text,
);

console.log(
  "20.5 child-process stdio typing repaired.",
);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 20.5 child-process type repair"
echo "============================================================"
echo
echo "Fixed:"
echo "  - matches spawn() result when stdin is ignored"
echo "  - stdout/stderr remain readable"
echo "  - FFmpeg runtime behavior unchanged"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
