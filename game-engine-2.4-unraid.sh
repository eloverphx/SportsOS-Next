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
TELEMETRY="apps/api/src/modules/games/telemetry.ts"
TELEMETRY_ROUTES="apps/api/src/modules/games/telemetry-routes.ts"
TEST="apps/api/test/game-engine-telemetry.test.ts"

for f in "$APP" "$SUPERVISOR" "apps/api/src/modules/games/repository.ts"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing expected SportsOS-Next file: $f" >&2
    exit 1
  fi
done

if ! grep -q 'startGameRuntimeSupervisor' "$APP"; then
  echo "Game Engine 2.3 was not detected in app.ts. Stop and verify 2.3 first." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/2.4-${STAMP}"
mkdir -p "$BACKUP_DIR"

for f in "$APP" "$SUPERVISOR"; do
  mkdir -p "$BACKUP_DIR/$(dirname "$f")"
  cp "$f" "$BACKUP_DIR/$f"
done

cat > "$TELEMETRY" <<'EOF'
import type { RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";

export type EngineGameState =
  | "HEALTHY"
  | "TRANSITION_PENDING"
  | "OPERATOR_REQUIRED"
  | "WARNING";

export interface EngineWarning {
  code: string;
  message: string;
}

export interface EngineTelemetryRow {
  id: number;
  organizationId: number;
  homeTeamName: string;
  awayTeamName: string;
  status: string;
  gamePhase: string;
  period: number;
  regulationPeriods: number;
  clockRemainingMs: number;
  clockRunning: boolean;
  clockStartedAt: Date | string | null;
  intermissionRemainingMs: number;
  intermissionRunning: boolean;
  intermissionStartedAt: Date | string | null;
}

export interface EngineGameTelemetry {
  gameId: number;
  organizationId: number;
  matchup: string;
  state: EngineGameState;
  status: string;
  gamePhase: string;
  period: number;
  regulationPeriods: number;
  clockRemainingMs: number;
  clockRunning: boolean;
  intermissionRemainingMs: number;
  intermissionRunning: boolean;
  actionRequired: string | null;
  warnings: EngineWarning[];
}

export interface EngineTransitionHistoryItem {
  timestamp: string;
  source: "runtime-supervisor" | "system";
  gameId: number;
  action: string;
  outcome: "applied" | "replayed" | "failed";
  detail?: string;
}

const MAX_HISTORY = 100;
const transitionHistory: EngineTransitionHistoryItem[] = [];

export function recordEngineTransition(
  item: Omit<EngineTransitionHistoryItem, "timestamp"> & { timestamp?: string },
): void {
  transitionHistory.unshift({
    ...item,
    timestamp: item.timestamp ?? new Date().toISOString(),
  });

  if (transitionHistory.length > MAX_HISTORY) {
    transitionHistory.length = MAX_HISTORY;
  }
}

export function getEngineTransitionHistory(limit = 25): EngineTransitionHistoryItem[] {
  return transitionHistory.slice(0, Math.max(1, Math.min(MAX_HISTORY, limit)));
}

export function clearEngineTransitionHistoryForTests(): void {
  transitionHistory.length = 0;
}

function effectiveRemainingMs(
  storedRemainingMs: number,
  running: boolean,
  startedAt: Date | string | null,
  nowMs: number,
): number {
  if (!running || !startedAt) return Math.max(0, storedRemainingMs);
  const started = startedAt instanceof Date ? startedAt : new Date(startedAt);
  if (!Number.isFinite(started.getTime())) return Math.max(0, storedRemainingMs);
  return Math.max(0, storedRemainingMs - Math.max(0, nowMs - started.getTime()));
}

export function classifyEngineGame(
  row: EngineTelemetryRow,
  nowMs = Date.now(),
): EngineGameTelemetry {
  const warnings: EngineWarning[] = [];

  const clockRemainingMs = effectiveRemainingMs(
    row.clockRemainingMs,
    row.clockRunning,
    row.clockStartedAt,
    nowMs,
  );

  const intermissionRemainingMs = effectiveRemainingMs(
    row.intermissionRemainingMs,
    row.intermissionRunning,
    row.intermissionStartedAt,
    nowMs,
  );

  if (row.clockRunning && !row.clockStartedAt) {
    warnings.push({
      code: "CLOCK_STARTED_AT_MISSING",
      message: "Game clock is marked running but has no started_at timestamp.",
    });
  }

  if (row.intermissionRunning && !row.intermissionStartedAt) {
    warnings.push({
      code: "INTERMISSION_STARTED_AT_MISSING",
      message: "Intermission is marked running but has no started_at timestamp.",
    });
  }

  if (row.clockRunning && row.intermissionRunning) {
    warnings.push({
      code: "DUAL_CLOCKS_RUNNING",
      message: "Game clock and intermission clock are both marked running.",
    });
  }

  if (row.gamePhase === "INTERMISSION" && row.clockRunning) {
    warnings.push({
      code: "GAME_CLOCK_RUNNING_DURING_INTERMISSION",
      message: "Game clock is running while the game phase is INTERMISSION.",
    });
  }

  if (row.status === "FINAL" && row.gamePhase !== "FINAL") {
    warnings.push({
      code: "FINAL_STATUS_PHASE_MISMATCH",
      message: "Game status is FINAL but game phase is not FINAL.",
    });
  }

  if (row.status !== "FINAL" && row.gamePhase === "FINAL") {
    warnings.push({
      code: "FINAL_PHASE_STATUS_MISMATCH",
      message: "Game phase is FINAL but game status is not FINAL.",
    });
  }

  let state: EngineGameState = warnings.length ? "WARNING" : "HEALTHY";
  let actionRequired: string | null = null;

  if (!warnings.length && row.status === "LIVE") {
    if (
      row.gamePhase === "REGULATION" &&
      clockRemainingMs === 0 &&
      row.period < row.regulationPeriods
    ) {
      state = "TRANSITION_PENDING";
      actionRequired = "Runtime supervisor should begin intermission.";
    } else if (
      row.gamePhase === "INTERMISSION" &&
      intermissionRemainingMs === 0 &&
      row.period < row.regulationPeriods
    ) {
      state = "TRANSITION_PENDING";
      actionRequired = "Runtime supervisor should prepare the next regulation period.";
    } else if (
      row.gamePhase === "REGULATION" &&
      clockRemainingMs === 0 &&
      row.period >= row.regulationPeriods
    ) {
      state = "OPERATOR_REQUIRED";
      actionRequired = "Choose overtime or finish the game.";
    } else if (row.gamePhase === "OVERTIME" && clockRemainingMs === 0) {
      state = "OPERATOR_REQUIRED";
      actionRequired = "Review the overtime result and finish or continue the game.";
    }
  }

  return {
    gameId: row.id,
    organizationId: row.organizationId,
    matchup: `${row.homeTeamName} vs ${row.awayTeamName}`,
    state,
    status: row.status,
    gamePhase: row.gamePhase,
    period: row.period,
    regulationPeriods: row.regulationPeriods,
    clockRemainingMs,
    clockRunning: row.clockRunning && clockRemainingMs > 0,
    intermissionRemainingMs,
    intermissionRunning: row.intermissionRunning && intermissionRemainingMs > 0,
    actionRequired,
    warnings,
  };
}

interface RawGameEngineRow extends RowDataPacket {
  id: number;
  organization_id: number;
  home_name: string;
  away_name: string;
  status: string;
  game_phase: string;
  period: number;
  regulation_periods: number;
  clock_remaining_ms: number;
  clock_running: number;
  clock_started_at: Date | null;
  intermission_remaining_ms: number;
  intermission_running: number;
  intermission_started_at: Date | null;
}

export async function getGameEngineTelemetry(
  organizationId?: number,
  nowMs = Date.now(),
): Promise<{
  status: "healthy" | "attention";
  summary: {
    total: number;
    healthy: number;
    transitionPending: number;
    operatorRequired: number;
    warnings: number;
  };
  games: EngineGameTelemetry[];
  recentTransitions: EngineTransitionHistoryItem[];
}> {
  const params: number[] = [];
  const organizationFilter =
    organizationId === undefined ? "" : "AND g.organization_id = ?";

  if (organizationId !== undefined) params.push(organizationId);

  const [rows] = await pool.execute<RawGameEngineRow[]>(
    `SELECT
       g.id,
       g.organization_id,
       COALESCE(home.name, g.home_external_name, 'Home team') AS home_name,
       COALESCE(away.name, g.away_external_name, 'Away team') AS away_name,
       g.status,
       g.game_phase,
       g.period,
       g.regulation_periods,
       g.clock_remaining_ms,
       g.clock_running,
       g.clock_started_at,
       g.intermission_remaining_ms,
       g.intermission_running,
       g.intermission_started_at
     FROM games g
     LEFT JOIN teams home ON home.id = g.home_team_id
     LEFT JOIN teams away ON away.id = g.away_team_id
     WHERE g.status IN ('SCHEDULED', 'LIVE')
       ${organizationFilter}
     ORDER BY
       CASE WHEN g.status = 'LIVE' THEN 0 ELSE 1 END,
       g.scheduled_start,
       g.id`,
    params,
  );

  const games = rows.map((row) =>
    classifyEngineGame(
      {
        id: Number(row.id),
        organizationId: Number(row.organization_id),
        homeTeamName: String(row.home_name),
        awayTeamName: String(row.away_name),
        status: String(row.status),
        gamePhase: String(row.game_phase),
        period: Number(row.period),
        regulationPeriods: Number(row.regulation_periods),
        clockRemainingMs: Number(row.clock_remaining_ms),
        clockRunning: Boolean(row.clock_running),
        clockStartedAt: row.clock_started_at,
        intermissionRemainingMs: Number(row.intermission_remaining_ms),
        intermissionRunning: Boolean(row.intermission_running),
        intermissionStartedAt: row.intermission_started_at,
      },
      nowMs,
    ),
  );

  const summary = {
    total: games.length,
    healthy: games.filter((game) => game.state === "HEALTHY").length,
    transitionPending: games.filter((game) => game.state === "TRANSITION_PENDING").length,
    operatorRequired: games.filter((game) => game.state === "OPERATOR_REQUIRED").length,
    warnings: games.filter((game) => game.state === "WARNING").length,
  };

  return {
    status:
      summary.operatorRequired > 0 ||
      summary.warnings > 0 ||
      summary.transitionPending > 0
        ? "attention"
        : "healthy",
    summary,
    games,
    recentTransitions: getEngineTransitionHistory(),
  };
}
EOF

cat > "$TELEMETRY_ROUTES" <<'EOF'
import type { FastifyInstance } from "fastify";
import { PERMISSIONS, ROLES, requirePermission } from "../auth/index.js";
import { getGameEngineTelemetry } from "./telemetry.js";

export async function gameEngineTelemetryRoutes(app: FastifyInstance): Promise<void> {
  app.get("/system/game-engine", async (request) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_READ,
    });

    return getGameEngineTelemetry(
      identity.role === ROLES.SYSTEM_ADMIN ? undefined : identity.organizationId,
    );
  });
}
EOF

