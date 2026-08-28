#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
TARGET="${SPORTSOS_ROLLBACK_TARGET:-sportsos-m27-complete}"
APPLY="${SPORTSOS_APPLY_ROLLBACK:-0}"
ROLLBACK_DIR="${SPORTSOS_ROLLBACK_DIR:-${ROOT}/data/operations-rollback}"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="${ROLLBACK_DIR}/rollback-${STAMP}.txt"

cd "$ROOT"

mkdir -p "$ROLLBACK_DIR"
chmod 700 "$ROLLBACK_DIR"
umask 077

echo "============================================================"
echo " SportsOS Production Rollback"
echo "============================================================"
echo "Target: $TARGET"
echo "Apply:  $APPLY"
echo

if ! git rev-parse --verify "${TARGET}^{commit}" >/dev/null 2>&1; then
  echo "ERROR: rollback target does not resolve to a commit: $TARGET" >&2
  exit 1
fi

CURRENT_COMMIT="$(git rev-parse HEAD)"
TARGET_COMMIT="$(git rev-parse "${TARGET}^{commit}")"
CURRENT_DESC="$(git describe --tags --always --dirty 2>/dev/null || true)"
TARGET_DESC="$(git describe --tags --always "$TARGET_COMMIT" 2>/dev/null || true)"

{
  echo "SportsOS Production Rollback Report"
  echo "Captured: $(date -Iseconds)"
  echo "Current commit: $CURRENT_COMMIT"
  echo "Current release: $CURRENT_DESC"
  echo "Target commit: $TARGET_COMMIT"
  echo "Target release: $TARGET_DESC"
} > "$REPORT"

chmod 600 "$REPORT"

echo "Current:"
echo "  $CURRENT_DESC"
echo
echo "Target:"
echo "  $TARGET_DESC"
echo

if [[ "$CURRENT_COMMIT" == "$TARGET_COMMIT" ]]; then
  echo "PASS  already at rollback target."
  exit 0
fi

echo "Checking working tree..."

if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: working tree is not clean." >&2
  echo "Rollback will not proceed with uncommitted changes." >&2
  git status --short
  exit 1
fi

echo "PASS  working tree clean"

echo
echo "Creating pre-rollback production baseline..."
bash scripts/capture-production-baseline.sh

echo
echo "Creating pre-rollback MySQL backup..."
bash scripts/backup-mysql.sh

echo
echo "Creating pre-rollback persistent-data backup..."
bash scripts/backup-persistent-data.sh

if [[ "$APPLY" != "1" ]]; then
  echo
  echo "DRY RUN COMPLETE."
  echo "No Git checkout, container rebuild, or production change was performed."
  echo
  echo "To apply:"
  echo "  SPORTSOS_APPLY_ROLLBACK=1 \\"
  echo "  SPORTSOS_ROLLBACK_TARGET=$TARGET \\"
  echo "    bash scripts/production-rollback.sh"
  exit 0
fi

echo
echo "Applying rollback to $TARGET_COMMIT..."

git checkout --detach "$TARGET_COMMIT"

echo
echo "Rebuilding application services at rollback target..."

docker compose up -d --build api dashboard

echo
echo "Checking production health..."

if bash scripts/production-health-monitor.sh; then
  echo "PASS  rollback target is healthy."
else
  echo "ERROR: rollback target failed health validation." >&2
  echo "Pre-rollback backups were created before checkout." >&2
  exit 1
fi

echo
echo "Rollback completed."
echo "Current HEAD:"
git log -1 --oneline --decorate
