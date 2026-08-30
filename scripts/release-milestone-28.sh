#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
TAG="${SPORTSOS_M28_RELEASE_TAG:-sportsos-m28-complete}"
MESSAGE="${SPORTSOS_M28_RELEASE_MESSAGE:-feat(operations): complete milestone 28 production reliability}"
APPLY="${SPORTSOS_APPLY_M28_RELEASE:-0}"

cd "$ROOT"

echo "============================================================"
echo " SportsOS Milestone 28 Release Closeout"
echo "============================================================"
echo "Tag:   $TAG"
echo "Apply: $APPLY"
echo

LATEST_CLOSEOUT="$(
  find "$ROOT/data/operations-closeout" \
    -maxdepth 1 \
    -type f \
    -name 'operations-closeout-*.txt' \
    -printf '%T@ %p\n' \
    2>/dev/null |
    sort -nr |
    head -1 |
    cut -d' ' -f2-
)"

if [[ -z "$LATEST_CLOSEOUT" || ! -f "$LATEST_CLOSEOUT" ]]; then
  echo "ERROR: no Milestone 28 operations closeout report found." >&2
  exit 1
fi

echo "Latest closeout:"
echo "  $LATEST_CLOSEOUT"

if ! grep -q '^Operations closeout PASSED\.$' "$LATEST_CLOSEOUT"; then
  echo "ERROR: latest operations closeout did not pass." >&2
  exit 1
fi

echo "PASS  latest operations closeout passed"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "ERROR: tag already exists: $TAG" >&2
  exit 1
fi

echo
echo "Repository status:"
git status --short

# Runtime and backup locations must never be staged.
blocked_staged="$(
  git diff --cached --name-only |
    grep -E \
      '(^|/)(\.env($|\.)|data/|\.game-engine-backups/|\.deployment-backups/)' \
      || true
)"

if [[ -n "$blocked_staged" ]]; then
  echo
  echo "ERROR: blocked runtime/secret paths are staged:" >&2
  echo "$blocked_staged" >&2
  exit 1
fi

# Do not commit direct secret assignments if any happen to be staged.
secret_matches="$(
  git diff --cached --unified=0 --no-color |
    grep '^+' |
    grep -Ev '^\+\+\+' |
    grep -Ei \
      '(PASSWORD|SECRET|TOKEN|API[_-]?KEY|PRIVATE[_-]?KEY)[[:space:]]*[:=][[:space:]]*[^$<{[:space:]]' \
      || true
)"

if [[ -n "$secret_matches" ]]; then
  echo
  echo "ERROR: staged diff appears to contain a direct secret assignment." >&2
  echo "Review with: git diff --cached" >&2
  exit 1
fi

echo
echo "Candidate Milestone 28 files:"
git status --short |
  grep -E \
    '(^|[[:space:]])(scripts/|docs/|packages/core/test/|docker-compose\.logging\.yml|\.gitignore)' \
  || true

echo
echo "Release commit message:"
echo "  $MESSAGE"

if [[ "$APPLY" != "1" ]]; then
  echo
  echo "DRY RUN ONLY."
  echo
  echo "Review the repository status above."
  echo "To create the Milestone 28 release commit/tag:"
  echo
  echo "  SPORTSOS_APPLY_M28_RELEASE=1 bash scripts/release-milestone-28.sh"
  echo
  exit 0
fi

echo
echo "Staging Milestone 28 production-operations sources..."

git add \
  scripts \
  docs \
  packages/core/test \
  .gitignore \
  docker-compose.logging.yml \
  2>/dev/null || true

blocked_staged="$(
  git diff --cached --name-only |
    grep -E \
      '(^|/)(\.env($|\.)|data/|\.game-engine-backups/|\.deployment-backups/)' \
      || true
)"

if [[ -n "$blocked_staged" ]]; then
  echo "ERROR: blocked runtime/secret paths became staged." >&2
  echo "$blocked_staged" >&2
  git reset
  exit 1
fi

secret_matches="$(
  git diff --cached --unified=0 --no-color |
    grep '^+' |
    grep -Ev '^\+\+\+' |
    grep -Ei \
      '(PASSWORD|SECRET|TOKEN|API[_-]?KEY|PRIVATE[_-]?KEY)[[:space:]]*[:=][[:space:]]*[^$<{[:space:]]' \
      || true
)"

if [[ -n "$secret_matches" ]]; then
  echo "ERROR: staged diff appears to contain a direct secret assignment." >&2
  git reset
  exit 1
fi

if git diff --cached --quiet; then
  echo "ERROR: nothing staged for Milestone 28 release." >&2
  exit 1
fi

echo
echo "Staged summary:"
git diff --cached --stat

git commit -m "$MESSAGE"
git tag -a "$TAG" -m "SportsOS Milestone 28 - Production Operations & Reliability"

echo
echo "============================================================"
echo "Milestone 28 release created."
echo "Commit:"
git log -1 --oneline
echo
echo "Tag:"
git show-ref --tags "$TAG"
echo "============================================================"
