#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
USER_SCRIPTS_ROOT="${SPORTSOS_UNRAID_USER_SCRIPTS_ROOT:-/boot/config/plugins/user.scripts/scripts}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "/mnt/user/appdata/SportsOS-Next" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" || "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to install scheduler wrappers outside canonical SportsOS-Next root." >&2
  exit 1
fi

if [[ ! -d "$USER_SCRIPTS_ROOT" ]]; then
  echo "ERROR: Unraid User Scripts directory not found:" >&2
  echo "  $USER_SCRIPTS_ROOT" >&2
  echo >&2
  echo "Install the Unraid User Scripts plugin first, or set SPORTSOS_UNRAID_USER_SCRIPTS_ROOT for testing." >&2
  exit 1
fi

declare -A SOURCE
declare -A SCHEDULE

SOURCE["SportsOS Observability"]="$ROOT/scripts/unraid-user-script-sportsos-observability.sh"
SCHEDULE["SportsOS Observability"]="*/5 * * * *"

SOURCE["SportsOS Recovery"]="$ROOT/scripts/unraid-user-script-sportsos-recovery.sh"
SCHEDULE["SportsOS Recovery"]="*/5 * * * *"

SOURCE["SportsOS Daily Operations"]="$ROOT/scripts/unraid-user-script-sportsos-daily.sh"
SCHEDULE["SportsOS Daily Operations"]="15 3 * * *"

SOURCE["SportsOS Weekly Rehearsal"]="$ROOT/scripts/unraid-user-script-sportsos-weekly.sh"
SCHEDULE["SportsOS Weekly Rehearsal"]="30 4 * * 0"

echo "SportsOS Unraid User Scripts installer"
echo
echo "This creates/updates only SportsOS-owned User Scripts folders."
echo "It does NOT edit cron directly."
echo

for name in \
  "SportsOS Observability" \
  "SportsOS Recovery" \
  "SportsOS Daily Operations" \
  "SportsOS Weekly Rehearsal"
do
  src="${SOURCE[$name]}"
  schedule="${SCHEDULE[$name]}"
  dest="$USER_SCRIPTS_ROOT/$name"

  [[ -f "$src" ]] || {
    echo "ERROR: missing wrapper: $src" >&2
    exit 1
  }

  mkdir -p "$dest"

  cat > "$dest/script" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
exec bash "$src"
SCRIPT

  cat > "$dest/name" <<NAME
$name
NAME

  cat > "$dest/description" <<DESC
SportsOS production operations automation. Managed by SportsOS Milestone 29.11.
DESC

  # User Scripts plugin recognizes custom schedules from the schedule file.
  cat > "$dest/schedule" <<SCHEDULE_FILE
custom
$schedule
SCHEDULE_FILE

  chmod +x "$dest/script"
  chmod 600 "$dest/name" "$dest/description" "$dest/schedule" 2>/dev/null || true

  echo "Installed: $name"
  echo "  schedule: $schedule"
  echo "  folder:   $dest"
done

echo
echo "Installation complete."
echo
echo "Open Unraid -> Settings -> User Scripts and verify the four SportsOS entries."
echo "The plugin remains responsible for applying its schedules."

