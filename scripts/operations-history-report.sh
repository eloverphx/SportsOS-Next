#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
HISTORY_DIR="${SPORTSOS_OPERATIONS_HISTORY_DIR:-${ROOT}/data/operations-history}"
DAYS="${SPORTSOS_OPERATIONS_HISTORY_DAYS:-7}"

cd "$ROOT"

if ! [[ "$DAYS" =~ ^[0-9]+$ ]] || [[ "$DAYS" -lt 1 ]]; then
  echo "ERROR: SPORTSOS_OPERATIONS_HISTORY_DAYS must be >= 1." >&2
  exit 1
fi

mkdir -p "$HISTORY_DIR"

node - "$HISTORY_DIR" "$DAYS" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const [historyDir, daysArg] = process.argv.slice(2);
const days = Number(daysArg);
const cutoff = Date.now() - (days * 24 * 60 * 60 * 1000);
const records = [];

for (const name of fs.readdirSync(historyDir)) {
  if (!name.endsWith(".json")) continue;
  const fullPath = path.join(historyDir, name);

  try {
    const stat = fs.statSync(fullPath);
    if (stat.mtimeMs < cutoff) continue;

    const parsed = JSON.parse(
      fs.readFileSync(fullPath, "utf8"),
    );

    records.push({
      ...parsed,
      file: fullPath,
      mtimeMs: stat.mtimeMs,
    });
  } catch {
    // Raw operation log remains available if a history record is malformed.
  }
}

records.sort((a, b) => b.mtimeMs - a.mtimeMs);

const grouped = new Map();

for (const record of records) {
  const current =
    grouped.get(record.mode) ??
    { total: 0, passed: 0, failed: 0, latest: null };

  current.total += 1;

  if (record.status === "passed") {
    current.passed += 1;
  } else {
    current.failed += 1;
  }

  if (!current.latest) {
    current.latest = record;
  }

  grouped.set(record.mode, current);
}

console.log("============================================================");
console.log(" SportsOS Operations History");
console.log("============================================================");
console.log(`Window: last ${days} day(s)`);
console.log(`Records: ${records.length}`);
console.log("");

if (records.length === 0) {
  console.log("No operation history records found in the selected window.");
  process.exit(0);
}

for (const mode of [...grouped.keys()].sort()) {
  const item = grouped.get(mode);
  console.log(
    `${mode.padEnd(20)} total=${String(item.total).padStart(3)} ` +
    `pass=${String(item.passed).padStart(3)} ` +
    `fail=${String(item.failed).padStart(3)} ` +
    `latest=${item.latest.status}`,
  );
}

const failures = records.filter((record) => record.status !== "passed");

console.log("");
console.log(`Failures in window: ${failures.length}`);

for (const failure of failures.slice(0, 20)) {
  console.log(
    `  ${failure.finishedAt ?? failure.stamp} ` +
    `${failure.mode} exit=${failure.exitCode} ` +
    `${failure.runLog}`,
  );
}

if (failures.length > 20) {
  console.log(`  ... ${failures.length - 20} more`);
}
NODE
