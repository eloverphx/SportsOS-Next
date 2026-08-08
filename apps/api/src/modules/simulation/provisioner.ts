import type { ResultSetHeader, RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import { createGame } from "../games/repository.js";
import {
  generateTournamentPlan,
  normalizeTournamentSimulationConfig,
  type TournamentSimulationConfig,
} from "./tournament-simulator.js";
import {
  createSportsOSSimulationAdapter,
  type SportsOSSimulationGameBinding,
} from "./sportsos-adapter.js";
import { runTournamentSimulation } from "./tournament-runner.js";

export type SimulationRunStatus =
  | "PROVISIONED"
  | "RUNNING"
  | "COMPLETED"
  | "FAILED"
  | "CLEANED";

export interface ProvisionSimulationRunInput {
  runId: string;
  organizationId: number;
  seasonId: number;
  actorUserId: string;
  config?: Partial<TournamentSimulationConfig>;
}

export interface ProvisionedSimulationRun {
  runId: string;
  organizationId: number;
  seasonId: number;
  status: SimulationRunStatus;
  config: TournamentSimulationConfig;
  bindings: SportsOSSimulationGameBinding[];
}

export interface ExecuteSimulationRunResult {
  runId: string;
  status: SimulationRunStatus;
  games: number;
  succeeded: number;
  failed: number;
  processedEvents: number;
  durationMs: number;
}

function normalizeRunId(value: string): string {
  const normalized = value
    .trim()
    .replace(/[^A-Za-z0-9._:-]/g, "-")
    .slice(0, 64);

  if (normalized.length < 4) {
    throw new Error("Simulation runId must contain at least four safe characters");
  }

  return normalized;
}

async function validateSimulationScope(
  organizationId: number,
  seasonId: number,
): Promise<void> {
  const [rows] = await pool.execute<RowDataPacket[]>(
    `SELECT s.id
     FROM seasons s
     WHERE s.id = ?
       AND s.organization_id = ?
     LIMIT 1`,
    [seasonId, organizationId],
  );

  if (!rows[0]) {
    throw new Error(
      "Simulation season was not found in the requested organization",
    );
  }
}

export async function provisionSimulationRun(
  input: ProvisionSimulationRunInput,
): Promise<ProvisionedSimulationRun> {
  const runId = normalizeRunId(input.runId);
  const config = normalizeTournamentSimulationConfig(input.config ?? {});

  if (!Number.isInteger(input.organizationId) || input.organizationId <= 0) {
    throw new Error("Simulation organizationId must be a positive integer");
  }

  if (!Number.isInteger(input.seasonId) || input.seasonId <= 0) {
    throw new Error("Simulation seasonId must be a positive integer");
  }

  await validateSimulationScope(input.organizationId, input.seasonId);

  const [existing] = await pool.execute<RowDataPacket[]>(
    `SELECT id
     FROM simulation_runs
     WHERE id = ?
     LIMIT 1`,
    [runId],
  );

  if (existing[0]) {
    throw new Error(`Simulation run ${runId} already exists`);
  }

  await pool.execute<ResultSetHeader>(
    `INSERT INTO simulation_runs
      (id, organization_id, season_id, seed, config_json, status, created_by)
     VALUES (?, ?, ?, ?, ?, 'PROVISIONED', ?)`,
    [
      runId,
      input.organizationId,
      input.seasonId,
      config.seed,
      JSON.stringify(config),
      Number(input.actorUserId),
    ],
  );

  const plan = generateTournamentPlan(config);
  const bindings: SportsOSSimulationGameBinding[] = [];
  const createdGameIds: number[] = [];

  try {
    for (const simulatedGame of plan.games) {
      const homeTeam = plan.teams.find(
        (team) => team.id === simulatedGame.homeTeamId,
      );
      const awayTeam = plan.teams.find(
        (team) => team.id === simulatedGame.awayTeamId,
      );

      if (!homeTeam || !awayTeam) {
        throw new Error(
          `Simulation plan contains an invalid team binding for game ${simulatedGame.id}`,
        );
      }

      const scheduledStart = new Date(
        Date.now() + simulatedGame.scheduledOffsetMinutes * 60_000,
      ).toISOString();

      const game = await createGame({
        organizationId: input.organizationId,
        seasonId: input.seasonId,
        homeTeamId: null,
        homeExternalName: `[SIM] ${homeTeam.name}`,
        awayTeamId: null,
        awayExternalName: `[SIM] ${awayTeam.name}`,
        scheduledStart,
        timezone: "America/Chicago",
        venue: `[SIM] Rink ${simulatedGame.rink}`,
        status: "SCHEDULED",
        homeScore: 0,
        awayScore: 0,
        regulationPeriods: config.regulationPeriods,
        regulationPeriodLengthMs: config.periodLengthMs,
        intermissionLengthMs: config.intermissionLengthMs,
        overtimeEnabled: true,
        overtimeLengthMs: 300_000,
        notes: `SIMULATION_RUN:${runId};SIMULATED_GAME:${simulatedGame.id}`,
      });

      createdGameIds.push(game.id);

      const binding: SportsOSSimulationGameBinding = {
        simulatedGameId: simulatedGame.id,
        sportsOSGameId: game.id,
        organizationId: input.organizationId,
      };

      bindings.push(binding);

      await pool.execute(
        `INSERT INTO simulation_game_bindings
          (run_id, simulated_game_id, game_id, organization_id)
         VALUES (?, ?, ?, ?)`,
        [
          runId,
          simulatedGame.id,
          game.id,
          input.organizationId,
        ],
      );
    }
  } catch (error) {
    for (const gameId of createdGameIds.reverse()) {
      await pool.execute("DELETE FROM games WHERE id = ?", [gameId]);
    }

    await pool.execute("DELETE FROM simulation_runs WHERE id = ?", [runId]);
    throw error;
  }

  return {
    runId,
    organizationId: input.organizationId,
    seasonId: input.seasonId,
    status: "PROVISIONED",
    config,
    bindings,
  };
}

interface SimulationRunRow extends RowDataPacket {
  id: string;
  organization_id: number;
  season_id: number;
  seed: number;
  config_json: string;
  status: SimulationRunStatus;
}

interface SimulationBindingRow extends RowDataPacket {
  simulated_game_id: number;
  game_id: number;
  organization_id: number;
}

export async function getProvisionedSimulationRun(
  runIdInput: string,
): Promise<ProvisionedSimulationRun | null> {
  const runId = normalizeRunId(runIdInput);

  const [runs] = await pool.execute<SimulationRunRow[]>(
    `SELECT id, organization_id, season_id, seed, config_json, status
     FROM simulation_runs
     WHERE id = ?
     LIMIT 1`,
    [runId],
  );

  const run = runs[0];
  if (!run) return null;

  const [rows] = await pool.execute<SimulationBindingRow[]>(
    `SELECT simulated_game_id, game_id, organization_id
     FROM simulation_game_bindings
     WHERE run_id = ?
     ORDER BY simulated_game_id`,
    [runId],
  );

  return {
    runId: run.id,
    organizationId: Number(run.organization_id),
    seasonId: Number(run.season_id),
    status: run.status,
    config: normalizeTournamentSimulationConfig(
      JSON.parse(run.config_json) as Partial<TournamentSimulationConfig>,
    ),
    bindings: rows.map((row) => ({
      simulatedGameId: Number(row.simulated_game_id),
      sportsOSGameId: Number(row.game_id),
      organizationId: Number(row.organization_id),
    })),
  };
}

export async function executeProvisionedSimulationRun(
  runIdInput: string,
  actorUserId: string,
  concurrency?: number,
): Promise<ExecuteSimulationRunResult> {
  const run = await getProvisionedSimulationRun(runIdInput);

  if (!run) {
    throw new Error("Simulation run not found");
  }

  if (run.status !== "PROVISIONED" && run.status !== "FAILED") {
    throw new Error(
      `Simulation run ${run.runId} cannot execute from status ${run.status}`,
    );
  }

  await pool.execute(
    `UPDATE simulation_runs
     SET status = 'RUNNING', started_at = CURRENT_TIMESTAMP(3), completed_at = NULL
     WHERE id = ?`,
    [run.runId],
  );

  try {
    const adapter = createSportsOSSimulationAdapter({
      bindings: run.bindings,
      actorUserId,
      runId: run.runId,
    });

    const result = await runTournamentSimulation(
      adapter,
      run.config,
      {
        concurrency: concurrency ?? run.config.rinkCount,
        failFast: false,
      },
    );

    const status: SimulationRunStatus =
      result.failed === 0 ? "COMPLETED" : "FAILED";

    await pool.execute(
      `UPDATE simulation_runs
       SET status = ?, completed_at = CURRENT_TIMESTAMP(3)
       WHERE id = ?`,
      [status, run.runId],
    );

    return {
      runId: run.runId,
      status,
      games: result.games,
      succeeded: result.succeeded,
      failed: result.failed,
      processedEvents: result.processedEvents,
      durationMs: result.durationMs,
    };
  } catch (error) {
    await pool.execute(
      `UPDATE simulation_runs
       SET status = 'FAILED', completed_at = CURRENT_TIMESTAMP(3)
       WHERE id = ?`,
      [run.runId],
    );
    throw error;
  }
}

export async function cleanupSimulationRun(
  runIdInput: string,
): Promise<{ runId: string; deletedGames: number }> {
  const runId = normalizeRunId(runIdInput);

  const [rows] = await pool.execute<SimulationBindingRow[]>(
    `SELECT simulated_game_id, game_id, organization_id
     FROM simulation_game_bindings
     WHERE run_id = ?
     ORDER BY simulated_game_id`,
    [runId],
  );

  if (rows.length === 0) {
    const [existing] = await pool.execute<RowDataPacket[]>(
      "SELECT id FROM simulation_runs WHERE id = ? LIMIT 1",
      [runId],
    );

    if (!existing[0]) {
      throw new Error("Simulation run not found");
    }
  }

  let deletedGames = 0;

  for (const row of rows) {
    const [result] = await pool.execute<ResultSetHeader>(
      "DELETE FROM games WHERE id = ?",
      [Number(row.game_id)],
    );
    deletedGames += result.affectedRows;
  }

  await pool.execute(
    `UPDATE simulation_runs
     SET status = 'CLEANED', cleaned_at = CURRENT_TIMESTAMP(3)
     WHERE id = ?`,
    [runId],
  );

  return { runId, deletedGames };
}
