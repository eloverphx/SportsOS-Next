#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
HISTORY_DIR="${SPORTSOS_OPERATIONS_HISTORY_DIR:-${ROOT}/data/operations-history}"
RELIABILITY_DIR="${SPORTSOS_OPERATIONS_RELIABILITY_DIR:-${ROOT}/data/operations-reliability}"
OUTPUT_DIR="${SPORTSOS_OPERATIONS_METRICS_DIR:-${ROOT}/data/operations-metrics}"

WINDOW_HOURS="${SPORTSOS_OPERATIONS_METRICS_WINDOW_HOURS:-24}"
WARNING_FAILURE_RATE="${SPORTSOS_OPERATIONS_WARNING_FAILURE_RATE:-5}"
CRITICAL_FAILURE_RATE="${SPORTSOS_OPERATIONS_CRITICAL_FAILURE_RATE:-20}"
WARNING_STREAK="${SPORTSOS_OPERATIONS_WARNING_STREAK:-1}"
CRITICAL_STREAK="${SPORTSOS_OPERATIONS_CRITICAL_STREAK:-3}"

mkdir -p "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR" 2>/dev/null || true

node - \
  "$HISTORY_DIR" \
  "$RELIABILITY_DIR" \
  "$OUTPUT_DIR" \
  "$WINDOW_HOURS" \
  "$WARNING_FAILURE_RATE" \
  "$CRITICAL_FAILURE_RATE" \
  "$WARNING_STREAK" \
  "$CRITICAL_STREAK" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const [
  historyDir,
  reliabilityDir,
  outputDir,
  windowHoursRaw,
  warningFailureRateRaw,
  criticalFailureRateRaw,
  warningStreakRaw,
  criticalStreakRaw,
] = process.argv.slice(2);

const windowHours = Number(windowHoursRaw);
const warningFailureRate = Number(warningFailureRateRaw);
const criticalFailureRate = Number(criticalFailureRateRaw);
const warningStreak = Number(warningStreakRaw);
const criticalStreak = Number(criticalStreakRaw);

for (const [name, value] of Object.entries({
  windowHours,
  warningFailureRate,
  criticalFailureRate,
  warningStreak,
  criticalStreak,
})) {
  if (!Number.isFinite(value) || value < 0) {
    console.error(`ERROR: invalid numeric setting ${name}=${value}`);
    process.exit(2);
  }
}

const now = Date.now();
const cutoff = now - windowHours * 60 * 60 * 1000;

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

function listJson(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter((name) => name.endsWith(".json"))
    .map((name) => path.join(dir, name));
}

const history = listJson(historyDir)
  .map(readJson)
  .filter(Boolean)
  .filter((entry) => {
    const ts = Date.parse(entry.finishedAt ?? "");
    return Number.isFinite(ts) && ts >= cutoff;
  });

const reliabilityFiles = listJson(reliabilityDir)
  .map((file) => ({ file, stat: fs.statSync(file) }))
  .sort((a, b) => b.stat.mtimeMs - a.stat.mtimeMs);

const reliability =
  reliabilityFiles.length > 0
    ? readJson(reliabilityFiles[0].file)
    : null;

const totalRuns = history.length;
const failedRuns = history.filter(
  (entry) =>
    entry.status === "failed" ||
    Number(entry.exitCode ?? 0) !== 0,
).length;
const passedRuns = totalRuns - failedRuns;
const failureRatePercent =
  totalRuns === 0
    ? 0
    : Number(((failedRuns / totalRuns) * 100).toFixed(2));

const byMode = new Map();

for (const entry of history) {
  const mode = String(entry.mode ?? "unknown");

  if (!byMode.has(mode)) {
    byMode.set(mode, {
      mode,
      total: 0,
      passed: 0,
      failed: 0,
      latestStatus: "unknown",
      latestFinishedAt: null,
      currentFailureStreak: 0,
      failureRatePercent: 0,
    });
  }

  const metric = byMode.get(mode);
  metric.total += 1;

  const failed =
    entry.status === "failed" ||
    Number(entry.exitCode ?? 0) !== 0;

  if (failed) metric.failed += 1;
  else metric.passed += 1;
}

