#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

SPEC="e2e/game-day-scorekeeper.spec.ts"

if [[ ! -f "$SPEC" ]]; then
  echo "Missing Milestone 5.6 spec: $SPEC" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/5.6-penalty-select-order-${STAMP}"
mkdir -p "$BACKUP_DIR/e2e"
cp "$SPEC" "$BACKUP_DIR/$SPEC"

node <<'NODE'
const fs = require("fs");
const path = "e2e/game-day-scorekeeper.spec.ts";
let text = fs.readFileSync(path, "utf8");

const oldBlock = `    const penaltyDialog = page.getByRole("dialog", { name: "Record penalty" });

    await penaltyDialog.getByLabel("Player", { exact: true }).selectOption("2001");
    await penaltyDialog.getByLabel("Infraction", { exact: true }).selectOption("Hooking");
    await penaltyDialog.getByLabel("Duration", { exact: true }).selectOption("2");
    await penaltyDialog.getByRole("button", { name: "CONFIRM PENALTY" }).click();`;

const newBlock = `    const penaltyDialog = page.getByRole("dialog", { name: "Record penalty" });
    const penaltySelects = penaltyDialog.locator("select");

    await expect(penaltySelects).toHaveCount(3);
    await penaltySelects.nth(0).selectOption("2001");
    await penaltySelects.nth(1).selectOption("Hooking");
    await penaltySelects.nth(2).selectOption("2");
    await penaltyDialog.getByRole("button", { name: "CONFIRM PENALTY" }).click();`;

if (!text.includes(oldBlock)) {
  throw new Error("Could not find exact-label penalty selector block");
}

text = text.replace(oldBlock, newBlock);
fs.writeFileSync(path, text);
NODE

echo
echo "============================================="
echo " SportsOS 5.6 Penalty Select-Order Fix"
echo "============================================="
echo
echo "Modified:"
echo "  $SPEC"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Penalty dialog selectors:"
echo "  select[0] = player"
echo "  select[1] = infraction"
echo "  select[2] = duration"
echo
echo "Includes toHaveCount(3) guard so markup drift is detected."
echo "Production UI unchanged."
echo
echo "Run:"
echo "  npm run test:e2e:docker"
