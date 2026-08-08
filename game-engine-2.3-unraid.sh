#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

for cmd in bash node npm cp date grep; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
done

APP="apps/api/src/app.ts"
SUPERVISOR="apps/api/src/modules/games/runtime-supervisor.ts"
TEST="apps/api/test/game-runtime-supervisor.test.ts"

for f in "$APP" \
  "apps/api/src/modules/games/repository.ts" \
  "apps/api/src/modules/games/clock-expiration.ts"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing expected SportsOS-Next file: $f" >&2
    exit 1
  fi
done

if ! grep -q 'recoverGameClocksOnStartup' "$APP"; then
  echo "Game Engine 2.2 startup recovery was not detected. Stop and verify 2.2 first." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/2.3-${STAMP}"
mkdir -p "$BACKUP_DIR/apps/api/src"
cp "$APP" "$BACKUP_DIR/$APP"

cat > "$SUPERVISOR" <<'EOF'
import type { RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import { applyGameScoringAction } from "./repository.js";

interface RegulationTransitionCandidate extends RowDataPacket {
  id: number;
  period: number;
}

interface IntermissionTransitionCandidate extends RowDataPacket {
  id: number;
  period: number;
}

export interface AutomaticLifecycleResult {
  intermissionsStarted: number;
  periodsPrepared: number;
}

export async function processAutomaticLifecycleTransitions(): Promise<AutomaticLifecycleResult> {
  const [periodEndRows] = await pool.execute<RegulationTransitionCandidate[]>(
    `SELECT id, period
     FROM games
     WHERE status = 'LIVE'
       AND game_phase = 'REGULATION'
       AND clock_running = FALSE
       AND clock_remaining_ms = 0
       AND period < regulation_periods
     ORDER BY id
     LIMIT 100`,
  );

  let intermissionsStarted = 0;

  for (const row of periodEndRows) {
    const result = await applyGameScoringAction(
      Number(row.id),
      { action: "startIntermission" },
      `runtime:period-end:${Number(row.id)}:${Number(row.period)}`,
    );

    if (result?.applied) intermissionsStarted += 1;
  }

  const [intermissionRows] = await pool.execute<IntermissionTransitionCandidate[]>(
    `SELECT id, period
     FROM games
     WHERE status = 'LIVE'
       AND game_phase = 'INTERMISSION'
       AND intermission_running = FALSE
       AND intermission_remaining_ms = 0
       AND period < regulation_periods
     ORDER BY id
     LIMIT 100`,
  );

  let periodsPrepared = 0;

  for (const row of intermissionRows) {
    const result = await applyGameScoringAction(
      Number(row.id),
      { action: "nextPeriod" },
      `runtime:intermission-complete:${Number(row.id)}:${Number(row.period)}`,
    );

    if (result?.applied) periodsPrepared += 1;
  }

  return {
    intermissionsStarted,
    periodsPrepared,
  };
}

export function startGameRuntimeSupervisor(
  options: {
    intervalMs?: number;
    onError?: (error: unknown) => void;
  } = {},
): () => void {
  const intervalMs = Math.max(250, options.intervalMs ?? 500);
  let running = false;

  const tick = async (): Promise<void> => {
    if (running) return;
    running = true;

    try {
      await processAutomaticLifecycleTransitions();
    } catch (error) {
      options.onError?.(error);
    } finally {
      running = false;
    }
  };

  const timer = setInterval(() => {
    void tick();
  }, intervalMs);

  timer.unref();
  void tick();

  return () => clearInterval(timer);
}
EOF

cat > "$TEST" <<'EOF'
import { beforeEach, describe, expect, it, vi } from "vitest";

const poolExecute = vi.fn();
const applyGameScoringAction = vi.fn();

vi.mock("../src/infrastructure/database.js", () => ({
  pool: {
    execute: poolExecute,
  },
}));

vi.mock("../src/modules/games/repository.js", () => ({
  applyGameScoringAction,
}));

const { processAutomaticLifecycleTransitions } = await import(
  "../src/modules/games/runtime-supervisor.js"
);

beforeEach(() => {
  vi.clearAllMocks();
});

describe("automatic multi-game lifecycle supervision", () => {
  it("starts intermissions for multiple completed early regulation periods", async () => {
    poolExecute
      .mockResolvedValueOnce([
        [
          { id: 11, period: 1 },
          { id: 22, period: 2 },
        ],
      ])
      .mockResolvedValueOnce([[]]);

    applyGameScoringAction.mockResolvedValue({
      game: {},
      applied: true,
    });

    await expect(processAutomaticLifecycleTransitions()).resolves.toEqual({
      intermissionsStarted: 2,
      periodsPrepared: 0,
    });

    expect(applyGameScoringAction).toHaveBeenCalledWith(
      11,
      { action: "startIntermission" },
      "runtime:period-end:11:1",
    );
    expect(applyGameScoringAction).toHaveBeenCalledWith(
      22,
      { action: "startIntermission" },
      "runtime:period-end:22:2",
    );
  });

  it("prepares next regulation periods after intermission expiration", async () => {
    poolExecute
      .mockResolvedValueOnce([[]])
      .mockResolvedValueOnce([
        [
          { id: 31, period: 1 },
          { id: 32, period: 2 },
        ],
      ]);

    applyGameScoringAction.mockResolvedValue({
      game: {},
      applied: true,
    });

    await expect(processAutomaticLifecycleTransitions()).resolves.toEqual({
      intermissionsStarted: 0,
      periodsPrepared: 2,
    });

    expect(applyGameScoringAction).toHaveBeenCalledWith(
      31,
      { action: "nextPeriod" },
      "runtime:intermission-complete:31:1",
    );
    expect(applyGameScoringAction).toHaveBeenCalledWith(
      32,
      { action: "nextPeriod" },
      "runtime:intermission-complete:32:2",
    );
  });

  it("uses database eligibility rules that leave regulation-end decisions manual", async () => {
    poolExecute.mockResolvedValueOnce([[]]).mockResolvedValueOnce([[]]);

    await processAutomaticLifecycleTransitions();

    const firstSql = String(poolExecute.mock.calls[0]?.[0] ?? "");
    const secondSql = String(poolExecute.mock.calls[1]?.[0] ?? "");

    expect(firstSql).toContain("period < regulation_periods");
    expect(secondSql).toContain("period < regulation_periods");
    expect(firstSql).toContain("game_phase = 'REGULATION'");
    expect(secondSql).toContain("game_phase = 'INTERMISSION'");
  });

  it("does not count idempotent replays as new transitions", async () => {
    poolExecute
      .mockResolvedValueOnce([[{ id: 41, period: 1 }]])
      .mockResolvedValueOnce([[]]);

    applyGameScoringAction.mockResolvedValue(null);

    await expect(processAutomaticLifecycleTransitions()).resolves.toEqual({
      intermissionsStarted: 0,
      periodsPrepared: 0,
    });
  });
});
EOF

node <<'NODE'
const fs = require("fs");
const path = "apps/api/src/app.ts";
let text = fs.readFileSync(path, "utf8");

if (!text.includes('startGameRuntimeSupervisor')) {
  // Insert import after clock-expiration import block, regardless of whether it is one or multiple lines.
  const anchor = 'from "./modules/games/clock-expiration.js";';
  const index = text.indexOf(anchor);
  if (index < 0) {
    throw new Error("Could not locate clock-expiration import in app.ts");
  }

  const insertAt = index + anchor.length;
  text =
    text.slice(0, insertAt) +
    '\nimport { startGameRuntimeSupervisor } from "./modules/games/runtime-supervisor.js";' +
    text.slice(insertAt);
}

if (!text.includes("Game runtime supervisor failed")) {
  const varAnchor = "let stopClockExpirationService: (() => void) | undefined;";
  const varIndex = text.indexOf(varAnchor);
  if (varIndex < 0) {
    throw new Error("Could not locate clock expiration service variable in app.ts");
  }

  const varInsertAt = varIndex + varAnchor.length;
  text =
    text.slice(0, varInsertAt) +
    '\n    let stopGameRuntimeSupervisor: (() => void) | undefined;' +
    text.slice(varInsertAt);

  const startAnchor = "stopClockExpirationService = startClockExpirationService({";
  const startIndex = text.indexOf(startAnchor);
  if (startIndex < 0) {
    throw new Error("Could not locate expiration service startup in app.ts");
  }

  // Find the end of the startClockExpirationService assignment by locating the first "});"
  // after its start.
  const endIndex = text.indexOf("});", startIndex);
  if (endIndex < 0) {
    throw new Error("Could not locate expiration service startup terminator in app.ts");
  }

  const supervisorStart = `

      stopGameRuntimeSupervisor = startGameRuntimeSupervisor({
        onError: (error) =>
          app.log.error({ error }, "Game runtime supervisor failed"),
      });`;

  text =
    text.slice(0, endIndex + 3) +
    supervisorStart +
    text.slice(endIndex + 3);

  const closeAnchor = "stopClockExpirationService?.();";
  const closeIndex = text.indexOf(closeAnchor);
  if (closeIndex < 0) {
    throw new Error("Could not locate expiration service shutdown in app.ts");
  }

  const closeInsertAt = closeIndex + closeAnchor.length;
  text =
    text.slice(0, closeInsertAt) +
    "\n      stopGameRuntimeSupervisor?.();" +
    text.slice(closeInsertAt);
}

fs.writeFileSync(path, text);
NODE

echo
echo "============================================="
echo " SportsOS Next - Game Engine 2.3"
echo " Automatic Lifecycle + Multi-game Supervisor"
echo "============================================="
echo
echo "Created:"
echo "  $SUPERVISOR"
echo "  $TEST"
echo
echo "Modified:"
echo "  $APP"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Automation policy:"
echo "  period 1/2 end -> intermission automatically"
echo "  intermission expiry -> next regulation period prepared automatically"
echo "  regulation end -> NO automatic overtime/final decision"
echo "  overtime end -> NO automatic final decision"
echo
echo "Run:"
echo "  npm run typecheck"
echo "  npm test"
