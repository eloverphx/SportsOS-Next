#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10-runtime-duplicate-scoreboard-route-repair"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  echo "Expected: $EXPECTED_REAL" >&2
  echo "Received: $ROOT_REAL" >&2
  exit 1
fi

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api"
do
  [[ -e "$required" ]] || {
    echo "ERROR: repository safety marker missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

CUSTOM_ROUTE="apps/api/src/routes/scoreboardDevices.ts"
TEST="apps/api/test/scoreboard-route-duplication-repair.test.ts"

[[ -f "$CUSTOM_ROUTE" ]] || {
  echo "ERROR: Milestone 10 custom scoreboard route file missing: $CUSTOM_ROUTE" >&2
  exit 1
}

# Discover canonical existing scoreboard module route source.
mapfile -t CANONICAL_CANDIDATES < <(
  grep -RIl \
    --include='*.ts' \
    --exclude='scoreboardDevices.ts' \
    '"/scoreboard-devices"' \
    apps/api/src 2>/dev/null || true
)

if [[ "${#CANONICAL_CANDIDATES[@]}" -eq 0 ]]; then
  echo "ERROR: could not find an existing canonical scoreboard route file." >&2
  echo "No files were modified." >&2
  exit 1
fi

CANONICAL_ROUTE="${CANONICAL_CANDIDATES[0]}"

echo "Canonical scoreboard route file:"
echo "  $CANONICAL_ROUTE"
echo "Custom Milestone 10 route file:"
echo "  $CUSTOM_ROUTE"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$CUSTOM_ROUTE")" \
  "$BACKUP_DIR/$(dirname "$CANONICAL_ROUTE")" \
  "$BACKUP_DIR/$(dirname "$TEST")"

cp -a "$CUSTOM_ROUTE" "$BACKUP_DIR/$CUSTOM_ROUTE"
cp -a "$CANONICAL_ROUTE" "$BACKUP_DIR/$CANONICAL_ROUTE"
[[ -f "$TEST" ]] && cp -a "$TEST" "$BACKUP_DIR/$TEST"

# Remove only the conflicting base GET routes from the custom route file.
# Keep Milestone 10 command/sync/assignment/reconcile endpoints intact.
node <<'NODE'
const fs = require("fs");

const file = "apps/api/src/routes/scoreboardDevices.ts";
let text = fs.readFileSync(file, "utf8");

function removeRouteBlock(method, literal) {
  const escaped = literal.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

  const patterns = [
    new RegExp(
      `\\n\\s*app\\.${method}\\(\\s*"${escaped}"[\\s\\S]*?\\n\\s*\\);`,
      "m",
    ),
    new RegExp(
      `\\n\\s*app\\.${method}<[\\s\\S]*?>\\(\\s*"${escaped}"[\\s\\S]*?\\n\\s*\\);`,
      "m",
    ),
  ];

  for (const pattern of patterns) {
    const before = text;
    text = text.replace(pattern, "\n");
    if (text !== before) {
      return true;
    }
  }

  return false;
}

const removedList =
  removeRouteBlock("get", "/scoreboard-devices");

const removedDetail =
  removeRouteBlock("get", "/scoreboard-devices/:deviceId");

if (!removedList) {
  console.log(
    "NOTE: custom GET /scoreboard-devices block was not found; it may already be removed.",
  );
}

if (!removedDetail) {
  console.log(
    "NOTE: custom GET /scoreboard-devices/:deviceId block was not found; it may already be removed.",
  );
}

fs.writeFileSync(file, text);
NODE

# Verify no duplicate base GET routes remain across source files.
COUNT_LIST="$(
  grep -R \
    --include='*.ts' \
    -F '"/scoreboard-devices"' \
    apps/api/src \
    | grep -E 'app\.get|\.get\(' \
    | wc -l \
    | tr -d ' '
)"

if [[ "$COUNT_LIST" -gt 1 ]]; then
  echo "ERROR: more than one GET /scoreboard-devices registration still appears in source." >&2
  echo "Matching lines:" >&2
  grep -R \
    --include='*.ts' \
    -n -F '"/scoreboard-devices"' \
    apps/api/src >&2 || true
  exit 1
fi

cat > "$TEST" <<EOF
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 10 runtime duplicate scoreboard route repair", () => {
  it("keeps the canonical base scoreboard route outside the custom gateway route file", () => {
    const custom = fs.readFileSync(
      new URL(
        "../src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(custom).not.toContain(
      'app.get("/scoreboard-devices"',
    );

    expect(custom).not.toContain(
      '"/scoreboard-devices/:deviceId",\\n    async',
    );
  });

  it("preserves Milestone 10 gateway endpoints", () => {
    const custom = fs.readFileSync(
      new URL(
        "../src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(custom).toContain(
      '"/scoreboard-devices/:deviceId/commands"',
    );
    expect(custom).toContain(
      '"/scoreboard-devices/:deviceId/sync-game"',
    );
    expect(custom).toContain(
      '"/scoreboard-devices/assignments"',
    );
    expect(custom).toContain(
      '"/scoreboard-devices/:deviceId/reconcile"',
    );
  });

  it("retains the existing canonical scoreboard route module", () => {
    const canonical = fs.readFileSync(
      new URL(
        "../../../${CANONICAL_ROUTE#apps/api/}",
        import.meta.url,
      ),
      "utf8",
    );

    expect(canonical).toContain(
      "/scoreboard-devices",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next duplicate scoreboard route repair installed"
echo "============================================================"
echo
echo "Canonical route retained:"
echo "  $CANONICAL_ROUTE"
echo
echo "Custom route adjusted:"
echo "  $CUSTOM_ROUTE"
echo
echo "Fixed:"
echo "  - removed duplicate GET /scoreboard-devices from custom Milestone 10 routes"
echo "  - removed duplicate GET /scoreboard-devices/:deviceId when present"
echo "  - preserved commands / sync / assignments / reconcile endpoints"
echo "  - added regression coverage"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then rebuild API:"
echo "  docker compose up -d --build api"
echo
echo "Verify:"
echo "  docker compose ps api"
echo "  curl -i http://192.168.5.3:4001/health"
