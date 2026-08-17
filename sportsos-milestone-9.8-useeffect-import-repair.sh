#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="9.8-useeffect-import-repair"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  exit 1
fi

cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentBroadcastOperatorPanel.tsx"
TEST="apps/dashboard/test/tournament-broadcast-useeffect-import-9.8-repair.test.ts"

[[ -f "$PANEL" ]] || {
  echo "ERROR: required component missing: $PANEL" >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$PANEL")" \
  "$BACKUP_DIR/$(dirname "$TEST")"

cp -a "$PANEL" "$BACKUP_DIR/$PANEL"
[[ -f "$TEST" ]] && cp -a "$TEST" "$BACKUP_DIR/$TEST"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/components/tournament/TournamentBroadcastOperatorPanel.tsx";

let text = fs.readFileSync(file, "utf8");

const importRegex =
  /import\s+\{([^}]*)\}\s+from\s+"react";/;

const match = text.match(importRegex);

if (!match) {
  throw new Error("Could not locate React named import.");
}

const names = match[1]
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);

for (const required of ["useEffect", "useMemo", "useState"]) {
  if (!names.includes(required)) {
    names.push(required);
  }
}

const replacement =
  `import { ${names.join(", ")} } from "react";`;

text = text.replace(importRegex, replacement);

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 9.8 useEffect import repair", () => {
  it("imports every React hook used by the broadcast operator panel", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentBroadcastOperatorPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toMatch(
      /import\s+\{[^}]*useEffect[^}]*\}\s+from\s+"react";/,
    );

    expect(component).toContain("useEffect(() =>");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 9.8 import repair installed"
echo "============================================================"
echo
echo "Fixed:"
echo "  - added useEffect to the React import"
echo "  - added regression test"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
