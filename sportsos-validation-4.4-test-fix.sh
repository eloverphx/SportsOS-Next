#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

TEST="apps/api/test/simulation-provisioner.test.ts"

if [[ ! -f "$TEST" ]]; then
  echo "Missing expected test file: $TEST" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/4.4-test-fix-${STAMP}"
mkdir -p "$BACKUP_DIR/$(dirname "$TEST")"
cp "$TEST" "$BACKUP_DIR/$TEST"

node <<'NODE'
const fs = require("fs");
const path = "apps/api/test/simulation-provisioner.test.ts";
let text = fs.readFileSync(path, "utf8");

const oldBlock = `    poolExecute
      .mockResolvedValueOnce([
        [
          { simulated_game_id: 1, game_id: 1001, organization_id: 9 },
          { simulated_game_id: 2, game_id: 1002, organization_id: 9 },
        ],
      ])
      .mockResolvedValueOnce({ affectedRows: 1 })
      .mockResolvedValueOnce({ affectedRows: 1 })
      .mockResolvedValueOnce({ affectedRows: 1 });`;

const newBlock = `    poolExecute
      .mockResolvedValueOnce([
        [
          { simulated_game_id: 1, game_id: 1001, organization_id: 9 },
          { simulated_game_id: 2, game_id: 1002, organization_id: 9 },
        ],
      ])
      .mockResolvedValueOnce([{ affectedRows: 1 }, []])
      .mockResolvedValueOnce([{ affectedRows: 1 }, []])
      .mockResolvedValueOnce([{ affectedRows: 1 }, []]);`;

if (text.includes(newBlock)) {
  console.log("4.4 cleanup mock fix already applied.");
} else if (text.includes(oldBlock)) {
  text = text.replace(oldBlock, newBlock);
  fs.writeFileSync(path, text);
  console.log("Fixed mysql2 execute() tuple mocks in cleanup test.");
} else {
  throw new Error(
    "Expected cleanup mock block was not found. The test file may have changed.",
  );
}
NODE

echo
echo "============================================="
echo " SportsOS Validation 4.4 - Test Fixture Fix"
echo "============================================="
echo
echo "Modified:"
echo "  $TEST"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Reason:"
echo "  mysql2/promise execute() returns [result, fields]"
echo "  cleanup test incorrectly mocked a bare ResultSetHeader"
echo
echo "Run:"
echo "  npm run test:simulation-provisioner"
echo "  npm test"
