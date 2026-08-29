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

# SPORTSOS_M30_2_2_STATUS_PERMISSION_NORMALIZATION
# Keep protected operations status readable by the non-root API runtime.
SPORTSOS_STATUS_RUNTIME_UID="${SPORTSOS_STATUS_RUNTIME_UID:-1000}"
SPORTSOS_STATUS_RUNTIME_GID="${SPORTSOS_STATUS_RUNTIME_GID:-1000}"
SPORTSOS_STATUS_PERMISSION_DIR="${SPORTSOS_STATUS_PERMISSION_DIR:-/mnt/user/appdata/SportsOS-Next/data/operations-status}"

if [[ -d "$SPORTSOS_STATUS_PERMISSION_DIR" ]]; then
  chown "$SPORTSOS_STATUS_RUNTIME_UID:$SPORTSOS_STATUS_RUNTIME_GID" "$SPORTSOS_STATUS_PERMISSION_DIR"
  chmod 750 "$SPORTSOS_STATUS_PERMISSION_DIR"

  while IFS= read -r -d '' status_file; do
    chown "$SPORTSOS_STATUS_RUNTIME_UID:$SPORTSOS_STATUS_RUNTIME_GID" "$status_file"
    chmod 640 "$status_file"
  done < <(find "$SPORTSOS_STATUS_PERMISSION_DIR" -maxdepth 1 -type f -name '*.json' -print0)
fi
# END SPORTSOS_M30_2_2_STATUS_PERMISSION_NORMALIZATION

# SPORTSOS_M33_2_RECOVERY_STATUS_SCHEMA
# Add bounded self-healing telemetry to the protected operations status snapshot.
RECOVERY_STATE_DIR="${SPORTSOS_RECOVERY_STATE_DIR:-${ROOT}/data/operations-recovery}"
RECOVERY_STATE_FILE="${RECOVERY_STATE_DIR}/restart-counts.env"
RECOVERY_ACTION_LOG="${RECOVERY_STATE_DIR}/recovery-actions.tsv"
OPERATIONS_STATUS_FILE="${ROOT}/data/operations-status/latest.json"

if [[ -f "$OPERATIONS_STATUS_FILE" ]]; then
# SPORTSOS_M33_5_SHARED_RECOVERY_POLICY_CONSUMER
source "${ROOT}/scripts/lib/recovery-policy.sh"
export SPORTSOS_RECOVERY_POLICY_JSON="$(sportsos_recovery_policy_json)"
export SPORTSOS_RECOVERY_POLICY_RESTART_DELTA_THRESHOLD="$RESTART_DELTA_THRESHOLD"
export SPORTSOS_RECOVERY_POLICY_COOLDOWN_SECONDS="$COOLDOWN_SECONDS"
export SPORTSOS_RECOVERY_POLICY_BUDGET_WINDOW_SECONDS="$BUDGET_WINDOW_SECONDS"
export SPORTSOS_RECOVERY_POLICY_MAX_ACTIONS_PER_WINDOW="$MAX_ACTIONS_PER_WINDOW"
export SPORTSOS_RECOVERY_POLICY_POST_TIMEOUT_SECONDS="$POST_RECOVERY_TIMEOUT_SECONDS"

  node - "$OPERATIONS_STATUS_FILE" "$RECOVERY_STATE_FILE" "$RECOVERY_ACTION_LOG" <<'NODE'
const fs = require("fs");

const [statusFile, stateFile, actionLog] = process.argv.slice(2);

const status = JSON.parse(fs.readFileSync(statusFile, "utf8"));

const policy = JSON.parse(
  process.env.SPORTSOS_RECOVERY_POLICY_JSON ?? "{}",
);

const containerToService = {
  sportsos_api: "api",
  sportsos_dashboard: "dashboard",
  sportsos_mysql: "mysql",
  sportsos_redis: "redis",
  sportsos_mqtt: "mqtt",
  sportsos_minio: "minio",
  sportsos_scoreboard_simulator: "scoreboard-simulator",
};

const restartCounts = {};
if (fs.existsSync(stateFile)) {
  for (const raw of fs.readFileSync(stateFile, "utf8").split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || !line.includes("=")) continue;
    const idx = line.indexOf("=");
    const container = line.slice(0, idx);
    const value = Number(line.slice(idx + 1));
    const service = containerToService[container] || container;
    restartCounts[service] = Number.isFinite(value) ? value : 0;
  }
}

