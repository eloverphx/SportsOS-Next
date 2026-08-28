#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
STATE_DIR="${SPORTSOS_RELIABILITY_ALERT_STATE_DIR:-${ROOT}/data/operations-alerts}"
COOLDOWN_MINUTES="${SPORTSOS_RELIABILITY_ALERT_COOLDOWN_MINUTES:-60}"
WEBHOOK_URL="${SPORTSOS_RELIABILITY_ALERT_WEBHOOK_URL:-${SPORTSOS_ALERT_WEBHOOK_URL:-}}"
STAMP="$(date +%Y%m%d-%H%M%S)"
STATE_FILE="${STATE_DIR}/reliability-alert-state.json"
EVENT_FILE="${STATE_DIR}/reliability-alert-${STAMP}.json"

cd "$ROOT"

if ! [[ "$COOLDOWN_MINUTES" =~ ^[0-9]+$ ]]; then
  echo "ERROR: SPORTSOS_RELIABILITY_ALERT_COOLDOWN_MINUTES must be a non-negative integer." >&2
  exit 1
fi

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
umask 077

set +e
score_output="$(bash scripts/operations-reliability-scorecard.sh 2>&1)"
score_rc=$?
set -e

printf '%s\n' "$score_output"

if [[ "$score_rc" -eq 0 ]]; then
  node - "$STATE_FILE" <<'NODE'
const fs = require("node:fs");
const [stateFile] = process.argv.slice(2);

const state = {
  schemaVersion: 1,
  status: "healthy",
  lastHealthyAt: new Date().toISOString(),
};

fs.writeFileSync(
  stateFile,
  `${JSON.stringify(state, null, 2)}\n`,
  { mode: 0o600 },
);
NODE
  chmod 600 "$STATE_FILE"
  echo "PASS  reliability scorecard is healthy; no alert generated."
  exit 0
fi

if [[ "$score_rc" -ne 3 ]]; then
  echo "ERROR: reliability scorecard failed unexpectedly with exit code $score_rc." >&2
  exit "$score_rc"
fi

LATEST_SCORE="$(
  find "$ROOT/data/operations-reliability" \
    -maxdepth 1 \
    -type f \
    -name 'reliability-*.json' \
    -printf '%T@ %p\n' \
    2>/dev/null |
    sort -nr |
    head -1 |
    cut -d' ' -f2-
)"

if [[ -z "$LATEST_SCORE" || ! -f "$LATEST_SCORE" ]]; then
  echo "ERROR: reliability scorecard returned attention but no JSON result was found." >&2
  exit 1
fi

node - \
  "$LATEST_SCORE" \
  "$STATE_FILE" \
  "$EVENT_FILE" \
  "$COOLDOWN_MINUTES" \
  "$WEBHOOK_URL" <<'NODE'
const fs = require("node:fs");
const crypto = require("node:crypto");

const [
  scoreFile,
  stateFile,
  eventFile,
  cooldownMinutesArg,
  webhookUrl,
] = process.argv.slice(2);

const score = JSON.parse(fs.readFileSync(scoreFile, "utf8"));
const cooldownMinutes = Number(cooldownMinutesArg);
const now = Date.now();

const normalizedIssues =
  (score.issues ?? [])
    .map((issue) => ({
      type: issue.type,
      mode: issue.mode,
      message: issue.message,
    }))
    .sort((a, b) =>
      `${a.type}:${a.mode}:${a.message}`.localeCompare(
        `${b.type}:${b.mode}:${b.message}`,
      ),
    );

const fingerprint =
  crypto
    .createHash("sha256")
    .update(JSON.stringify(normalizedIssues))
    .digest("hex");

let state = {};

try {
  state = JSON.parse(fs.readFileSync(stateFile, "utf8"));
} catch {
  state = {};
}

const lastAlertMs =
  Date.parse(state.lastAlertAt || "") || 0;

const sameFingerprint =
  state.lastFingerprint === fingerprint;

const insideCooldown =
  sameFingerprint &&
  lastAlertMs > 0 &&
  (now - lastAlertMs) < (cooldownMinutes * 60 * 1000);

const event = {
  schemaVersion: 1,
  generatedAt: new Date(now).toISOString(),
  severity: "warning",
  source: "operations-reliability",
  fingerprint,
  suppressed: insideCooldown,
  overallStatus: score.overallStatus,
  issues: normalizedIssues,
  scorecard: scoreFile,
};

fs.writeFileSync(
  eventFile,
  `${JSON.stringify(event, null, 2)}\n`,
  { mode: 0o600 },
);

if (insideCooldown) {
  console.log(
    `SKIP  duplicate reliability alert suppressed within ${cooldownMinutes} minute cooldown.`,
  );
  process.exit(0);
}

const nextState = {
  schemaVersion: 1,
  status: "attention",
  lastFingerprint: fingerprint,
  lastAlertAt: new Date(now).toISOString(),
  lastEventFile: eventFile,
};

fs.writeFileSync(
  stateFile,
  `${JSON.stringify(nextState, null, 2)}\n`,
  { mode: 0o600 },
);

console.log("ALERT reliability requires attention.");

for (const issue of normalizedIssues) {
  console.log(`  - ${issue.message}`);
}

if (webhookUrl) {
  const body = JSON.stringify({
    text:
      "SportsOS reliability requires attention: " +
      normalizedIssues.map((issue) => issue.message).join("; "),
    event,
  });

  fetch(webhookUrl, {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body,
  }).then((response) => {
    if (!response.ok) {
      throw new Error(
        `Webhook returned HTTP ${response.status}`,
      );
    }

    console.log("PASS  reliability alert webhook delivered.");
  }).catch((error) => {
    console.error(
      `ERROR: reliability alert webhook failed: ${error.message}`,
    );
    process.exitCode = 4;
  });
} else {
  console.log("INFO  no reliability alert webhook configured; local alert recorded.");
}
NODE

rc=$?
chmod 600 "$STATE_FILE" "$EVENT_FILE" 2>/dev/null || true
exit "$rc"
