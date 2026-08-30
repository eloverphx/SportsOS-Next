#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
AUDIT="${ROOT}/scripts/secret-source-audit.sh"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-26.5-secret-audit-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

[[ -f "$AUDIT" ]] || {
  echo "ERROR: missing $AUDIT" >&2
  exit 1
}

mkdir -p "$BACKUP/scripts"
cp -a "$AUDIT" "$BACKUP/scripts/secret-source-audit.sh"

cat > "$AUDIT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"

cd "$ROOT"

echo "============================================================"
echo " SportsOS Secret Source Audit"
echo "============================================================"

failures=0

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1"
  failures=$((failures + 1))
}

if [[ -f .env ]]; then
  pass ".env present"
else
  fail ".env missing"
fi

if [[ -f .env ]]; then
  mode="$(
    stat -c '%a' .env 2>/dev/null ||
    stat -f '%Lp' .env 2>/dev/null ||
    true
  )"

  if [[ "$mode" == "600" ]]; then
    pass ".env permissions = 600"
  else
    fail ".env permissions = ${mode:-unknown} (expected 600)"
  fi
fi

if git check-ignore -q .env; then
  pass ".env is ignored by git"
else
  fail ".env is NOT ignored by git"
fi

tracked="$(
  git ls-files --error-unmatch .env 2>/dev/null || true
)"

if [[ -z "$tracked" ]]; then
  pass ".env is not tracked"
else
  fail ".env is tracked by git"
fi

duplicates=()

for file in \
  .env.local \
  .env.production \
  .env.development \
  .env.override
do
  [[ -f "$file" ]] && duplicates+=("$file")
done

if (( ${#duplicates[@]} == 0 )); then
  pass "no alternate environment source files"
else
  fail "alternate environment sources detected: ${duplicates[*]}"
fi

echo
echo "Checking tracked environment-like files..."

tracked_env_files="$(
  git ls-files |
    grep -E '(^|/)\.env($|[.])|(^|/)[^/]+\.env$' |
    grep -vE '(^|/)\.env\.example$|(^|/)\.env\.sample$' ||
    true
)"

if [[ -z "$tracked_env_files" ]]; then
  pass "no tracked environment files detected"
else
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    fail "tracked environment-like file detected: $file"
  done <<< "$tracked_env_files"
fi

echo
echo "Checking secret assignments in tracked configuration files..."

suspicious=0

while IFS= read -r file; do
  [[ -n "$file" ]] || continue

  case "$file" in
    *.md|*.test.ts|*.spec.ts|*.sh|*.example|*.sample)
      continue
      ;;
  esac

  if grep -Eq '^(JWT_SECRET|MYSQL_PASSWORD|MINIO_ROOT_PASSWORD)=' "$file" 2>/dev/null; then
    fail "secret-style assignment found in tracked file: $file"
    suspicious=$((suspicious + 1))
  fi
done < <(git ls-files)

if (( suspicious == 0 )); then
  pass "no secret-style assignments in tracked configuration files"
fi

echo
echo "Checking backup directories are not tracked..."

backup_tracked="$(
  git ls-files |
    grep -E '(^|/)\.security-backups/|(^|/)\.game-engine-backups/' ||
    true
)"

if [[ -z "$backup_tracked" ]]; then
  pass "security/game-engine backup directories are not tracked"
else
  fail "backup files are tracked by git"
fi

echo
echo "============================================================"

if (( failures > 0 )); then
  echo "Secret source audit FAILED: ${failures} check(s) failed."
  exit 1
fi

echo "Secret source audit PASSED."
EOF

chmod +x "$AUDIT"

echo "============================================================"
echo " SportsOS 26.5 secret-source audit repair installed"
echo "============================================================"
echo
echo "Fixed:"
echo "  - code/tests/docs no longer count as duplicate secrets"
echo "  - audits real environment-like files"
echo "  - audits tracked secret-style assignments"
echo "  - checks backup directories are untracked"
echo "  - never prints secret values"
echo
echo "Backup:"
echo "  $BACKUP/scripts/secret-source-audit.sh"
echo
echo "Run:"
echo "  bash scripts/secret-source-audit.sh"
