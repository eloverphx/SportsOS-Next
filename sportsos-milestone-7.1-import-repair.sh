#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.1-import-repair"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/${MILESTONE}-${STAMP}"

cd "$ROOT"

PAGE="apps/dashboard/app/tournament/game-operations/page.tsx"
WORKSPACE="apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx"

for file in "$PAGE" "$WORKSPACE"; do
  if [[ ! -f "$file" ]]; then
    echo "ERROR: expected Milestone 7.1 file not found: $file" >&2
    exit 1
  fi
done

if ! grep -Fq '@/components/tournament/TournamentGameOperationsWorkspace' "$PAGE"; then
  echo "ERROR: expected 7.1 page import was not found in $PAGE" >&2
  exit 1
fi

if ! grep -Fq '@/lib/tournament-game-operations' "$WORKSPACE"; then
  echo "ERROR: expected 7.1 workspace import was not found in $WORKSPACE" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR/$(dirname "$PAGE")"
mkdir -p "$BACKUP_DIR/$(dirname "$WORKSPACE")"
cp -a "$PAGE" "$BACKUP_DIR/$PAGE"
cp -a "$WORKSPACE" "$BACKUP_DIR/$WORKSPACE"

node <<'NODE'
const fs = require("fs");

const page = "apps/dashboard/app/tournament/game-operations/page.tsx";
const workspace =
  "apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx";

let pageText = fs.readFileSync(page, "utf8");
let workspaceText = fs.readFileSync(workspace, "utf8");

const oldPage =
  'import { TournamentGameOperationsWorkspace } from "@/components/tournament/TournamentGameOperationsWorkspace";';
const newPage =
  'import { TournamentGameOperationsWorkspace } from "../../../components/tournament/TournamentGameOperationsWorkspace";';

const oldWorkspace =
  '} from "@/lib/tournament-game-operations";';
const newWorkspace =
  '} from "../../lib/tournament-game-operations";';

if (!pageText.includes(oldPage)) {
  throw new Error(`Expected page import not found in ${page}`);
}

if (!workspaceText.includes(oldWorkspace)) {
  throw new Error(`Expected workspace import not found in ${workspace}`);
}

pageText = pageText.replace(oldPage, newPage);
workspaceText = workspaceText.replace(oldWorkspace, newWorkspace);

fs.writeFileSync(page, pageText);
fs.writeFileSync(workspace, workspaceText);
NODE

echo
echo "Milestone 7.1 import repair applied."
echo
echo "Changed:"
echo "  $PAGE"
echo "    @/components/... -> ../../../components/..."
echo
echo "  $WORKSPACE"
echo "    @/lib/... -> ../../lib/..."
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo
echo "  npm run typecheck && npm test"