cat > "$TEST" <<'EOF'
import { beforeEach, describe, expect, it } from "vitest";
import {
  classifyEngineGame,
  clearEngineTransitionHistoryForTests,
  getEngineTransitionHistory,
  recordEngineTransition,
  type EngineTelemetryRow,
} from "../src/modules/games/telemetry.js";

function row(overrides: Partial<EngineTelemetryRow> = {}): EngineTelemetryRow {
  return {
    id: 77,
    organizationId: 8,
    homeTeamName: "Lakers",
    awayTeamName: "Storm",
    status: "LIVE",
    gamePhase: "REGULATION",
    period: 1,
    regulationPeriods: 3,
    clockRemainingMs: 300_000,
    clockRunning: false,
    clockStartedAt: null,
    intermissionRemainingMs: 0,
    intermissionRunning: false,
    intermissionStartedAt: null,
    ...overrides,
  };
}

beforeEach(() => {
  clearEngineTransitionHistoryForTests();
});

describe("game engine telemetry classification", () => {
  it("classifies a normal live game as healthy", () => {
    expect(classifyEngineGame(row()).state).toBe("HEALTHY");
  });

  it("flags an early regulation period at zero as transition pending", () => {
    const result = classifyEngineGame(
      row({
        period: 1,
        clockRemainingMs: 0,
      }),
    );

    expect(result.state).toBe("TRANSITION_PENDING");
    expect(result.actionRequired).toContain("begin intermission");
  });

  it("requires an operator decision at the end of regulation", () => {
    const result = classifyEngineGame(
      row({
        period: 3,
        clockRemainingMs: 0,
      }),
    );

    expect(result.state).toBe("OPERATOR_REQUIRED");
    expect(result.actionRequired).toContain("overtime");
  });

  it("requires an operator decision at overtime expiration", () => {
    const result = classifyEngineGame(
      row({
        gamePhase: "OVERTIME",
        period: 4,
        clockRemainingMs: 0,
      }),
    );

    expect(result.state).toBe("OPERATOR_REQUIRED");
  });

  it("flags a running game clock without started_at", () => {
    const result = classifyEngineGame(
      row({
        clockRunning: true,
        clockStartedAt: null,
      }),
    );

    expect(result.state).toBe("WARNING");
    expect(result.warnings.map((warning) => warning.code)).toContain(
      "CLOCK_STARTED_AT_MISSING",
    );
  });

  it("flags simultaneous game and intermission clocks", () => {
    const now = new Date();

    const result = classifyEngineGame(
      row({
        gamePhase: "INTERMISSION",
        clockRunning: true,
        clockStartedAt: now,
        intermissionRemainingMs: 60_000,
        intermissionRunning: true,
        intermissionStartedAt: now,
      }),
    );

    expect(result.state).toBe("WARNING");
    expect(result.warnings.map((warning) => warning.code)).toContain(
      "DUAL_CLOCKS_RUNNING",
    );
  });
});

