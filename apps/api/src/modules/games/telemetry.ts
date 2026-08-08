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
