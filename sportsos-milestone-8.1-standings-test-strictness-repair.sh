#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="8.1-standings-test-strictness-repair"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/${MILESTONE}-${STAMP}"

cd "$ROOT"

TEST="apps/dashboard/test/tournament-standings-8.1.test.ts"

[[ -f "$TEST" ]] || {
  echo "ERROR: required test file missing: $TEST" >&2
  exit 1
}

mkdir -p "$BACKUP_DIR/$(dirname "$TEST")"
cp -a "$TEST" "$BACKUP_DIR/$TEST"

node <<'NODE'
const fs = require("fs");

const file = "apps/dashboard/test/tournament-standings-8.1.test.ts";
let text = fs.readFileSync(file, "utf8");

const oldBlock = `    expect(standings.map((row) => row.rank)).toEqual([1, 2, 3]);
    expect(standings[0].points).toBeGreaterThanOrEqual(
      standings[1].points,
    );`;

const newBlock = `    expect(standings.map((row) => row.rank)).toEqual([1, 2, 3]);

    const first = standings[0];
    const second = standings[1];

    expect(first).toBeDefined();
    expect(second).toBeDefined();

    if (!first || !second) {
      throw new Error("Expected at least two standings rows.");
    }

    expect(first.points).toBeGreaterThanOrEqual(second.points);`;

if (!text.includes(oldBlock)) {
  throw new Error("Expected strict-indexing test block not found.");
}

text = text.replace(oldBlock, newBlock);

fs.writeFileSync(file, text);
NODE

echo
echo "Milestone 8.1 strict TypeScript test repair complete."
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
