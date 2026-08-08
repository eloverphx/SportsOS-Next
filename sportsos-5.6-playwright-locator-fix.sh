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
BACKUP_DIR=".game-engine-backups/5.6-locator-fix-${STAMP}"
mkdir -p "$BACKUP_DIR/e2e"
cp "$SPEC" "$BACKUP_DIR/$SPEC"

node <<'NODE'
const fs = require("fs");
const path = "e2e/game-day-scorekeeper.spec.ts";
let text = fs.readFileSync(path, "utf8");

const oldHome = `    await page
      .locator("section")
      .filter({ hasText: "HOME" })
      .getByRole("button", { name: "GOAL", exact: true })
      .click();`;

const newHome = `    await page
      .getByText("Prior Lake Lakers", { exact: true })
      .locator("xpath=ancestor::*[self::section or self::article or self::div][.//button[normalize-space()='GOAL']][1]")
      .getByRole("button", { name: "GOAL", exact: true })
      .click();`;

const oldAway = `    await page
      .locator("section")
      .filter({ hasText: "AWAY" })
      .getByRole("button", { name: "2:00 PENALTY", exact: true })
      .click();`;

const newAway = `    await page
      .getByText("Edina Hornets", { exact: true })
      .locator("xpath=ancestor::*[self::section or self::article or self::div][.//button[normalize-space()='2:00 PENALTY']][1]")
      .getByRole("button", { name: "2:00 PENALTY", exact: true })
      .click();`;

if (!text.includes(oldHome)) {
  throw new Error("Could not find original home GOAL locator");
}
if (!text.includes(oldAway)) {
  throw new Error("Could not find original away PENALTY locator");
}

text = text.replace(oldHome, newHome);
text = text.replace(oldAway, newAway);

fs.writeFileSync(path, text);
NODE

echo
echo "============================================="
echo " SportsOS 5.6 Playwright Locator Fix"
echo "============================================="
echo
echo "Modified:"
echo "  $SPEC"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Changed only E2E selectors:"
echo "  HOME GOAL -> team-name scoped"
echo "  AWAY PENALTY -> team-name scoped"
echo
echo "Production UI unchanged."
echo
echo "Run:"
echo "  npm run test:e2e:docker"
