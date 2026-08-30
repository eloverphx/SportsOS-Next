#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
OUT_DIR="${SPORTSOS_RELEASE_ARTIFACT_DIR:-${ROOT}/release-artifacts}"

cd "$ROOT"

mkdir -p "$OUT_DIR"

VERSION="$(
  node -p "require('./package.json').version"
)"

COMMIT="$(
  git rev-parse HEAD
)"

SHORT_COMMIT="$(
  git rev-parse --short HEAD
)"

BRANCH="$(
  git branch --show-current
)"

TAG="$(
  git describe --tags --exact-match HEAD 2>/dev/null || true
)"

DIRTY="$(
  if [[ -n "$(git status --porcelain)" ]]; then
    echo yes
  else
    echo no
  fi
)"

STAMP="$(
  date +%Y%m%d-%H%M%S
)"

ARTIFACT="${OUT_DIR}/sportsos-release-${VERSION}-${SHORT_COMMIT}-${STAMP}.md"

{
  echo "# SportsOS Release Artifact"
  echo
  echo "Generated: $(date --iso-8601=seconds)"
  echo
  echo "## Release Identity"
  echo
  echo "- Version: ${VERSION}"
  echo "- Commit: ${COMMIT}"
  echo "- Branch: ${BRANCH:-detached}"
  echo "- Tag: ${TAG:-none}"
  echo "- Dirty working tree: ${DIRTY}"
  echo
  echo "## Recent Changes"
  echo
  git log -15 --pretty='- %h %s'
  echo
  echo "## Milestone 23 Acceptance"
  echo
  sed -n '1,220p' docs/MILESTONE-23-BROADCAST-OPERATIONS-ACCEPTANCE.md
  echo
  echo "## Milestone 24 Acceptance"
  echo
  sed -n '1,260p' docs/MILESTONE-24-BROADCAST-RESILIENCE-ACCEPTANCE.md
  echo
  echo "## Deployment Verification Commands"
  echo
  echo '```bash'
  echo 'npm run typecheck && npm test'
  echo 'docker compose up -d --build api dashboard'
  echo 'bash scripts/release-smoke-test.sh'
  echo 'npm run test:e2e:docker'
  echo '```'
} > "$ARTIFACT"

echo "Release artifact created:"
echo "  $ARTIFACT"