const actions = [];
if (fs.existsSync(actionLog)) {
  const rows = fs.readFileSync(actionLog, "utf8").split(/\r?\n/).filter(Boolean);

  for (const row of rows) {
    const cols = row.split("\t");
    if (cols.length < 6) continue;

    const [timestampRaw, isoTime, service, container, action, result] = cols;
    const timestamp = Number(timestampRaw);

    actions.push({
      timestamp: Number.isFinite(timestamp) ? timestamp : null,
      time: isoTime || null,
      service,
      container,
      action,
      result,
    });
  }
}

actions.sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0));

const now = Math.floor(Date.now() / 1000);
const windowSeconds = 3600;
const recentWindow = actions.filter(
  (entry) => entry.timestamp && entry.timestamp >= now - windowSeconds,
);

const successful = actions.filter(
  (entry) => entry.action === "restart" && entry.result.startsWith("success:"),
);
const blocked = actions.filter(
  (entry) => entry.result.startsWith("blocked:"),
);
const failed = actions.filter(
  (entry) =>
    entry.action === "restart" &&
    !entry.result.startsWith("success:") &&
    !entry.result.startsWith("blocked:"),
);

const lastSuccessful = successful[0] || null;
const lastBlocked = blocked[0] || null;
const lastFailed = failed[0] || null;

const services = Object.entries(policy).map(([service, recoveryPolicy]) => ({
  service,
  policy: recoveryPolicy,
  restartCount: restartCounts[service] ?? 0,
}));

status.recovery = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  mode: "bounded",
  defaults: {
    restartDeltaThreshold: Number(process.env.SPORTSOS_RECOVERY_POLICY_RESTART_DELTA_THRESHOLD),
    cooldownSeconds: Number(process.env.SPORTSOS_RECOVERY_POLICY_COOLDOWN_SECONDS),
    budgetWindowSeconds: Number(process.env.SPORTSOS_RECOVERY_POLICY_BUDGET_WINDOW_SECONDS),
    maxActionsPerWindow: Number(process.env.SPORTSOS_RECOVERY_POLICY_MAX_ACTIONS_PER_WINDOW),
    postRecoveryTimeoutSeconds: Number(process.env.SPORTSOS_RECOVERY_POLICY_POST_TIMEOUT_SECONDS),
  },
  summary: {
    servicesMonitored: services.length,
    autoRecoveryServices: services.filter((s) => s.policy === "auto").length,
    monitorOnlyServices: services.filter((s) => s.policy === "monitor").length,
    totalSuccessfulRecoveries: successful.length,
    totalBlockedRecoveries: blocked.length,
    totalFailedRecoveries: failed.length,
    recentSuccessfulRecoveries: recentWindow.filter(
      (entry) =>
        entry.action === "restart" && entry.result.startsWith("success:"),
    ).length,
    recentBlockedRecoveries: recentWindow.filter(
      (entry) => entry.result.startsWith("blocked:"),
    ).length,
  },
  lastSuccessfulRecovery: lastSuccessful,
  lastBlockedRecovery: lastBlocked,
  lastFailedRecovery: lastFailed,
  services,
  recentActions: actions.slice(0, 20),
};

fs.writeFileSync(statusFile, JSON.stringify(status, null, 2) + "\n");
NODE

  # Preserve the API-readable permission contract established in M30.
  chown 1000:1000 "$OPERATIONS_STATUS_FILE" 2>/dev/null || true
  chmod 640 "$OPERATIONS_STATUS_FILE" 2>/dev/null || true
fi

# SPORTSOS_M33_6_5_RECOVERY_GUARDRAIL_ENRICHMENT
source "${ROOT}/scripts/lib/recovery-policy.sh"

SPORTSOS_M33_6_STATUS_FILE="${SPORTSOS_OPERATIONS_STATUS_FILE:-${ROOT}/data/operations-status/latest.json}"
SPORTSOS_M33_6_ACTION_LOG="${SPORTSOS_RECOVERY_STATE_DIR:-${ROOT}/data/operations-recovery}/recovery-actions.tsv"