describe("game engine transition history", () => {
  it("records newest transitions first", () => {
    recordEngineTransition({
      timestamp: "2026-08-08T10:00:00.000Z",
      source: "runtime-supervisor",
      gameId: 1,
      action: "startIntermission",
      outcome: "applied",
    });

    recordEngineTransition({
      timestamp: "2026-08-08T10:01:00.000Z",
      source: "runtime-supervisor",
      gameId: 2,
      action: "nextPeriod",
      outcome: "applied",
    });

    expect(getEngineTransitionHistory()).toEqual([
      expect.objectContaining({ gameId: 2 }),
      expect.objectContaining({ gameId: 1 }),
    ]);
  });

  it("bounds transition history to 100 entries", () => {
    for (let index = 0; index < 125; index += 1) {
      recordEngineTransition({
        source: "system",
        gameId: index,
        action: "test",
        outcome: "applied",
      });
    }

    expect(getEngineTransitionHistory(100)).toHaveLength(100);
  });
});
EOF

node <<'NODE'
const fs = require("fs");

function read(path) {
  return fs.readFileSync(path, "utf8");
}
function write(path, text) {
  fs.writeFileSync(path, text);
}

const supervisorPath = "apps/api/src/modules/games/runtime-supervisor.ts";
let supervisor = read(supervisorPath);

