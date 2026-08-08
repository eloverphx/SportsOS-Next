#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

SPEC="e2e/game-day-scorekeeper.spec.ts"

if [[ ! -f "$SPEC" ]]; then
  echo "Missing Milestone 5.6 spec: $SPEC" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/5.6-player-id-normalization-${STAMP}"
mkdir -p "$BACKUP_DIR/e2e"
cp "$SPEC" "$BACKUP_DIR/$SPEC"

node <<'NODE'
const fs = require("fs");
const path = "e2e/game-day-scorekeeper.spec.ts";
let text = fs.readFileSync(path, "utf8");

const oldBlock = `      const event = {
        id: events.length + 1,
        type: body.type,
        side: body.side,
        period: game.period,
        clockRemainingMs: game.clockRemainingMs,
        playerName:
          body.playerId === 1001
            ? "Alex Laker"
            : body.playerId === 2001
              ? "Eddie Hornet"
              : null,
        playerJerseyNumber:
          body.playerId === 1001 ? 18 : body.playerId === 2001 ? 22 : null,`;

const newBlock = `      const normalizedPlayerId =
        body.playerId === null || body.playerId === undefined || body.playerId === ""
          ? null
          : Number(body.playerId);

      const event = {
        id: events.length + 1,
        type: body.type,
        side: body.side,
        period: game.period,
        clockRemainingMs: game.clockRemainingMs,
        playerName:
          normalizedPlayerId === 1001
            ? "Alex Laker"
            : normalizedPlayerId === 2001
              ? "Eddie Hornet"
              : null,
        playerJerseyNumber:
          normalizedPlayerId === 1001 ? 18 : normalizedPlayerId === 2001 ? 22 : null,`;

if (!text.includes(oldBlock)) {
  throw new Error("Could not find player identity fixture block");
}

text = text.replace(oldBlock, newBlock);

fs.writeFileSync(path, text);
NODE

echo
echo "============================================="
echo " SportsOS 5.6 Player ID Fixture Fix"
echo "============================================="
echo
echo "Modified:"
echo "  $SPEC"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Fixture now normalizes select values:"
echo '  "1001" -> 1001'
echo '  "2001" -> 2001'
echo
echo "Production code unchanged."
echo
echo "Run:"
echo "  npm run test:e2e:docker"
