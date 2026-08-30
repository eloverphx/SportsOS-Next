#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
EXPECTED_REMOTE_RE='github\.com[:/]eloverphx/SportsOS-Next(\.git)?$'
BASELINE_TAG="${SPORTSOS_RELEASE_BASELINE_TAG:-sportsos-m35-complete}"
REQUIRE_CLEAN="${SPORTSOS_RELEASE_REQUIRE_CLEAN:-1}"
REQUIRE_REMOTE_SYNC="${SPORTSOS_RELEASE_REQUIRE_REMOTE_SYNC:-1}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" || "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "FAIL canonical repository root is required." >&2
  exit 1
fi

cd "$ROOT"

failures=0
warnings=0

pass() { echo "PASS  $*"; }
warn() { echo "WARN  $*"; warnings=$((warnings + 1)); }
fail() { echo "FAIL  $*" >&2; failures=$((failures + 1)); }

check_file() {
  local file="$1"
  [[ -s "$file" ]] && pass "$file exists" || fail "$file is missing or empty"
}

echo "============================================================"
echo " SportsOS Release Governance Preflight"
echo "============================================================"
echo

for file in \
  package.json \
  package-lock.json \
  .github/workflows/ci.yml \
  .github/dependabot.yml \
  .github/PULL_REQUEST_TEMPLATE.md
do
  check_file "$file"
done

echo

echo "=== Release lineage ==="
if git rev-parse -q --verify "refs/tags/$BASELINE_TAG" >/dev/null; then
  if [[ "$(git cat-file -t "$BASELINE_TAG")" == "tag" ]]; then
    pass "$BASELINE_TAG is annotated"
  else
    fail "$BASELINE_TAG is not annotated"
  fi

  BASELINE_COMMIT="$(git rev-parse "$BASELINE_TAG^{commit}")"
  if git merge-base --is-ancestor "$BASELINE_COMMIT" HEAD; then
    pass "HEAD descends from $BASELINE_TAG"
  else
    fail "HEAD does not descend from $BASELINE_TAG"
  fi
else
  fail "baseline tag $BASELINE_TAG is missing"
fi

LATEST_RELEASE_TAG="$(git tag --list 'sportsos-m*-complete' --sort=-version:refname | head -n 1 || true)"
if [[ -n "$LATEST_RELEASE_TAG" ]]; then
  pass "latest local release tag is $LATEST_RELEASE_TAG"
else
  fail "no sportsos-m*-complete release tag exists"
fi

BRANCH="$(git branch --show-current)"
if [[ "$BRANCH" == "main" ]]; then
  pass "release preflight is running on main"
else
  fail "release preflight must run on main (current: ${BRANCH:-DETACHED})"
fi

ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ -n "$ORIGIN_URL" && "$ORIGIN_URL" =~ $EXPECTED_REMOTE_RE ]]; then
  pass "origin targets eloverphx/SportsOS-Next"
else
  fail "origin does not target eloverphx/SportsOS-Next"
fi

if [[ "$REQUIRE_REMOTE_SYNC" == "1" ]]; then
  if git rev-parse -q --verify refs/remotes/origin/main >/dev/null; then
    if [[ "$(git rev-parse HEAD)" == "$(git rev-parse refs/remotes/origin/main)" ]]; then
      pass "HEAD matches origin/main"
    else
      fail "HEAD does not match origin/main; fetch/pull before release"
    fi
  else
    fail "origin/main is not available locally"
  fi
else
  warn "remote synchronization enforcement disabled"
fi

echo

echo "=== Repository cleanliness and prohibited tracked paths ==="
if [[ "$REQUIRE_CLEAN" == "1" ]]; then
  STATUS="$(git status --porcelain=v1)"
  if [[ -z "$STATUS" ]]; then
    pass "worktree and index are clean"
  else
    fail "worktree or index contains changes"
    printf '%s\n' "$STATUS" >&2
  fi
else
  warn "clean-worktree enforcement disabled"
fi

if git ls-files | grep -Eq '(^|/)\.env$'; then
  fail "a real .env file is tracked"
else
  pass "no real .env file is tracked"
fi

if git ls-files | grep -Eq '(^|/)\.game-engine-backups/'; then
  fail ".game-engine-backups content is tracked"