if (!supervisor.includes('recordEngineTransition')) {
  const importAnchor = 'import { applyGameScoringAction } from "./repository.js";';
  if (!supervisor.includes(importAnchor)) {
    throw new Error("Could not locate repository import in runtime-supervisor.ts");
  }
  supervisor = supervisor.replace(
    importAnchor,
    `${importAnchor}
import { recordEngineTransition } from "./telemetry.js";`,
  );
}

if (!supervisor.includes('action: "startIntermission"') ||
    !supervisor.includes('runtime:period-end:')) {
  throw new Error("2.3 startIntermission supervisor block not found");
}

if (!supervisor.includes('action: "nextPeriod"') ||
    !supervisor.includes('runtime:intermission-complete:')) {
  throw new Error("2.3 nextPeriod supervisor block not found");
}

if (!supervisor.includes('recordEngineTransition({')) {
  supervisor = supervisor.replace(
`    if (result?.applied) intermissionsStarted += 1;`,
`    if (result?.applied) {
      intermissionsStarted += 1;
      recordEngineTransition({
        source: "runtime-supervisor",
        gameId: Number(row.id),
        action: "startIntermission",
        outcome: "applied",
      });
    } else {
      recordEngineTransition({
        source: "runtime-supervisor",
        gameId: Number(row.id),
        action: "startIntermission",
        outcome: "replayed",
      });
    }`,
  );

  supervisor = supervisor.replace(
`    if (result?.applied) periodsPrepared += 1;`,
`    if (result?.applied) {
      periodsPrepared += 1;
      recordEngineTransition({
        source: "runtime-supervisor",
        gameId: Number(row.id),
        action: "nextPeriod",
        outcome: "applied",
      });
    } else {
      recordEngineTransition({
        source: "runtime-supervisor",
        gameId: Number(row.id),
        action: "nextPeriod",
        outcome: "replayed",
      });
    }`,
  );
}

write(supervisorPath, supervisor);

const appPath = "apps/api/src/app.ts";
let app = read(appPath);

if (!app.includes('gameEngineTelemetryRoutes')) {
  const importMarker =
    'import { startGameRuntimeSupervisor } from "./modules/games/runtime-supervisor.js";';
  if (!app.includes(importMarker)) {
    throw new Error("Could not locate 2.3 runtime supervisor import in app.ts");
  }

  app = app.replace(
    importMarker,
`${importMarker}
import { gameEngineTelemetryRoutes } from "./modules/games/telemetry-routes.js";`,
  );
}

if (!app.includes('app.register(gameEngineTelemetryRoutes)')) {
  const registerMarker = 'await app.register(systemRoutes);';
  if (!app.includes(registerMarker)) {
    throw new Error("Could not locate systemRoutes registration in app.ts");
  }

  app = app.replace(
    registerMarker,
`${registerMarker}
  await app.register(gameEngineTelemetryRoutes);`,
  );
}

write(appPath, app);
NODE

echo
echo "============================================="
echo " SportsOS Next - Game Engine 2.4"
echo " Telemetry + Operator Safety"
echo "============================================="
echo
echo "Created:"
echo "  $TELEMETRY"
echo "  $TELEMETRY_ROUTES"
echo "  $TEST"
echo
echo "Modified:"
echo "  $SUPERVISOR"
echo "  $APP"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "New endpoint:"
echo "  GET /system/game-engine"
echo
echo "Telemetry states:"
echo "  HEALTHY"
echo "  TRANSITION_PENDING"
echo "  OPERATOR_REQUIRED"
echo "  WARNING"
echo
echo "Run:"
echo "  npm run typecheck"
echo "  npm test"
