import type { RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import {
  cleanupSimulationRun,
  executeProvisionedSimulationRun,
  getProvisionedSimulationRun,
  provisionSimulationRun,
  type ProvisionSimulationRunInput,
} from "./provisioner.js";

export interface SimulationQualificationOptions
  extends ProvisionSimulationRunInput {
  concurrency?: number;
  cleanupOnPass?: boolean;
}

export interface SimulationQualificationGameResult {
  simulatedGameId: number;
  gameId: number;
  status: string;
  homeScore: number;
  awayScore: number;
  events: number;
  goals: number;
  penalties: number;
  passed: boolean;
  failures: string[];
}

export interface SimulationQualificationReport {
  runId: string;
  startedAt: string;
  finishedAt: string;
  durationMs: number;
  overall: "PASS" | "FAIL";
  execution: {
    status: string;
    games: number;
    succeeded: number;
    failed: number;
    processedEvents: number;
    durationMs: number;
  };
  verification: {
    gamesExpected: number;
    gamesVerified: number;
    gamesPassed: number;
    gamesFailed: number;
    events: number;
    goals: number;
    penalties: number;
  };
  games: SimulationQualificationGameResult[];
  cleanup: {
    requested: boolean;
    performed: boolean;
    deletedGames: number;
  };
}

interface VerificationRow extends RowDataPacket {
  game_id: number;
  simulated_game_id: number;
  status: string;
  home_score: number;
  away_score: number;
  event_count: number;
  goal_count: number;
  penalty_count: number;
}

async function verifySimulationRun(
  runId: string,
): Promise<SimulationQualificationGameResult[]> {
  const [rows] = await pool.execute<VerificationRow[]>(
    `SELECT
       b.game_id,
       b.simulated_game_id,
       g.status,
       g.home_score,
       g.away_score,
       COUNT(ge.id) AS event_count,
       SUM(CASE WHEN ge.type = 'GOAL' AND ge.voided_at IS NULL THEN 1 ELSE 0 END) AS goal_count,
       SUM(CASE WHEN ge.type = 'PENALTY' AND ge.voided_at IS NULL THEN 1 ELSE 0 END) AS penalty_count
     FROM simulation_game_bindings b
     JOIN games g ON g.id = b.game_id
     LEFT JOIN game_events ge ON ge.game_id = g.id
     WHERE b.run_id = ?
     GROUP BY
       b.game_id,
       b.simulated_game_id,
       g.status,
       g.home_score,
       g.away_score
     ORDER BY b.simulated_game_id`,
    [runId],
  );

  return rows.map((row) => {
    const failures: string[] = [];
    const homeScore = Number(row.home_score);
    const awayScore = Number(row.away_score);
    const goals = Number(row.goal_count ?? 0);
    const penalties = Number(row.penalty_count ?? 0);
    const events = Number(row.event_count ?? 0);
    const status = String(row.status);

    if (status !== "FINAL") {
      failures.push(`Expected FINAL status, found ${status}`);
    }

    if (homeScore + awayScore !== goals) {
      failures.push(
        `Score/event mismatch: score total ${homeScore + awayScore}, goal events ${goals}`,
      );
    }

    if (events < goals + penalties) {
      failures.push(
        `Event count ${events} is lower than goals + penalties ${goals + penalties}`,
      );
    }

    return {
      simulatedGameId: Number(row.simulated_game_id),
      gameId: Number(row.game_id),
      status,
      homeScore,
      awayScore,
      events,
      goals,
      penalties,
      passed: failures.length === 0,
      failures,
    };
  });
}

export async function qualifySimulationRun(
  options: SimulationQualificationOptions,
): Promise<SimulationQualificationReport> {
  const started = Date.now();

  const provisioned = await provisionSimulationRun(options);

  const execution = await executeProvisionedSimulationRun(
    provisioned.runId,
    options.actorUserId,
    options.concurrency,
  );

  const games = await verifySimulationRun(provisioned.runId);

  const expectedGames = provisioned.bindings.length;
  const gamesPassed = games.filter((game) => game.passed).length;
  const gamesFailed = games.length - gamesPassed;

  let overall: "PASS" | "FAIL" = "PASS";

  if (
    execution.status !== "COMPLETED" ||
    execution.failed !== 0 ||
    execution.succeeded !== expectedGames ||
    games.length !== expectedGames ||
    gamesFailed !== 0
  ) {
    overall = "FAIL";
  }

  let deletedGames = 0;
  let cleanupPerformed = false;

  if (overall === "PASS" && options.cleanupOnPass) {
    const cleanup = await cleanupSimulationRun(provisioned.runId);
    deletedGames = cleanup.deletedGames;
    cleanupPerformed = true;

    if (deletedGames !== expectedGames) {
      overall = "FAIL";
    }
  }

  const finished = Date.now();

  return {
    runId: provisioned.runId,
    startedAt: new Date(started).toISOString(),
    finishedAt: new Date(finished).toISOString(),
    durationMs: finished - started,
    overall,
    execution: {
      status: execution.status,
      games: execution.games,
      succeeded: execution.succeeded,
      failed: execution.failed,
      processedEvents: execution.processedEvents,
      durationMs: execution.durationMs,
    },
    verification: {
      gamesExpected: expectedGames,
      gamesVerified: games.length,
      gamesPassed,
      gamesFailed,
      events: games.reduce((sum, game) => sum + game.events, 0),
      goals: games.reduce((sum, game) => sum + game.goals, 0),
      penalties: games.reduce((sum, game) => sum + game.penalties, 0),
    },
    games,
    cleanup: {
      requested: Boolean(options.cleanupOnPass),
      performed: cleanupPerformed,
      deletedGames,
    },
  };
}
