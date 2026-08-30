#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
HISTORY_DIR="${SPORTSOS_OPERATIONS_HISTORY_DIR:-${ROOT}/data/operations-history}"
WINDOW_DAYS="${SPORTSOS_RELIABILITY_WINDOW_DAYS:-7}"
MIN_SUCCESS_PERCENT="${SPORTSOS_RELIABILITY_MIN_SUCCESS_PERCENT:-95}"
MAX_FAILURE_STREAK="${SPORTSOS_RELIABILITY_MAX_FAILURE_STREAK:-2}"
STALE_HEALTH_MINUTES="${SPORTSOS_RELIABILITY_STALE_HEALTH_MINUTES:-15}"
STALE_BACKUP_HOURS="${SPORTSOS_RELIABILITY_STALE_BACKUP_HOURS:-36}"
OUTPUT_DIR="${SPORTSOS_RELIABILITY_OUTPUT_DIR:-${ROOT}/data/operations-reliability}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_FILE="${OUTPUT_DIR}/reliability-${STAMP}.json"

cd "$ROOT"

for value_name in \
  WINDOW_DAYS \
  MIN_SUCCESS_PERCENT \
  MAX_FAILURE_STREAK \
  STALE_HEALTH_MINUTES \
  STALE_BACKUP_HOURS
do
  value="${!value_name}"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "ERROR: $value_name must be a non-negative integer." >&2
    exit 1
  fi
done

if [[ "$WINDOW_DAYS" -lt 1 ]]; then
  echo "ERROR: SPORTSOS_RELIABILITY_WINDOW_DAYS must be >= 1." >&2
  exit 1
fi
if [[ "$MIN_SUCCESS_PERCENT" -gt 100 ]]; then
  echo "ERROR: SPORTSOS_RELIABILITY_MIN_SUCCESS_PERCENT must be <= 100." >&2
  exit 1
fi

mkdir -p "$HISTORY_DIR" "$OUTPUT_DIR"
chmod 700 "$HISTORY_DIR" "$OUTPUT_DIR"
umask 077

set +e
node - \
  "$HISTORY_DIR" \
  "$WINDOW_DAYS" \
  "$MIN_SUCCESS_PERCENT" \
  "$MAX_FAILURE_STREAK" \
  "$STALE_HEALTH_MINUTES" \
  "$STALE_BACKUP_HOURS" \
  "$OUTPUT_FILE" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const [
  historyDir,
  windowDaysArg,
  minSuccessArg,
  maxFailureStreakArg,
  staleHealthMinutesArg,
  staleBackupHoursArg,
  outputFile,
] = process.argv.slice(2);

const windowDays = Number(windowDaysArg);
const minSuccessPercent = Number(minSuccessArg);
const maxFailureStreak = Number(maxFailureStreakArg);
const staleHealthMinutes = Number(staleHealthMinutesArg);
const staleBackupHours = Number(staleBackupHoursArg);

const now = Date.now();
const cutoff = now - (windowDays * 24 * 60 * 60 * 1000);
const allRecords = [];

for (const name of fs.readdirSync(historyDir)) {
  if (!name.endsWith(".json")) continue;

  const fullPath = path.join(historyDir, name);

  try {
    const stat = fs.statSync(fullPath);
    const parsed = JSON.parse(fs.readFileSync(fullPath, "utf8"));
    const finishedMs = Date.parse(parsed.finishedAt || "") || stat.mtimeMs;

    allRecords.push({
      ...parsed,
      sourceFile: fullPath,
      finishedMs,
    });
  } catch {
    // Ignore malformed history record; the original raw log is retained.
  }
}

allRecords.sort((a, b) => b.finishedMs - a.finishedMs);
const windowRecords = allRecords.filter((record) => record.finishedMs >= cutoff);
const modes = new Map();

for (const record of windowRecords) {
  const current = modes.get(record.mode) ?? {
    total: 0,
    passed: 0,
    failed: 0,
    latestStatus: null,
    latestAt: null,
    currentFailureStreak: 0,
    successPercent: 0,
  };

  current.total += 1;

  if (record.status === "passed") current.passed += 1;
  else current.failed += 1;

  if (current.latestStatus === null) {
    current.latestStatus = record.status;
    current.latestAt = record.finishedAt || null;
  }

  modes.set(record.mode, current);
}

