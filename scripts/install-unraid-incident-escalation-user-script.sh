#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  exit 1
fi

cd "$ROOT"

SOURCE="$ROOT/scripts/unraid-user-script-sportsos-incident-escalation.sh"
PLUGIN_ROOT="/boot/config/plugins/user.scripts/scripts"
ENTRY_NAME="SportsOS Incident Escalation"
ENTRY_DIR="$PLUGIN_ROOT/$ENTRY_NAME"
ENTRY_SCRIPT="$ENTRY_DIR/script"

[[ -f "$SOURCE" ]] || {
  echo "ERROR: source wrapper missing: $SOURCE" >&2
  exit 1
}

[[ -d "/boot/config/plugins/user.scripts" ]] || {
  echo "ERROR: User Scripts plugin is not installed." >&2
  exit 1
}

mkdir -p "$PLUGIN_ROOT"
mkdir -p "$ENTRY_DIR"

# SPORTSOS_M35_3_2_DIRECT_USER_SCRIPT_ENTRY
install -m 0755 "$SOURCE" "$ENTRY_SCRIPT"

echo "Installed User Scripts entry:"
echo "  $ENTRY_NAME"
echo "Path:"
echo "  $ENTRY_SCRIPT"
echo
echo "Schedule is intentionally NOT rewritten here."
echo "Use Unraid -> Settings -> User Scripts:"
echo "  $ENTRY_NAME"
echo "  Schedule: Custom"
echo "  Cron: */5 * * * *"
echo "  Apply"
