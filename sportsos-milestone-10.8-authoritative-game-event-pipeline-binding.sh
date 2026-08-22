#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="10.8-authoritative-game-event-pipeline-binding"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

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
  "$ROOT/apps" \
  "$ROOT/apps/api"
do
  [[ -e "$required" ]] || {
    echo "ERROR: repository safety marker missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

AUTO="apps/api/src/services/automaticGameScoreboardSync.ts"
SYNC="apps/api/src/services/gameScoreboardSync.ts"
ROUTE="apps/api/src/routes/scoreboardDevices.ts"
BINDING="apps/api/src/services/gameScoreboardEventBinding.ts"
TEST="apps/api/test/game-scoreboard-event-binding-10.8.test.ts"

for file in "$AUTO" "$SYNC" "$ROUTE"; do
  [[ -f "$file" ]] || {
    echo "ERROR: required Milestone 10.7 file missing: $file" >&2
    exit 1
  }
done

# Discover the current authoritative realtime publication surface before writes.
mapfile -t EVENT_FILES < <(
  grep -RIl \
    --include='*.ts' \
    --exclude='gameScoreboardEventBinding.ts' \
    -E 'game:updated|scoreboard:update|game:state' \
    apps/api/src 2>/dev/null || true
)

if [[ "${#EVENT_FILES[@]}" -eq 0 ]]; then
  echo "ERROR: could not discover an authoritative game realtime publication surface." >&2
  echo "No repository files were modified." >&2
  exit 1
fi

EVENT_FILE=""
for file in "${EVENT_FILES[@]}"; do
  if grep -Eq '\.emit\([^)]*["'\'']game:updated["'\'']|emit\(["'\'']game:updated["'\'']' "$file"; then
    EVENT_FILE="$file"
    break
  fi
done

if [[ -z "$EVENT_FILE" ]]; then
  for file in "${EVENT_FILES[@]}"; do
    if grep -q 'game:updated' "$file"; then
      EVENT_FILE="$file"
      break
    fi
  done
fi

if [[ -z "$EVENT_FILE" ]]; then
  EVENT_FILE="${EVENT_FILES[0]}"
fi

echo "Discovered authoritative realtime file:"
echo "  $EVENT_FILE"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$BINDING")" \
  "$BACKUP_DIR/$(dirname "$ROUTE")" \
  "$BACKUP_DIR/$(dirname "$EVENT_FILE")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$BINDING")" \
  "$(dirname "$TEST")"

for file in "$BINDING" "$ROUTE" "$EVENT_FILE" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$BINDING" <<'EOF'
import type {
  AuthoritativeGameSnapshot,
} from "./gameScoreboardSync.js";
import {
  AutomaticGameScoreboardSync,
} from "./automaticGameScoreboardSync.js";

let automaticSync:
  AutomaticGameScoreboardSync | null = null;

export function bindAutomaticGameScoreboardSync(
  service: AutomaticGameScoreboardSync,
): void {
  automaticSync = service;
}