for (const [mode, current] of modes) {
  current.successPercent =
    current.total > 0
      ? Number(((current.passed / current.total) * 100).toFixed(2))
      : 0;

  const recordsForMode = allRecords.filter((record) => record.mode === mode);
  let streak = 0;

  for (const record of recordsForMode) {
    if (record.status === "passed") break;
    streak += 1;
  }

  current.currentFailureStreak = streak;
}

const issues = [];

for (const [mode, current] of modes) {
  if (current.successPercent < minSuccessPercent) {
    issues.push({
      type: "success-rate",
      mode,
      message:
        `${mode} success rate ${current.successPercent}% is below ${minSuccessPercent}%`,
    });
  }

  if (current.currentFailureStreak > maxFailureStreak) {
    issues.push({
      type: "failure-streak",
      mode,
      message:
        `${mode} has ${current.currentFailureStreak} consecutive failures`,
    });
  }
}

function latestForModes(modeNames) {
  return allRecords.find((record) => modeNames.includes(record.mode));
}

const latestHealth = latestForModes(["health", "alert", "daily"]);

if (!latestHealth) {
  issues.push({
    type: "missing-health",
    mode: "health",
    message: "No health-related operation history exists.",
  });
} else {
  const ageMinutes = (now - latestHealth.finishedMs) / 60000;

  if (ageMinutes > staleHealthMinutes) {
    issues.push({
      type: "stale-health",
      mode: latestHealth.mode,
      message:
        `Latest health-related run is ${ageMinutes.toFixed(1)} minutes old ` +
        `(limit ${staleHealthMinutes} minutes)`,
    });
  }
}

const latestBackup = latestForModes(["backup-all", "daily", "mysql-backup"]);

if (!latestBackup) {
  issues.push({
    type: "missing-backup",
    mode: "backup",
    message: "No backup-related operation history exists.",
  });
} else {
  const ageHours = (now - latestBackup.finishedMs) / 3600000;

  if (ageHours > staleBackupHours) {
    issues.push({
      type: "stale-backup",
      mode: latestBackup.mode,
      message:
        `Latest backup-related run is ${ageHours.toFixed(1)} hours old ` +
        `(limit ${staleBackupHours} hours)`,
    });
  }
}

const modeSummary =
  Object.fromEntries(
    [...modes.entries()].sort(([a], [b]) => a.localeCompare(b)),
  );

const result = {
  schemaVersion: 1,
  generatedAt: new Date(now).toISOString(),
  windowDays,
  thresholds: {
    minSuccessPercent,
    maxFailureStreak,
    staleHealthMinutes,
    staleBackupHours,
  },
  overallStatus: issues.length === 0 ? "healthy" : "attention",
  recordCount: windowRecords.length,
  modes: modeSummary,
  issues,
};

fs.writeFileSync(
  outputFile,
  `${JSON.stringify(result, null, 2)}\n`,
  { mode: 0o600 },
);

console.log("============================================================");
console.log(" SportsOS Production Reliability Scorecard");
console.log("============================================================");
console.log(`Window: ${windowDays} day(s)`);
console.log(`Records: ${windowRecords.length}`);
console.log("");

if (modes.size === 0) {
  console.log("No operation records are available in the selected window.");
} else {
  for (const [mode, current] of [...modes.entries()].sort()) {
    console.log(
      `${mode.padEnd(20)} ` +
      `success=${current.successPercent.toFixed(2).padStart(6)}% ` +
      `runs=${String(current.total).padStart(3)} ` +
      `failures=${String(current.failed).padStart(3)} ` +
      `streak=${current.currentFailureStreak}`,
    );
  }
}

console.log("");
console.log(`Overall: ${result.overallStatus.toUpperCase()}`);
console.log(`Issues: ${issues.length}`);

for (const issue of issues) {
  console.log(`  - ${issue.message}`);
}

console.log("");
console.log(`JSON: ${outputFile}`);

process.exit(issues.length === 0 ? 0 : 3);
NODE

rc=$?
set -e
chmod 600 "$OUTPUT_FILE"
exit "$rc"