export SPORTSOS_M33_6_STATUS_FILE
export SPORTSOS_M33_6_ACTION_LOG
export SPORTSOS_M33_6_COOLDOWN_SECONDS="$COOLDOWN_SECONDS"
export SPORTSOS_M33_6_BUDGET_WINDOW_SECONDS="$BUDGET_WINDOW_SECONDS"
export SPORTSOS_M33_6_MAX_ACTIONS_PER_WINDOW="$MAX_ACTIONS_PER_WINDOW"

node <<'NODE'
const fs = require("fs");

const statusFile = process.env.SPORTSOS_M33_6_STATUS_FILE;
const actionLog = process.env.SPORTSOS_M33_6_ACTION_LOG;

if (!statusFile || !fs.existsSync(statusFile)) {
  console.error("ERROR: operations status file missing.");
  process.exit(1);
}

const status = JSON.parse(fs.readFileSync(statusFile, "utf8"));
if (!status.recovery || !Array.isArray(status.recovery.services)) {
  console.error("ERROR: recovery.services missing.");
  process.exit(1);
}

const cooldownSeconds = Number(process.env.SPORTSOS_M33_6_COOLDOWN_SECONDS);
const budgetWindowSeconds = Number(process.env.SPORTSOS_M33_6_BUDGET_WINDOW_SECONDS);
const maxActionsPerWindow = Number(process.env.SPORTSOS_M33_6_MAX_ACTIONS_PER_WINDOW);

const actions = [];
if (actionLog && fs.existsSync(actionLog)) {
  for (const line of fs.readFileSync(actionLog, "utf8").split(/\r?\n/).filter(Boolean)) {
    const c = line.split("\t");
    if (c.length < 6) continue;
    const epoch = Number(c[0]);
    if (!Number.isFinite(epoch)) continue;
    actions.push({
      epoch,
      service: c[2],
      action: c[4],
      result: c[5],
    });
  }
}

const now = Math.floor(Date.now() / 1000);
const cutoff = now - budgetWindowSeconds;

function successEpochs(service) {
  return actions
    .filter(
      (a) =>
        a.service === service &&
        a.action === "restart" &&
        a.result.startsWith("success:"),
    )
    .map((a) => a.epoch);
}

status.recovery.services = status.recovery.services.map((service) => {
  if (service.policy !== "auto") {
    return {
      ...service,
      guardrailState: "monitor-only",
      eligible: false,
      blockedReason: "monitor-only",
      successfulActionsInWindow: 0,
      remainingBudget: 0,
      cooldownRemainingSeconds: 0,
    };
  }

  const successes = successEpochs(service.service);
  const successfulActionsInWindow = successes.filter((epoch) => epoch >= cutoff).length;
  const remainingBudget = Math.max(0, maxActionsPerWindow - successfulActionsInWindow);
  const lastSuccess = successes.length ? Math.max(...successes) : null;
  const cooldownRemainingSeconds =
    lastSuccess === null
      ? 0
      : Math.max(0, cooldownSeconds - (now - lastSuccess));

  if (cooldownRemainingSeconds > 0) {
    return {
      ...service,
      guardrailState: "cooldown",
      eligible: false,
      blockedReason: "cooldown",
      successfulActionsInWindow,
      remainingBudget,
      cooldownRemainingSeconds,
    };
  }

  if (remainingBudget <= 0) {
    return {
      ...service,
      guardrailState: "budget-exhausted",
      eligible: false,
      blockedReason: "budget-exhausted",
      successfulActionsInWindow,
      remainingBudget,
      cooldownRemainingSeconds: 0,
    };
  }

  return {
    ...service,
    guardrailState: "ready",
    eligible: true,
    blockedReason: null,
    successfulActionsInWindow,
    remainingBudget,
    cooldownRemainingSeconds: 0,
  };
});

const tmp = `${statusFile}.m33-6-5.tmp`;
fs.writeFileSync(tmp, `${JSON.stringify(status, null, 2)}\n`, { mode: 0o640 });
fs.renameSync(tmp, statusFile);
NODE

chown 1000:1000 "$SPORTSOS_M33_6_STATUS_FILE" 2>/dev/null || true
chmod 640 "$SPORTSOS_M33_6_STATUS_FILE" 2>/dev/null || true
