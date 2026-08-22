#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  echo "Expected: $EXPECTED_REAL" >&2
  echo "Received: $ROOT_REAL" >&2
  exit 1
fi

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src"
do
  [[ -e "$required" ]] || {
    echo "ERROR: repository safety marker missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

echo "============================================================"
echo " SportsOS scoreboard assignment repository probe"
echo " READ ONLY - no files will be modified"
echo "============================================================"
echo

node <<'NODE'
const fs = require("fs");
const path = require("path");

const root = "apps/api/src";
const files = [];

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      walk(full);
    } else if (entry.isFile() && entry.name.endsWith(".ts")) {
      files.push(full);
    }
  }
}

walk(root);

const candidates = [];

for (const file of files) {
  const text = fs.readFileSync(file, "utf8");

  const score = [
    /assignment/i.test(text) ? 3 : 0,
    /deviceId/.test(text) ? 2 : 0,
    /gameId/.test(text) ? 2 : 0,
    /scoreboard/i.test(text) ? 2 : 0,
    /\/scoreboard[^"'`]*assignment/i.test(text) ? 5 : 0,
    /Map\s*</.test(text) ? 1 : 0,
  ].reduce((a, b) => a + b, 0);

  if (score < 4) {
    continue;
  }

  const routeStrings =
    [...text.matchAll(/["'`]([^"'`]*scoreboard[^"'`]*assignment[^"'`]*)["'`]/gi)]
      .map((m) => m[1]);

  const exports = [
    ...text.matchAll(/export\s+(?:async\s+)?function\s+([A-Za-z0-9_]+)/g),
    ...text.matchAll(/export\s+const\s+([A-Za-z0-9_]+)/g),
    ...text.matchAll(/export\s+class\s+([A-Za-z0-9_]+)/g),
  ].map((m) => m[1]);

  const maps =
    [...text.matchAll(/(?:const|let)\s+([A-Za-z0-9_]*(?:assignment|device|scoreboard)[A-Za-z0-9_]*)\s*=\s*new\s+Map/gi)]
      .map((m) => m[1]);

  const assignmentSymbols =
    [...new Set(
      [...text.matchAll(/\b([A-Za-z0-9_]*assignment[A-Za-z0-9_]*)\b/gi)]
        .map((m) => m[1])
        .filter((name) => name.length > 3)
    )].slice(0, 30);

  candidates.push({
    file,
    score,
    routeStrings,
    exports,
    maps,
    assignmentSymbols,
  });
}

candidates.sort((a, b) => b.score - a.score || a.file.localeCompare(b.file));

if (candidates.length === 0) {
  console.log("No assignment-related TypeScript candidates found.");
  process.exit(0);
}

for (const candidate of candidates.slice(0, 15)) {
  console.log("------------------------------------------------------------");
  console.log(`FILE: ${candidate.file}`);
  console.log(`SCORE: ${candidate.score}`);

  if (candidate.routeStrings.length) {
    console.log("ROUTES:");
    for (const route of [...new Set(candidate.routeStrings)]) {
      console.log(`  ${route}`);
    }
  }

  if (candidate.exports.length) {
    console.log("EXPORTS:");
    for (const name of [...new Set(candidate.exports)]) {
      console.log(`  ${name}`);
    }
  }

  if (candidate.maps.length) {
    console.log("MAP-LIKE REGISTRIES:");
    for (const name of [...new Set(candidate.maps)]) {
      console.log(`  ${name}`);
    }
  }

  if (candidate.assignmentSymbols.length) {
    console.log("ASSIGNMENT SYMBOLS:");
    for (const name of candidate.assignmentSymbols) {
      console.log(`  ${name}`);
    }
  }
}

console.log("------------------------------------------------------------");
console.log("Focused matching lines:");
console.log();

for (const candidate of candidates.slice(0, 8)) {
  const lines = fs.readFileSync(candidate.file, "utf8").split(/\r?\n/);

  const hits = [];

  lines.forEach((line, index) => {
    if (
      /assignment/i.test(line) ||
      (/deviceId/.test(line) && /gameId/.test(line))
    ) {
      hits.push({
        line: index + 1,
        text: line,
      });
    }
  });

  if (!hits.length) {
    continue;
  }

  console.log(`### ${candidate.file}`);

  for (const hit of hits.slice(0, 60)) {
    console.log(`${String(hit.line).padStart(5, " ")}: ${hit.text}`);
  }

  console.log();
}
NODE

echo
echo "============================================================"
echo " Probe complete"
echo " No repository files were modified."
echo "============================================================"
