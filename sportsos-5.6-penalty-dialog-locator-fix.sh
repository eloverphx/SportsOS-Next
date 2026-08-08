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
BACKUP_DIR=".game-engine-backups/5.6-penalty-dialog-locator-${STAMP}"
mkdir -p "$BACKUP_DIR/e2e"
cp "$SPEC" "$BACKUP_DIR/$SPEC"

node <<'NODE'
const fs = require("fs");
const path = "e2e/game-day-scorekeeper.spec.ts";
let text = fs.readFileSync(path, "utf8");

const oldBlock = `    await page.getByLabel("Player").selectOption("2001");
    await page.getByLabel("Infraction").selectOption("Hooking");
    await page.getByLabel("Duration").selectOption("2");
    await page.getByRole("button", { name: "CONFIRM PENALTY" }).click();`;

const newBlock = `    const penaltyDialog = page.getByRole("dialog", { name: "Record penalty" });

    await penaltyDialog.getByLabel("Player", { exact: true }).selectOption("2001");
    await penaltyDialog.getByLabel("Infraction", { exact: true }).selectOption("Hooking");
    await penaltyDialog.getByLabel("Duration", { exact: true }).selectOption("2");
    await penaltyDialog.getByRole("button", { name: "CONFIRM PENALTY" }).click();`;

if (!text.includes(oldBlock)) {
  throw new Error("Could not find original penalty form locator block");
}

text = text.replace(oldBlock, newBlock);
fs.writeFileSync(path, text);
NODE

echo
echo "============================================="
echo " SportsOS 5.6 Penalty Dialog Locator Fix"
echo "============================================="
echo
echo "Modified:"
echo "  $SPEC"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Selectors now scoped to:"
echo '  dialog "Record penalty"'
echo '  exact label "Player"'
echo '  exact label "Infraction"'
echo '  exact label "Duration"'
echo
echo "Production UI unchanged."
echo
echo "Run:"
echo "  npm run test:e2e:docker"
