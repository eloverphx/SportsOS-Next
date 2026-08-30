#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
DATA_DIR="${SPORTSOS_DATA_DIR:-${ROOT}/data}"
BACKUP_DIR="${SPORTSOS_BACKUP_DIR:-${DATA_DIR}/backups}"

cd "$ROOT"

failures=0

check() {
  local name="$1"
  shift

  if "$@"; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name"
    failures=$((failures + 1))
  fi
}

check \
  "Git repository present" \
  test -d .git

check \
  "Current commit resolvable" \
  git rev-parse --verify HEAD

check \
  "Compose file present" \
  test -f docker-compose.yml

check \
  "Release smoke test present" \
  test -f scripts/release-smoke-test.sh

check \
  "Persistent data directory readable" \
  test -r "$DATA_DIR"

mkdir -p "$BACKUP_DIR"

check \
  "Backup directory writable" \
  test -w "$BACKUP_DIR"

echo
git status --short
echo
git log -1 --oneline --decorate

echo

if (( failures > 0 )); then
  echo "Rollback preflight FAILED: ${failures} check(s) failed."
  exit 1
fi

echo "Rollback preflight PASSED."
echo
echo "This script does not perform a rollback."
echo "It only verifies rollback/restore prerequisites."
