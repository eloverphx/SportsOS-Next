#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
PLUGIN="${ROOT}/apps/api/src/plugins/securityHeaders.ts"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-26.9-x-frame-options-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

[[ -f "$PLUGIN" ]] || {
  echo "ERROR: missing $PLUGIN" >&2
  exit 1
}

mkdir -p "$BACKUP/apps/api/src/plugins"
cp -a "$PLUGIN" "$BACKUP/apps/api/src/plugins/securityHeaders.ts"

node <<'NODE'
const fs = require("fs");

const file = "apps/api/src/plugins/securityHeaders.ts";
let s = fs.readFileSync(file, "utf8");

const old = `      for (
        const [
          name,
          value,
        ]
        of Object.entries(
          SECURITY_HEADERS,
        )
      ) {
        if (
          !reply.hasHeader(
            name,
          )
        ) {
          reply.header(
            name,
            value,
          );
        }
      }`;

const replacement = `      for (
        const [
          name,
          value,
        ]
        of Object.entries(
          SECURITY_HEADERS,
        )
      ) {
        if (
          name ===
          "x-frame-options"
        ) {
          reply.header(
            name,
            value,
          );

          continue;
        }

        if (
          !reply.hasHeader(
            name,
          )
        ) {
          reply.header(
            name,
            value,
          );
        }
      }`;

if (!s.includes(old)) {
  throw new Error("Expected security header loop not found.");
}

s = s.replace(old, replacement);

fs.writeFileSync(file, s);
NODE

echo "============================================================"
echo " SportsOS 26.9 X-Frame-Options conflict repair installed"
echo "============================================================"
echo
echo "Fixed:"
echo "  - X-Frame-Options is now forced to DENY"
echo "  - existing SAMEORIGIN from upstream middleware is overridden"
echo "  - other security headers still preserve existing values"
echo
echo "Backup:"
echo "  $BACKUP/apps/api/src/plugins/securityHeaders.ts"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo "  docker compose up -d --build api dashboard"
echo "  curl -I http://127.0.0.1:4001/health"
echo "  bash scripts/security-regression-check.sh"
