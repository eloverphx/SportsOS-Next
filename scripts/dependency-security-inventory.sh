#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
OUT_DIR="${SPORTSOS_DEPENDENCY_INVENTORY_DIR:-.game-engine-backups/dependency-security-inventory-$(date +%Y%m%d-%H%M%S)}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" || "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "FAIL canonical repository root is required." >&2
  exit 1
fi

cd "$ROOT"

command -v node >/dev/null 2>&1 || { echo "FAIL node is required." >&2; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "FAIL npm is required." >&2; exit 1; }

if [[ ! -f package.json || ! -f package-lock.json ]]; then
  echo "FAIL package.json/package-lock.json are required." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

AUDIT_JSON="$OUT_DIR/npm-audit.json"
OUTDATED_JSON="$OUT_DIR/npm-outdated.json"
SUMMARY="$OUT_DIR/summary.txt"

echo "============================================================"
echo " SportsOS Dependency Security Inventory"
echo "============================================================"
echo
echo "This command is read-only with respect to package.json/package-lock.json."
echo "It does not run npm install, npm update, npm audit fix, or Dependabot merges."
echo

before_pkg="$(sha256sum package.json | awk '{print $1}')"
before_lock="$(sha256sum package-lock.json | awk '{print $1}')"

set +e
npm audit --json >"$AUDIT_JSON" 2>"$OUT_DIR/npm-audit.stderr"
audit_rc=$?
npm outdated --json >"$OUTDATED_JSON" 2>"$OUT_DIR/npm-outdated.stderr"
outdated_rc=$?
set -e

# npm outdated returns 1 when outdated dependencies are found; that is inventory data, not script failure.
if [[ ! -s "$AUDIT_JSON" ]]; then
  printf '{}\n' >"$AUDIT_JSON"
fi
if [[ ! -s "$OUTDATED_JSON" ]]; then
  printf '{}\n' >"$OUTDATED_JSON"
fi

after_pkg="$(sha256sum package.json | awk '{print $1}')"
after_lock="$(sha256sum package-lock.json | awk '{print $1}')"

if [[ "$before_pkg" != "$after_pkg" || "$before_lock" != "$after_lock" ]]; then
  echo "FAIL dependency inventory unexpectedly modified package metadata." >&2
  exit 2
fi

node - "$AUDIT_JSON" "$OUTDATED_JSON" "$audit_rc" "$outdated_rc" >"$SUMMARY" <<'NODE'
const fs = require("fs");

const [auditFile, outdatedFile, auditRcRaw, outdatedRcRaw] = process.argv.slice(2);
const auditRc = Number(auditRcRaw);
const outdatedRc = Number(outdatedRcRaw);

function load(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return {};
  }
}

const audit = load(auditFile);
const outdated = load(outdatedFile);
const vulnerabilities = audit.metadata?.vulnerabilities ?? {};

const rows = Object.entries(outdated).map(([name, info]) => ({
  name,
  current: info?.current ?? "?",
  wanted: info?.wanted ?? "?",
  latest: info?.latest ?? "?",
  location: info?.location ?? "",
}));

const major = [];
const nonMajor = [];

function majorOf(v) {
  const match = String(v ?? "").match(/(\d+)/);
  return match ? Number(match[1]) : null;
}

for (const row of rows) {
  const c = majorOf(row.current);
  const l = majorOf(row.latest);
  if (c !== null && l !== null && c !== l) major.push(row);
  else nonMajor.push(row);
}

console.log("SportsOS Milestone 36.2 dependency security inventory");
console.log("=====================================================");
console.log("");
console.log(`npm audit exit code: ${auditRc}`);
console.log(`npm outdated exit code: ${outdatedRc}`);
console.log("");
console.log("Audit vulnerability counts:");
for (const severity of ["critical", "high", "moderate", "low", "info", "total"]) {
  if (severity in vulnerabilities) {
    console.log(`  ${severity}: ${vulnerabilities[severity]}`);
  }
}
if (Object.keys(vulnerabilities).length === 0) {
  console.log("  unavailable from npm audit output");
}

console.log("");
console.log(`Outdated dependencies discovered: ${rows.length}`);
console.log(`Major-version jumps: ${major.length}`);
console.log(`Same-major updates: ${nonMajor.length}`);

if (major.length) {
  console.log("");
  console.log("Major-version candidates (manual review required):");
  for (const r of major.sort((a, b) => a.name.localeCompare(b.name))) {
    console.log(`  ${r.name}: ${r.current} -> ${r.latest}`);
  }
}

if (nonMajor.length) {
  console.log("");
  console.log("Same-major candidates:");
  for (const r of nonMajor.sort((a, b) => a.name.localeCompare(b.name))) {
    console.log(`  ${r.name}: ${r.current} -> ${r.latest}`);
  }
}
NODE

cat "$SUMMARY"
echo
echo "Raw inventory:"
echo "  $AUDIT_JSON"
echo "  $OUTDATED_JSON"
echo "  $SUMMARY"
echo

if [[ "$audit_rc" -ne 0 ]]; then
  echo "NOTICE npm audit reported findings or a network/audit error."
  echo "Review npm-audit.json before selecting remediation targets."
else
  echo "PASS npm audit returned zero."
fi

echo "PASS package.json and package-lock.json were not modified."
