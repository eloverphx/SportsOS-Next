#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && -n "$EXPECTED_REAL" ]] || {
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
}
[[ "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  exit 1
}

cd "$ROOT"

# SPORTSOS_M34_8_INCIDENT_ESCALATION_POLICY
INCIDENT_DIR="${SPORTSOS_OPERATIONS_INCIDENT_DIR:-${ROOT}/data/operations-incidents}"
INCIDENT_FILE="${INCIDENT_DIR}/incidents.json"
STATE_DIR="${SPORTSOS_INCIDENT_ESCALATION_STATE_DIR:-${ROOT}/data/operations-incident-escalation}"
STATE_FILE="${STATE_DIR}/state.json"
AUDIT_FILE="${STATE_DIR}/escalation-events.tsv"
LOCK_FILE="${STATE_DIR}/escalation.lock"

WARNING_ESCALATE_SECONDS="${SPORTSOS_INCIDENT_WARNING_ESCALATE_SECONDS:-1800}"
CRITICAL_ESCALATE_SECONDS="${SPORTSOS_INCIDENT_CRITICAL_ESCALATE_SECONDS:-300}"
REPEAT_SECONDS="${SPORTSOS_INCIDENT_ESCALATION_REPEAT_SECONDS:-3600}"
WEBHOOK_URL="${SPORTSOS_INCIDENT_ESCALATION_WEBHOOK_URL:-}"
DRY_RUN="${SPORTSOS_INCIDENT_ESCALATION_DRY_RUN:-0}"

mkdir -p "$STATE_DIR"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "Incident escalation already running; exiting."
  exit 0
fi

if [[ ! -f "$INCIDENT_FILE" ]]; then
  echo "No incident journal found; nothing to escalate."
  exit 0
fi

node - "$INCIDENT_FILE" "$STATE_FILE" "$AUDIT_FILE" \
  "$WARNING_ESCALATE_SECONDS" "$CRITICAL_ESCALATE_SECONDS" "$REPEAT_SECONDS" \
  "$WEBHOOK_URL" "$DRY_RUN" <<'NODE'
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const [
  incidentFile,
  stateFile,
  auditFile,
  warningSecondsRaw,
  criticalSecondsRaw,
  repeatSecondsRaw,
  webhookUrl,
  dryRunRaw,
] = process.argv.slice(2);

const warningSeconds = Number(warningSecondsRaw);
const criticalSeconds = Number(criticalSecondsRaw);
const repeatSeconds = Number(repeatSecondsRaw);
const dryRun = dryRunRaw === "1";

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") return fallback;
    throw error;
  }
}

function writeAtomic(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.tmp-${process.pid}`;
  fs.writeFileSync(tmp, JSON.stringify(value, null, 2) + "\n", { mode: 0o640 });
  fs.renameSync(tmp, file);
}

function appendAudit(fields) {
  fs.appendFileSync(auditFile, fields.join("\t") + "\n", { mode: 0o640 });
}

function secondsBetween(fromIso, toMs) {
  const from = Date.parse(fromIso);
  if (!Number.isFinite(from)) return 0;
  return Math.max(0, Math.floor((toMs - from) / 1000));
}

const journal = readJson(incidentFile, { schemaVersion: 1, incidents: [] });
const state = readJson(stateFile, { schemaVersion: 1, incidents: {} });
state.schemaVersion = 1;
state.incidents ??= {};

const now = Date.now();
const nowIso = new Date(now).toISOString();

const active = Array.isArray(journal.incidents)
  ? journal.incidents.filter((incident) =>
      incident &&
      incident.status !== "resolved" &&
      (incident.severity === "warning" || incident.severity === "critical")
    )
  : [];

let escalated = 0;
let suppressed = 0;
let failed = 0;

for (const incident of active) {
  const threshold =
    incident.severity === "critical" ? criticalSeconds : warningSeconds;
  const ageSeconds = secondsBetween(incident.firstSeenAt, now);

  if (ageSeconds < threshold) continue;

  const previous = state.incidents[incident.id] ?? {};
  const lastEscalatedAt = previous.lastEscalatedAt
    ? Date.parse(previous.lastEscalatedAt)
    : NaN;
  const sinceLast = Number.isFinite(lastEscalatedAt)
    ? Math.floor((now - lastEscalatedAt) / 1000)
    : Infinity;

  if (sinceLast < repeatSeconds) {
    suppressed += 1;
    appendAudit([
      nowIso,
      incident.id,
      incident.severity,
      "suppressed",
      "repeat-cooldown",
      String(ageSeconds),
    ]);
    continue;
  }

  const payload = {
    schemaVersion: 1,
    type: "sportsos.operations.incident.escalation",
    generatedAt: nowIso,
    incident: {
      id: incident.id,
      fingerprint: incident.fingerprint,
      severity: incident.severity,
      status: incident.status,
      title: incident.title,
      summary: incident.summary,
      service: incident.service ?? null,
      source: incident.source,
      firstSeenAt: incident.firstSeenAt,
      lastSeenAt: incident.lastSeenAt,
      occurrences: incident.occurrences,
      ageSeconds,
    },
  };

  let result = "local-only";

  if (dryRun) {
    result = "dry-run";
  } else if (webhookUrl) {
    const delivery = spawnSync(
      "curl",
      [
        "--fail",
        "--silent",
        "--show-error",
        "--max-time",
        "10",
        "-H",
        "Content-Type: application/json",
        "--data-binary",
        JSON.stringify(payload),
        webhookUrl,
      ],
      { encoding: "utf8" },
    );

    if (delivery.status !== 0) {
      failed += 1;
      appendAudit([
        nowIso,
        incident.id,
        incident.severity,
        "failed",
        "webhook",
        String(ageSeconds),
      ]);
      continue;
    }

    result = "webhook";
  }

  state.incidents[incident.id] = {
    lastEscalatedAt: nowIso,
    lastSeverity: incident.severity,
    lastStatus: incident.status,
    lastResult: result,
  };

  escalated += 1;
  appendAudit([
    nowIso,
    incident.id,
    incident.severity,
    "escalated",
    result,
    String(ageSeconds),
  ]);
}

for (const [incidentId] of Object.entries(state.incidents)) {
  const stillActive = active.some((incident) => incident.id === incidentId);
  if (!stillActive) {
    delete state.incidents[incidentId];
  }
}

writeAtomic(stateFile, state);

console.log(
  JSON.stringify({
    success: failed === 0,
    activeIncidents: active.length,
    escalated,
    suppressed,
    failed,
    dryRun,
    webhookConfigured: Boolean(webhookUrl),
  }),
);

if (failed > 0) process.exit(2);
NODE
