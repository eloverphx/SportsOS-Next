#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

CSS="apps/dashboard/app/games/[id]/control/scorekeeper.module.css"

if [[ ! -f "$CSS" ]]; then
  echo "Missing expected CSS module: $CSS" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/5.1-css-fix-${STAMP}"
mkdir -p "$BACKUP_DIR/$(dirname "$CSS")"
cp "$CSS" "$BACKUP_DIR/$CSS"

node <<'NODE'
const fs = require("fs");
const path = "apps/dashboard/app/games/[id]/control/scorekeeper.module.css";
let text = fs.readFileSync(path, "utf8");

text = text.replace(
`button {
  min-height: 48px;
}`,
`.page button {
  min-height: 48px;
}`,
);

text = text.replace(
`button:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}`,
`.page button:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}`,
);

fs.writeFileSync(path, text);
NODE

echo
echo "============================================="
echo " SportsOS 5.1 - CSS Modules Build Fix"
echo "============================================="
echo
echo "Fixed:"
echo "  bare button selector -> .page button"
echo "  bare button:disabled -> .page button:disabled"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run build"