for (const metric of byMode.values()) {
  const entries = history
    .filter((entry) => String(entry.mode ?? "unknown") === metric.mode)
    .sort(
      (a, b) =>
        Date.parse(b.finishedAt ?? "") -
        Date.parse(a.finishedAt ?? ""),
    );

  if (entries.length > 0) {
    metric.latestStatus = entries[0].status ?? "unknown";
    metric.latestFinishedAt = entries[0].finishedAt ?? null;
  }

  for (const entry of entries) {
    const failed =
      entry.status === "failed" ||
      Number(entry.exitCode ?? 0) !== 0;

    if (!failed) break;
    metric.currentFailureStreak += 1;
  }

  metric.failureRatePercent =
    metric.total === 0
      ? 0
      : Number(((metric.failed / metric.total) * 100).toFixed(2));
}

const modes = [...byMode.values()].sort((a, b) =>
  a.mode.localeCompare(b.mode),
);

const maxFailureStreak =
  modes.reduce(
    (max, metric) => Math.max(max, metric.currentFailureStreak),
    0,
  );

const reasons = [];
let severity = "healthy";

function escalate(level, reason) {
  const rank = {
    healthy: 0,
    warning: 1,
    critical: 2,
  };

  if (rank[level] > rank[severity]) {
    severity = level;
  }

  reasons.push({ severity: level, reason });
}

if (totalRuns === 0) {
  escalate(
    "warning",
    `No operation history exists in the last ${windowHours} hours.`,
  );
}

if (failureRatePercent >= criticalFailureRate) {
  escalate(
    "critical",
    `Failure rate ${failureRatePercent}% exceeds critical threshold ${criticalFailureRate}%.`,
  );
} else if (failureRatePercent >= warningFailureRate) {
  escalate(
    "warning",
    `Failure rate ${failureRatePercent}% exceeds warning threshold ${warningFailureRate}%.`,
  );
}

if (maxFailureStreak >= criticalStreak) {
  escalate(
    "critical",
    `Failure streak ${maxFailureStreak} meets critical threshold ${criticalStreak}.`,
  );
} else if (maxFailureStreak >= warningStreak) {
  escalate(
    "warning",
    `Failure streak ${maxFailureStreak} meets warning threshold ${warningStreak}.`,
  );
}

const reliabilityStatus =
  reliability?.overallStatus ??
  reliability?.status ??
  null;

if (
  reliabilityStatus === "attention" ||
  reliabilityStatus === "critical"
) {
  escalate(
    reliabilityStatus === "critical" ? "critical" : "warning",
    `Reliability scorecard reports ${reliabilityStatus}.`,
  );
}

const generatedAt = new Date().toISOString();

const payload = {
  schemaVersion: 1,
  generatedAt,
  windowHours,
  severity,
  thresholds: {
    warningFailureRatePercent: warningFailureRate,
    criticalFailureRatePercent: criticalFailureRate,
    warningFailureStreak: warningStreak,
    criticalFailureStreak: criticalStreak,
  },
  summary: {
    totalRuns,
    passedRuns,
    failedRuns,
    failureRatePercent,
    maxFailureStreak,
  },
  reasons,
  modes,
};

const stamp = generatedAt
  .replace(/[-:]/g, "")
  .replace(/\.\d{3}Z$/, "Z");

const timestamped =
  path.join(outputDir, `operations-metrics-${stamp}.json`);
const latest = path.join(outputDir, "latest.json");
const text = JSON.stringify(payload, null, 2) + "\n";

fs.writeFileSync(timestamped, text, { mode: 0o600 });
fs.writeFileSync(latest, text, { mode: 0o600 });

try {
  fs.chmodSync(timestamped, 0o600);
  fs.chmodSync(latest, 0o600);
} catch {}

console.log(`Operations severity: ${severity}`);
console.log(`Runs: ${totalRuns} total, ${passedRuns} passed, ${failedRuns} failed`);
console.log(`Failure rate: ${failureRatePercent}%`);
console.log(`Max failure streak: ${maxFailureStreak}`);
console.log(`Metrics: ${latest}`);

process.exit(
  severity === "critical"
    ? 3
    : severity === "warning"
      ? 2
      : 0,
);
NODE
