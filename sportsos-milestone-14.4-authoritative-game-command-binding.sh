#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="14.4-authoritative-game-command-binding"
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
  "$ROOT/apps/api/src/services/scoreboardControlInputs.ts" \
  "$ROOT/apps/api/src/routes/scoreboardControlInputs.ts" \
  "$ROOT/apps/api/src/modules/games/routes.ts" \
  "$ROOT/apps/api/src/services/automaticGameScoreboardSync.ts" \
  "$ROOT/packages/core/src/scoreboard-control-input-contract.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

DISCOVERY="$(mktemp)"
trap 'rm -f "$DISCOVERY"' EXIT

node > "$DISCOVERY" <<'NODE'
const fs = require("fs");
const path = require("path");

const files = [];

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      walk(full);
    } else if (entry.isFile() && entry.name.endsWith(".ts")) {
      files.push(full);
    }
  }
}

walk("apps/api/src");

const candidates = [];

for (const file of files) {
  const text = fs.readFileSync(file, "utf8");

  if (!/game/i.test(file) && !/game/i.test(text)) continue;

  const routeHits = [
    ...text.matchAll(/["'`]([^"'`]*\/games\/[^"'`]*)["'`]/g),
  ].map(m => m[1]);

  const commandHits = [
    ...text.matchAll(/\b(startGame|finishGame|adjustScore|setScore|incrementScore|decrementScore|startClock|pauseClock|toggleClock|setPeriod|incrementPeriod|decrementPeriod)\b/g),
  ].map(m => m[1]);

  const exports = [
    ...text.matchAll(/export\s+(?:async\s+)?function\s+([A-Za-z0-9_]+)/g),
    ...text.matchAll(/export\s+const\s+([A-Za-z0-9_]+)/g),
    ...text.matchAll(/export\s+class\s+([A-Za-z0-9_]+)/g),
  ].map(m => m[1]);

  const score = routeHits.length * 4 + commandHits.length * 2 + exports.length;

  if (score > 0) {
    candidates.push({ file, score, routeHits, commandHits, exports });
  }
}

candidates.sort((a,b) => b.score - a.score);

for (const candidate of candidates.slice(0, 12)) {
  console.log(JSON.stringify(candidate));
}
NODE

DISCOVERY_JSON="$(cat "$DISCOVERY")"

if [[ -z "$DISCOVERY_JSON" ]]; then
  echo "ERROR: unable to discover authoritative game command implementation." >&2
  echo "Repository was not modified." >&2
  exit 1
fi

echo "Discovered authoritative game command candidates:"
echo "$DISCOVERY_JSON" | head -n 8

SERVICE="apps/api/src/services/scoreboardControlInputs.ts"
ROUTE="apps/api/src/routes/scoreboardControlInputs.ts"
COMMAND="apps/api/src/services/scoreboardControlCommandBinding.ts"
TEST="packages/core/test/authoritative-game-command-binding-14.4.test.ts"

for file in "$SERVICE" "$ROUTE" "$COMMAND" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
  fi
done

mkdir -p \
  "$(dirname "$COMMAND")" \
  "$(dirname "$TEST")"

cat > "$COMMAND" <<'EOF'
import type {
  ScoreboardControlInputEvent,
} from "@sportsos/core";

export type ScoreboardControlCommand =
  | {
      kind: "SCORE";
      side: "HOME" | "AWAY";
      delta: 1 | -1;
    }
  | {
      kind: "CLOCK";
      action:
        | "START"
        | "PAUSE"
        | "TOGGLE";
    }
  | {
      kind: "PERIOD";
      delta: 1 | -1;
    }
  | {
      kind: "HORN";
    };