else
  pass ".game-engine-backups is not tracked"
fi

if git ls-files | grep -Eq '^data/'; then
  fail "runtime data/ content is tracked"
else
  pass "runtime data/ is not tracked"
fi

echo

echo "=== GitHub workflow governance ==="
CI=".github/workflows/ci.yml"
for expected in \
  "permissions:" \
  "contents: read" \
  "npm ci --no-audit --no-fund" \
  "npm run lint" \
  "npm run typecheck" \
  "npm run test" \
  "npm run build" \
  "npm run test:e2e"
do
  if grep -Fq "$expected" "$CI"; then
    pass "CI contains: $expected"
  else
    fail "CI missing required governance step: $expected"
  fi
done

DEPENDABOT=".github/dependabot.yml"
if grep -Fq "package-ecosystem: npm" "$DEPENDABOT"; then
  pass "Dependabot monitors npm"
else
  fail "Dependabot npm monitoring is missing"
fi

if grep -Fq "package-ecosystem: github-actions" "$DEPENDABOT"; then
  pass "Dependabot monitors GitHub Actions"
else
  fail "Dependabot GitHub Actions monitoring is missing"
fi

PR_TEMPLATE=".github/PULL_REQUEST_TEMPLATE.md"
for expected in \
  "SPORTSOS_M36_1_RELEASE_GOVERNANCE" \
  "CI is green for the candidate commit" \
  "Security-related dependency updates" \
  "Major-version dependency upgrades" \
  "Release tags are annotated"
do
  if grep -Fq "$expected" "$PR_TEMPLATE"; then
    pass "PR governance contains: $expected"
  else
    fail "PR governance is missing: $expected"
  fi
done

echo

echo "=== Dependency security baseline ==="
if node <<'NODE'
const fs = require("fs");
const root = JSON.parse(fs.readFileSync("package.json", "utf8"));
const lock = JSON.parse(fs.readFileSync("package-lock.json", "utf8"));

if (!root.engines?.node?.includes("22")) {
  console.error("FAIL  package.json does not retain the Node 22 engine baseline");
  process.exit(2);
}

if (!lock.lockfileVersion) {
  console.error("FAIL  package-lock.json has no lockfileVersion");
  process.exit(2);
}

console.log(`PASS  Node engine baseline: ${root.engines.node}`);
console.log(`PASS  npm engine baseline: ${root.engines.npm || "unspecified"}`);
console.log(`PASS  package-lock lockfileVersion: ${lock.lockfileVersion}`);
NODE
then
  :
else
  fail "Node/npm/lockfile structural baseline check failed"
fi

if [[ "${SPORTSOS_RUN_NPM_AUDIT:-0}" == "1" ]]; then
  echo
  echo "Running opt-in npm audit (network required)..."
  AUDIT_TMP="$(mktemp)"
  trap 'rm -f "$AUDIT_TMP"' EXIT
  if npm audit --json >"$AUDIT_TMP" 2>/dev/null; then
    pass "npm audit reports no vulnerability threshold failure"
  else
    audit_rc=$?
    node - "$AUDIT_TMP" <<'NODE' || true
const fs = require("fs");
const file = process.argv[2];
try {
  const audit = JSON.parse(fs.readFileSync(file, "utf8"));
  const v = audit.metadata?.vulnerabilities || {};
  console.log(
    `INFO  npm audit vulnerabilities: critical=${v.critical || 0} high=${v.high || 0} moderate=${v.moderate || 0} low=${v.low || 0}`,
  );
} catch {
  console.log("INFO  npm audit output was not parseable JSON");
}
NODE
    fail "npm audit returned exit code $audit_rc"
  fi
else
  warn "npm audit not run; set SPORTSOS_RUN_NPM_AUDIT=1 for the network-backed audit"
fi

echo

echo "============================================================"
if [[ "$failures" -eq 0 ]]; then
  echo " RELEASE GOVERNANCE PREFLIGHT: PASS"
  echo " Warnings: $warnings"
  echo "============================================================"
  exit 0
fi

echo " RELEASE GOVERNANCE PREFLIGHT: FAIL ($failures checks failed)"
echo " Warnings: $warnings"
echo "============================================================"
exit 3
