#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.8-nullable-scheduled-start-repair"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/${MILESTONE}-${STAMP}"

cd "$ROOT"

CONTROL="apps/dashboard/components/tournament/GameLiveTransitionControl.tsx"
TRACKING_LIB="apps/dashboard/lib/tournament-game-start-tracking.ts"
TRACKING_TEST="apps/dashboard/test/tournament-game-start-tracking-7.8.test.ts"

for file in "$CONTROL" "$TRACKING_LIB" "$TRACKING_TEST"; do
  [[ -f "$file" ]] || { echo "ERROR: required file missing: $file" >&2; exit 1; }
done

mkdir -p \
  "$BACKUP_DIR/$(dirname "$CONTROL")" \
  "$BACKUP_DIR/$(dirname "$TRACKING_LIB")" \
  "$BACKUP_DIR/$(dirname "$TRACKING_TEST")"

cp -a "$CONTROL" "$BACKUP_DIR/$CONTROL"
cp -a "$TRACKING_LIB" "$BACKUP_DIR/$TRACKING_LIB"
cp -a "$TRACKING_TEST" "$BACKUP_DIR/$TRACKING_TEST"

cat > "$TRACKING_LIB" <<'EOF'
export type GameStartTiming = {
  scheduledStart: string | null;
  actualStart: string | null;
  delayMs: number | null;
  delayMinutes: number | null;
  state:
    | "NOT_SCHEDULED"
    | "NOT_STARTED"
    | "EARLY"
    | "ON_TIME"
    | "DELAYED";
};

export function computeGameStartTiming(
  scheduledStart: string | null,
  actualStart: string | null,
): GameStartTiming {
  if (!scheduledStart) {
    return {
      scheduledStart: null,
      actualStart,
      delayMs: null,
      delayMinutes: null,
      state: "NOT_SCHEDULED",
    };
  }

  const scheduledMs = new Date(scheduledStart).getTime();

  if (!Number.isFinite(scheduledMs)) {
    throw new Error("Invalid scheduled start timestamp.");
  }

  if (!actualStart) {
    return {
      scheduledStart,
      actualStart: null,
      delayMs: null,
      delayMinutes: null,
      state: "NOT_STARTED",
    };
  }

  const actualMs = new Date(actualStart).getTime();

  if (!Number.isFinite(actualMs)) {
    throw new Error("Invalid actual start timestamp.");
  }

  const delayMs = actualMs - scheduledMs;
  const delayMinutes = Math.round((delayMs / 60_000) * 10) / 10;

  let state: GameStartTiming["state"];

  if (Math.abs(delayMs) < 30_000) {
    state = "ON_TIME";
  } else if (delayMs < 0) {
    state = "EARLY";
  } else {
    state = "DELAYED";
  }

  return {
    scheduledStart,
    actualStart,
    delayMs,
    delayMinutes,
    state,
  };
}

export function formatDelayLabel(
  timing: GameStartTiming,
): string {
  switch (timing.state) {
    case "NOT_SCHEDULED":
      return "Not scheduled";
    case "NOT_STARTED":
      return "Not started";
    case "ON_TIME":
      return "On time";
    case "EARLY":
      return `${Math.abs(timing.delayMinutes ?? 0)} min early`;
    case "DELAYED":
      return `${timing.delayMinutes ?? 0} min late`;
  }
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/components/tournament/GameLiveTransitionControl.tsx";

let text = fs.readFileSync(file, "utf8");

text = text.replace(
  "scheduledStart: string;",
  "scheduledStart: string | null;",
);

text = text.replace(
`function formatTimestamp(value: string | null): string {
  if (!value) return "—";`,
`function formatTimestamp(value: string | null): string {
  if (!value) return "Not scheduled";`,
);

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/test/tournament-game-start-tracking-7.8.test.ts";

let text = fs.readFileSync(file, "utf8");

if (!text.includes("reports not-scheduled when scheduled start is missing")) {
  text = text.replace(
`describe("Milestone 7.8 delay / actual start tracking", () => {
  const scheduled = "2026-08-16T20:00:00.000Z";`,
`describe("Milestone 7.8 delay / actual start tracking", () => {
  const scheduled = "2026-08-16T20:00:00.000Z";

  it("reports not-scheduled when scheduled start is missing", () => {
    const timing = computeGameStartTiming(null, null);

    expect(timing).toMatchObject({
      scheduledStart: null,
      delayMs: null,
      delayMinutes: null,
      state: "NOT_SCHEDULED",
    });

    expect(formatDelayLabel(timing)).toBe("Not scheduled");
  });`,
  );
}

fs.writeFileSync(file, text);
NODE

echo
echo "============================================================"
echo " SportsOS-Next Milestone 7.8 nullable start repair installed"
echo "============================================================"
echo
echo "Fixed:"
echo "  - scheduledStart now accepts string | null"
echo "  - unscheduled games display 'Not scheduled'"
echo "  - delay math is skipped until scheduledStart exists"
echo "  - regression test added"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