export function normalizeAuthoritativeGameUpdate(
  payload: unknown,
): AuthoritativeGameSnapshot | null {
  if (
    !payload ||
    typeof payload !== "object"
  ) {
    return null;
  }

  const record =
    payload as Record<string, unknown>;

  const nested =
    record.game &&
    typeof record.game === "object"
      ? record.game as Record<string, unknown>
      : record;

  const gameId =
    typeof nested.gameId === "string"
      ? nested.gameId
      : typeof nested.id === "string"
        ? nested.id
        : typeof record.gameId === "string"
          ? record.gameId
          : null;

  const homeScore =
    typeof nested.homeScore === "number"
      ? nested.homeScore
      : typeof record.homeScore === "number"
        ? record.homeScore
        : null;

  const awayScore =
    typeof nested.awayScore === "number"
      ? nested.awayScore
      : typeof record.awayScore === "number"
        ? record.awayScore
        : null;

  const period =
    nested.period === null
      ? null
      : typeof nested.period === "number"
        ? nested.period
        : record.period === null
          ? null
          : typeof record.period === "number"
            ? record.period
            : null;

  const clockObject =
    nested.clock &&
    typeof nested.clock === "object"
      ? nested.clock as Record<string, unknown>
      : record.clock &&
          typeof record.clock === "object"
        ? record.clock as Record<string, unknown>
        : null;

  const remainingMs =
    typeof nested.remainingMs === "number"
      ? nested.remainingMs
      : typeof nested.clockRemainingMs === "number"
        ? nested.clockRemainingMs
        : clockObject &&
            typeof clockObject.remainingMs === "number"
          ? clockObject.remainingMs
          : typeof record.remainingMs === "number"
            ? record.remainingMs
            : null;

  const running =
    typeof nested.isClockRunning === "boolean"
      ? nested.isClockRunning
      : typeof nested.clockRunning === "boolean"
        ? nested.clockRunning
        : clockObject &&
            typeof clockObject.running === "boolean"
          ? clockObject.running
          : typeof record.clockRunning === "boolean"
            ? record.clockRunning
            : null;

  if (
    !gameId ||
    homeScore === null ||
    awayScore === null ||
    remainingMs === null ||
    running === null
  ) {
    return null;
  }

  return {
    gameId,
    homeScore,
    awayScore,
    period,
    clock: {
      remainingMs,
      running,
    },
  };
}

export async function notifyAutomaticScoreboardGameUpdate(
  payload: unknown,
): Promise<void> {
  if (!automaticSync) {
    return;
  }

  const snapshot =
    normalizeAuthoritativeGameUpdate(
      payload,
    );

  if (!snapshot) {
    return;
  }

  await automaticSync
    .handleAuthoritativeSnapshot(
      snapshot,
    );
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardDevices.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("bindAutomaticGameScoreboardSync")) {
  const anchor = `import {
  AutomaticGameScoreboardSync,
} from "../services/automaticGameScoreboardSync.js";`;

  if (!text.includes(anchor)) {
    throw new Error(
      "AutomaticGameScoreboardSync import anchor not found.",
    );
  }

  text = text.replace(
    anchor,
`${anchor}
import {
  bindAutomaticGameScoreboardSync,
} from "../services/gameScoreboardEventBinding.js";`,
  );
}

if (
  !text.includes(
    "bindAutomaticGameScoreboardSync(automaticSync);",
  )
) {
  const anchor = `const automaticSync =
  new AutomaticGameScoreboardSync(syncService);`;

  if (!text.includes(anchor)) {
    throw new Error(
      "automaticSync instance anchor not found.",
    );
  }

  text = text.replace(
    anchor,
`${anchor}
bindAutomaticGameScoreboardSync(automaticSync);`,
  );
}

fs.writeFileSync(file, text);
NODE

EVENT_FILE="$EVENT_FILE" node <<'NODE'
const fs = require("fs");
const path = require("path");

const file = process.env.EVENT_FILE;
if (!file) {
  throw new Error("EVENT_FILE missing.");
}

let text = fs.readFileSync(file, "utf8");

if (
  text.includes(
    "notifyAutomaticScoreboardGameUpdate",
  )
) {
  process.exit(0);
}

const bindingAbs =
  path.resolve(
    "apps/api/src/services/gameScoreboardEventBinding.ts",
  );
const eventDir =
  path.dirname(
    path.resolve(file),
  );

let relative =
  path.relative(
    eventDir,
    bindingAbs,
  )
    .replaceAll("\\", "/")
    .replace(/\.ts$/, ".js");

if (!relative.startsWith(".")) {
  relative = `./${relative}`;
}

const importLine =
  `import { notifyAutomaticScoreboardGameUpdate } from "${relative}";`;

const importMatches =
  [...text.matchAll(/^import[\s\S]*?;\s*$/gm)];

if (importMatches.length > 0) {
  const last =
    importMatches[
      importMatches.length - 1
    ];
  const pos =
    last.index + last[0].length;

  text =
    text.slice(0, pos) +
    "\n" +
    importLine +
    "\n" +
    text.slice(pos);
} else {
  text =
    importLine + "\n" + text;
}