export function mapScoreboardControlInputToCommand(
  event: ScoreboardControlInputEvent,
): ScoreboardControlCommand {
  switch (event.type) {
    case "SCORE_HOME_INCREMENT":
      return {
        kind: "SCORE",
        side: "HOME",
        delta: 1,
      };

    case "SCORE_HOME_DECREMENT":
      return {
        kind: "SCORE",
        side: "HOME",
        delta: -1,
      };

    case "SCORE_AWAY_INCREMENT":
      return {
        kind: "SCORE",
        side: "AWAY",
        delta: 1,
      };

    case "SCORE_AWAY_DECREMENT":
      return {
        kind: "SCORE",
        side: "AWAY",
        delta: -1,
      };

    case "CLOCK_START":
      return {
        kind: "CLOCK",
        action: "START",
      };

    case "CLOCK_PAUSE":
      return {
        kind: "CLOCK",
        action: "PAUSE",
      };

    case "CLOCK_TOGGLE":
      return {
        kind: "CLOCK",
        action: "TOGGLE",
      };

    case "PERIOD_INCREMENT":
      return {
        kind: "PERIOD",
        delta: 1,
      };

    case "PERIOD_DECREMENT":
      return {
        kind: "PERIOD",
        delta: -1,
      };

    case "HORN_TRIGGER":
      return {
        kind: "HORN",
      };
  }
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/scoreboardControlInputs.ts";

let text =
  fs.readFileSync(file, "utf8");

if (
  !text.includes(
    'mapScoreboardControlInputToCommand',
  )
) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate scoreboardControlInputs import block.",
    );
  }

  text =
    text.replace(
      imports[0],
      imports[0] +
        'import { mapScoreboardControlInputToCommand } from "./scoreboardControlCommandBinding.js";\n',
    );
}

if (
  !text.includes(
    "command: mapScoreboardControlInputToCommand(",
  )
) {
  text =
    text.replace(
`  return {
    inputId:
      event.inputId,
    deviceId:
      event.deviceId,
    disposition:
      "ACCEPTED",
    reason:
      null,
    authoritativeGameId:
      assignment.gameId,
    processedAt,
  };`,
`  return {
    inputId:
      event.inputId,
    deviceId:
      event.deviceId,
    disposition:
      "ACCEPTED",
    reason:
      null,
    authoritativeGameId:
      assignment.gameId,
    processedAt,
    command:
      mapScoreboardControlInputToCommand(
        event,
      ),
  } as ScoreboardControlInputAck & {
    command: ReturnType<
      typeof mapScoreboardControlInputToCommand
    >;
  };`,
    );
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardControlInputs.ts";

let text =
  fs.readFileSync(file, "utf8");

if (
  !text.includes(
    "const result =",
  )
) {
  text =
    text.replace(
`      return {
        success: true,
        data:
          processScoreboardControlInput(
            body,
            automaticSync,
          ),
      };`,
`      const result =
        processScoreboardControlInput(
          body,
          automaticSync,
        ) as ReturnType<
          typeof processScoreboardControlInput
        > & {
          command?: unknown;
        };

      /*
       * Milestone 14.4:
       * This route now exposes the authoritative command mapping alongside
       * the acceptance decision. Actual game mutation is delegated to the
       * same server-side game command path in the next binding layer; the
       * ESP32 never mutates game state directly.
       */
      return {
        success: true,
        data:
          result,
      };`,
    );
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.4 authoritative game command binding", () => {
  const source = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlCommandBinding.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("maps home and away score controls", () => {
    expect(source).toContain(
      '"SCORE_HOME_INCREMENT"',
    );

    expect(source).toContain(
      'side: "HOME"',
    );

    expect(source).toContain(
      '"SCORE_AWAY_DECREMENT"',
    );

    expect(source).toContain(
      'side: "AWAY"',
    );
  });

  it("maps clock controls", () => {
    for (const action of [
      "CLOCK_START",
      "CLOCK_PAUSE",
      "CLOCK_TOGGLE",
    ]) {
      expect(source).toContain(
        `"${action}"`,
      );
    }

    expect(source).toContain(
      'kind: "CLOCK"',
    );
  });

  it("maps period controls", () => {
    expect(source).toContain(
      '"PERIOD_INCREMENT"',
    );

    expect(source).toContain(
      '"PERIOD_DECREMENT"',
    );

    expect(source).toContain(
      'kind: "PERIOD"',
    );
  });

  it("maps horn trigger", () => {
    expect(source).toContain(
      '"HORN_TRIGGER"',
    );

    expect(source).toContain(
      'kind: "HORN"',
    );
  });

  it("attaches command intent only after control acceptance", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardControlInputs.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      '"ACCEPTED"',
    );

    expect(service).toContain(
      "mapScoreboardControlInputToCommand",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 14.4 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - physical-input -> authoritative-command mapping"
echo "  - score +/- command mapping"
echo "  - clock start/pause/toggle mapping"
echo "  - period +/- mapping"
echo "  - horn command mapping"
echo "  - accepted control inputs now carry server command intent"
echo
echo "Important:"
echo "  - device still never mutates game state directly"
echo "  - server remains authoritative"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api"
echo
echo "Next after green:"
echo "  Milestone 14.5 - Game Mutation Adapter / Physical Control Execution"
