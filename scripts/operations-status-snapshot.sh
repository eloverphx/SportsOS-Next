#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
HISTORY_DIR="${SPORTSOS_OPERATIONS_HISTORY_DIR:-${ROOT}/data/operations-history}"
RELIABILITY_DIR="${SPORTSOS_OPERATIONS_RELIABILITY_DIR:-${ROOT}/data/operations-reliability}"
METRICS_FILE="${SPORTSOS_OPERATIONS_METRICS_FILE:-${ROOT}/data/operations-metrics/latest.json}"
OUTPUT_DIR="${SPORTSOS_OPERATIONS_STATUS_DIR:-${ROOT}/data/operations-status}"
WINDOW_HOURS="${SPORTSOS_OPERATIONS_STATUS_WINDOW_HOURS:-24}"

mkdir -p "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR" 2>/dev/null || true

node - "$HISTORY_DIR" "$RELIABILITY_DIR" "$METRICS_FILE" "$OUTPUT_DIR" "$WINDOW_HOURS" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const [historyDir, reliabilityDir, metricsFile, outputDir, windowHoursRaw] = process.argv.slice(2);
const windowHours = Number(windowHoursRaw);
if (!Number.isFinite(windowHours) || windowHours <= 0) {
  console.error(`ERROR: invalid window hours: ${windowHoursRaw}`);
  process.exit(2);
}
function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, "utf8")); } catch { return null; }
}
function listJson(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter((name) => name.endsWith(".json")).map((name) => path.join(dir, name));
}
function latestJson(dir) {
  const files = listJson(dir).map((file) => ({ file, stat: fs.statSync(file) })).sort((a,b) => b.stat.mtimeMs - a.stat.mtimeMs);
  return files.length ? readJson(files[0].file) : null;
}
const cutoff = Date.now() - windowHours * 60 * 60 * 1000;
const history = listJson(historyDir).map(readJson).filter(Boolean).filter((entry) => {
  const ts = Date.parse(entry.finishedAt ?? "");
  return Number.isFinite(ts) && ts >= cutoff;
});
function newestForMode(mode) {
  const entries = history.filter((entry) => entry.mode === mode).sort((a,b) => Date.parse(b.finishedAt ?? "") - Date.parse(a.finishedAt ?? ""));
  if (!entries.length) return null;
  const entry = entries[0];
  return { mode: String(entry.mode ?? mode), status: String(entry.status ?? "unknown"), exitCode: Number(entry.exitCode ?? 0), finishedAt: entry.finishedAt ?? null };
}
function newestForModes(modes) {
  const entries = history.filter((entry) => modes.includes(entry.mode)).sort((a,b) => Date.parse(b.finishedAt ?? "") - Date.parse(a.finishedAt ?? ""));
  if (!entries.length) return null;
  const entry = entries[0];
  return { mode: String(entry.mode ?? "unknown"), status: String(entry.status ?? "unknown"), exitCode: Number(entry.exitCode ?? 0), finishedAt: entry.finishedAt ?? null };
}

const reliability = latestJson(reliabilityDir);
const metrics = readJson(metricsFile);
const totalRuns = history.length;
const failedRuns = history.filter((entry) => entry.status === "failed" || Number(entry.exitCode ?? 0) !== 0).length;
const passedRuns = totalRuns - failedRuns;

const sanitizedIssues = Array.isArray(reliability?.issues)
  ? reliability.issues.map((issue) => ({
      type: String(issue?.type ?? "unknown"),
      mode: String(issue?.mode ?? "unknown"),
      message: String(issue?.message ?? "Reliability issue detected."),
    }))
  : [];

const sanitizedReasons = Array.isArray(metrics?.reasons)
  ? metrics.reasons.map((reason) => ({
      severity: String(reason?.severity ?? "warning"),
      reason: String(reason?.reason ?? "Operations condition detected."),
    }))
  : [];

const sanitizedModes = Array.isArray(metrics?.modes)
  ? metrics.modes.map((mode) => ({
      mode: String(mode?.mode ?? "unknown"),
      total: Number(mode?.total ?? 0),
      passed: Number(mode?.passed ?? 0),
      failed: Number(mode?.failed ?? 0),
      failureRatePercent: Number(mode?.failureRatePercent ?? 0),
      currentFailureStreak: Number(mode?.currentFailureStreak ?? 0),
      latestStatus: String(mode?.latestStatus ?? "unknown"),
      latestFinishedAt: mode?.latestFinishedAt ?? null,
    }))
  : [];

const payload = {
  schemaVersion: 2,
  generatedAt: new Date().toISOString(),
  windowHours,
  overallStatus: String(metrics?.severity ?? reliability?.overallStatus ?? "unknown"),
  severity: {
    status: String(metrics?.severity ?? "unknown"),
    reasons: sanitizedReasons,
    summary: {
      totalRuns: Number(metrics?.summary?.totalRuns ?? totalRuns),
      passedRuns: Number(metrics?.summary?.passedRuns ?? passedRuns),
      failedRuns: Number(metrics?.summary?.failedRuns ?? failedRuns),
      failureRatePercent: Number(metrics?.summary?.failureRatePercent ?? 0),
      maxFailureStreak: Number(metrics?.summary?.maxFailureStreak ?? 0),
    },
    modes: sanitizedModes,
  },
  reliability: reliability ? {
    generatedAt: reliability.generatedAt ?? null,
    overallStatus: String(reliability.overallStatus ?? reliability.status ?? "unknown"),
    issueCount: sanitizedIssues.length,
    issues: sanitizedIssues,
  } : null,
  latest: {
    health: newestForMode("health"),
    backup: newestForMode("mysql-backup"),
    persistentBackup: newestForMode("persistent-backup"),
    recovery: newestForMode("recovery"),
    restoreRehearsal: newestForModes(["restore-rehearsal", "weekly"]),
    reliabilityAlert: newestForMode("reliability-alert"),
  },
  recent: { totalRuns, failedRuns, passedRuns },
};

const stamp = payload.generatedAt.replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
const timestamped = path.join(outputDir, `operations-status-${stamp}.json`);
const latest = path.join(outputDir, "latest.json");
const text = JSON.stringify(payload, null, 2) + "\n";
fs.writeFileSync(timestamped, text, { mode: 0o600 });
fs.writeFileSync(latest, text, { mode: 0o600 });
try { fs.chmodSync(timestamped, 0o600); fs.chmodSync(latest, 0o600); } catch {}
console.log(`Operations status: ${payload.overallStatus}`);
console.log(`Recent runs: ${totalRuns} total, ${passedRuns} passed, ${failedRuns} failed`);
console.log(`Snapshot: ${latest}`);
NODE