/*
 * Patch only a simple, safe game:updated emit shape:
 *   something.emit("game:updated", payload);
 * The payload identifier is reused for scoreboard synchronization.
 */
const patterns = [
  /(^[ \t]*)([A-Za-z0-9_.$()[\]'"]+)\.emit\(\s*"game:updated"\s*,\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*\);/m,
  /(^[ \t]*)([A-Za-z0-9_.$()[\]'"]+)\.emit\(\s*'game:updated'\s*,\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*\);/m,
];

let match = null;

for (const pattern of patterns) {
  match = text.match(pattern);
  if (match) {
    const indent = match[1];
    const payload = match[3];
    const replacement =
      `${match[0]}\n${indent}void notifyAutomaticScoreboardGameUpdate(${payload});`;

    text = text.replace(
      pattern,
      replacement,
    );
    break;
  }
}

if (!match) {
  throw new Error(
    "Found the realtime file but could not safely identify a simple game:updated emit payload. No production event file was written.",
  );
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<EOF
import { describe, expect, it, vi } from "vitest";
import fs from "node:fs";
import {
  bindAutomaticGameScoreboardSync,
  normalizeAuthoritativeGameUpdate,
  notifyAutomaticScoreboardGameUpdate,
} from "../src/services/gameScoreboardEventBinding.js";

describe("Milestone 10.8 authoritative game event binding", () => {
  it("normalizes a direct authoritative game update", () => {
    expect(
      normalizeAuthoritativeGameUpdate({
        gameId: "game-1",
        homeScore: 3,
        awayScore: 2,
        period: 2,
        clock: {
          remainingMs: 45000,
          running: true,
        },
      }),
    ).toEqual({
      gameId: "game-1",
      homeScore: 3,
      awayScore: 2,
      period: 2,
      clock: {
        remainingMs: 45000,
        running: true,
      },
    });
  });

  it("normalizes common flattened clock fields", () => {
    expect(
      normalizeAuthoritativeGameUpdate({
        id: "game-2",
        homeScore: 1,
        awayScore: 1,
        period: 3,
        clockRemainingMs: 12000,
        clockRunning: false,
      }),
    ).toMatchObject({
      gameId: "game-2",
      clock: {
        remainingMs: 12000,
        running: false,
      },
    });
  });

  it("ignores unrelated realtime payloads", () => {
    expect(
      normalizeAuthoritativeGameUpdate({
        message: "not a game update",
      }),
    ).toBeNull();
  });

  it("forwards normalized snapshots into automatic sync", async () => {
    const handleAuthoritativeSnapshot =
      vi.fn().mockResolvedValue({
        synced: false,
        gameId: "game-1",
        reason: "NO_DEVICE_ASSIGNED",
      });

    bindAutomaticGameScoreboardSync({
      handleAuthoritativeSnapshot,
    } as never);

    await notifyAutomaticScoreboardGameUpdate({
      gameId: "game-1",
      homeScore: 2,
      awayScore: 0,
      period: 1,
      remainingMs: 100000,
      clockRunning: true,
    });

    expect(
      handleAuthoritativeSnapshot,
    ).toHaveBeenCalledTimes(1);
  });

  it("binds the authoritative realtime publisher", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../${EVENT_FILE#apps/api/}",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "notifyAutomaticScoreboardGameUpdate",
    );
    expect(source).toContain(
      "game:updated",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 10.8 installed"
echo "============================================================"
echo
echo "Discovered authoritative realtime file:"
echo "  $EVENT_FILE"
echo
echo "Added:"
echo "  - automatic scoreboard event binding"
echo "  - authoritative game update normalizer"
echo "  - direct game:updated -> assigned scoreboard synchronization"
echo "  - no manual realtime-sync POST required for normal game updates"
echo "  - unchanged snapshots still deduplicated by Milestone 10.7"
echo "  - Milestone 10.8 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "If green:"
echo "  docker compose up -d --build api"
echo
echo "Next after green:"
echo "  Milestone 10.9 - Device Recovery / Reconnect State Reconciliation"
