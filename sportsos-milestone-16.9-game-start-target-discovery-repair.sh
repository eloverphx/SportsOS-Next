#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-16.9-game-start-target-discovery-repair-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "apps/api/src/modules/games/lifecycle.ts" \
  "apps/api/src/modules/games/engine.ts" \
  "apps/api/src/services/scoreboardPregameReadinessGate.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

mkdir -p "$BACKUP/apps/api/src/modules/games"
cp -a apps/api/src/modules/games/lifecycle.ts "$BACKUP/apps/api/src/modules/games/"
cp -a apps/api/src/modules/games/engine.ts "$BACKUP/apps/api/src/modules/games/"

PROBE="apps/api/src/services/scoreboardGameStartPath.discovery.txt"
mkdir -p "$(dirname "$PROBE")"

{
  echo "SportsOS 16.9 corrected game-start discovery"
  echo
  echo "lifecycle.ts startGame references:"
  grep -n -C 8 'startGame' apps/api/src/modules/games/lifecycle.ts || true
  echo
  echo "engine.ts SCHEDULED -> LIVE references:"
  grep -n -C 10 -E 'SCHEDULED|state\.status = "LIVE"|startGame' apps/api/src/modules/games/engine.ts || true
  echo
  echo "routes/repository references:"
  grep -RIn -C 4 -E 'startGame|gameAction|lifecycle|applyGame|engine' \
    apps/api/src/modules/games/routes.ts \
    apps/api/src/modules/games/repository.ts 2>/dev/null || true
} > "$PROBE"

cat <<'EOF'
============================================================
 SportsOS-Next Milestone 16.9 discovery repair
============================================================

The previous script selected runtime-supervisor.ts because it scored
the word "start" too broadly. runtime-supervisor.ts supervises games
that are already LIVE; it is not the game-start mutation path.

This repair intentionally stops before modifying game behavior.
It captures the real lifecycle/engine path so the next patch can bind
the readiness gate at the correct boundary.

Repository behavior files are NOT modified by this repair.
EOF

echo
echo "Discovery written to:"
echo "  $ROOT/$PROBE"
echo
echo "Show it with:"
echo "  cat $PROBE"
echo
echo "Also run:"
echo "  sed -n '1,120p' apps/api/src/modules/games/lifecycle.ts"
echo "  sed -n '50,115p' apps/api/src/modules/games/engine.ts"
echo
echo "Backup:"
echo "  $BACKUP"
