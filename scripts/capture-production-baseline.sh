#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
OUT_DIR="${SPORTSOS_BASELINE_DIR:-${ROOT}/data/operations-baselines}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${OUT_DIR}/production-baseline-${STAMP}.txt"

cd "$ROOT"
mkdir -p "$OUT_DIR"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

{
  echo "SportsOS Production Operations Baseline"
  echo "Captured: $(date -Iseconds)"
  echo

  echo "=== Git ==="
  echo "Branch: $(git branch --show-current)"
  echo "Commit: $(git rev-parse HEAD)"
  echo "Describe: $(git describe --tags --always --dirty 2>/dev/null || true)"
  echo

  echo "=== Containers ==="
  docker compose ps
  echo

  echo "=== Images ==="
  docker compose images
  echo

  echo "=== Docker Versions ==="
  docker version --format 'Client={{.Client.Version}} Server={{.Server.Version}}' 2>/dev/null || docker version
  echo

  echo "=== API Health ==="
  node - <<'NODE'
fetch("http://127.0.0.1:4001/health")
  .then(async (response) => {
    console.log(`HTTP ${response.status}`);
    console.log(await response.text());
    process.exit(response.ok ? 0 : 1);
  })
  .catch((error) => {
    console.error(String(error));
    process.exit(1);
  });
NODE
  echo

  echo "=== Public Endpoints ==="
  node - <<'NODE'
for (const url of [
  "https://crashthenet.online",
  "https://api.crashthenet.online/health",
]) {
  try {
    const response = await fetch(url, { redirect: "manual" });
    console.log(`${url} -> HTTP ${response.status}`);
  } catch (error) {
    console.log(`${url} -> ERROR ${error instanceof Error ? error.message : String(error)}`);
  }
}
NODE
  echo

  echo "=== Security / Deployment Checks ==="
  for script in \
    scripts/secret-source-audit.sh \
    scripts/security-regression-check.sh \
    scripts/reverse-proxy-contract-check.sh
  do
    if [[ -x "$script" ]]; then
      echo "--- $script ---"
      "$script" || true
      echo
    fi
  done

  echo "=== Persistent Paths ==="
  for path in \
    "$ROOT/data" \
    /mnt/user/appdata/SportsOS-Next
  do
    if [[ -e "$path" ]]; then
      stat -c '%n owner=%U group=%G mode=%a' "$path" 2>/dev/null || true
    fi
  done
} > "$tmp"

sed -E \
  -e 's/(JWT_SECRET=).*/\1[REDACTED]/' \
  -e 's/(MYSQL_PASSWORD=).*/\1[REDACTED]/' \
  -e 's/(MYSQL_ROOT_PASSWORD=).*/\1[REDACTED]/' \
  -e 's/(MINIO_ROOT_PASSWORD=).*/\1[REDACTED]/' \
  -e 's/(MINIO_SECRET_KEY=).*/\1[REDACTED]/' \
  "$tmp" > "$OUT"

chmod 600 "$OUT"

echo "============================================================"
echo " SportsOS Production Baseline Captured"
echo "============================================================"
echo
echo "File:"
echo "  $OUT"
echo
echo "Latest release:"
git describe --tags --always --dirty 2>/dev/null || true
echo
echo "No secret values are intentionally recorded."
