#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" || "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: invalid SportsOS-Next root." >&2
  exit 1
fi

STATE_DIR="${SPORTSOS_INCIDENT_ESCALATION_STATE_DIR:-${ROOT}/data/operations-incident-escalation}"
STATE_FILE="$STATE_DIR/state.json"
AUDIT_FILE="$STATE_DIR/escalation-events.tsv"

# SPORTSOS_M35_4_ESCALATION_STATUS_COLLECTOR
node - "$STATE_FILE" "$AUDIT_FILE" <<'NODE'
const fs = require("fs");

const stateFile = process.argv[2];
const auditFile = process.argv[3];

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

function readAudit(file) {
  try {
    return fs
      .readFileSync(file, "utf8")
      .split(/\r?\n/)
      .filter(Boolean);
  } catch {
    return [];
  }
}

function parseAuditLine(line) {
  const parts = line.split("\t");
  if (parts.length < 2) return null;

  return {
    observedAt: parts[0] || null,
    incidentId: parts[1] || null,
    severity: parts[2] || null,
    action: parts[3] || null,
    result: parts[4] || null,
    detail: parts.slice(5).join("\t") || null,
  };
}

const state = readJson(stateFile);
const rows = readAudit(auditFile)
  .map(parseAuditLine)
  .filter(Boolean);

const last = rows.length > 0 ? rows[rows.length - 1] : null;

const recent = rows.slice(-20).reverse();

const deliveryFailures = recent.filter((row) => {
  const haystack = [
    row.action,
    row.result,
    row.detail,
  ].filter(Boolean).join(" ").toLowerCase();

  return (
    haystack.includes("fail") ||
    haystack.includes("error") ||
    haystack.includes("timeout")
  );
});

const trackedIncidents =
  state?.incidents && typeof state.incidents === "object"
    ? Object.keys(state.incidents).length
    : 0;

const output = {
  schemaVersion: 1,
  available: Boolean(state || rows.length),
  stateFilePresent: Boolean(state),
  auditFilePresent: rows.length > 0,
  trackedIncidents,
  auditEventCount: rows.length,
  recentEventCount: recent.length,
  recentDeliveryFailureCount: deliveryFailures.length,
  lastEvent: last,
  recentEvents: recent,
};

process.stdout.write(JSON.stringify(output));
NODE
