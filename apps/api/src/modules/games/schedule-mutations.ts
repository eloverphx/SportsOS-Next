import type { PoolConnection, RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import type { GameInput } from "./schemas.js";
import type { Game } from "./types.js";
import {
  createGameUsingConnection,
  findGameById,
  listGamesByOrganizationUsingConnection,
  listGameTeamOptionsUsingConnection,
  updateGameUsingConnection,
} from "./repository.js";
import {
  evaluateGameInputScheduleAgainstExisting,
  scheduleRelevantFieldsChanged,
  type ScheduleEvaluation,
} from "./schedule-enforcement.js";

export type ScheduleMutationResult =
  | {
      readonly outcome: "blocked";
      readonly scheduleChanged: true;
      readonly evaluation: ScheduleEvaluation;
    }
  | {
      readonly outcome: "written";
      readonly scheduleChanged: boolean;
      readonly evaluation: ScheduleEvaluation;
      readonly game: Game;
    };

export function scheduleMutationOrganizationIds(
  existingOrganizationId: number | null,
  requestedOrganizationId: number,
): number[] {
  return Array.from(
    new Set(
      [existingOrganizationId, requestedOrganizationId].filter(
        (value): value is number => value !== null,
      ),
    ),
  ).sort((left, right) => left - right);
}

async function lockOrganizations(
  connection: PoolConnection,
  organizationIds: readonly number[],
): Promise<void> {
  if (organizationIds.length === 0) {
    throw new Error("Schedule mutation requires an organization lock");
  }

  const placeholders = organizationIds.map(() => "?").join(", ");
  const [rows] = await connection.execute<RowDataPacket[]>(
    `SELECT id
     FROM organizations
     WHERE id IN (${placeholders})
     ORDER BY id
     FOR UPDATE`,
    [...organizationIds],
  );

  if (rows.length !== organizationIds.length) {
    throw new Error("Could not lock every organization for schedule mutation");
  }
}

async function evaluateInsideTransaction(
  connection: PoolConnection,
  gameId: number,
  input: GameInput,
): Promise<ScheduleEvaluation> {
  const [existingGames, teamOptions] = await Promise.all([
    listGamesByOrganizationUsingConnection(connection, input.organizationId),
    listGameTeamOptionsUsingConnection(connection),
  ]);

  return evaluateGameInputScheduleAgainstExisting(
    gameId,
    input,
    existingGames,
    teamOptions,
  );
}

async function loadCommittedGame(id: number): Promise<Game> {
  const game = await findGameById(id);
  if (!game) {
    throw new Error("Game could not be read after schedule transaction committed");
  }
  return game;
}

export async function createGameWithScheduleTransaction(
  input: GameInput,
  allowHardConflict: boolean,
): Promise<ScheduleMutationResult> {
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();
    await lockOrganizations(
      connection,
      scheduleMutationOrganizationIds(null, input.organizationId),
    );

    const evaluation = await evaluateInsideTransaction(connection, 0, input);

    if (evaluation.hardConflict && !allowHardConflict) {
      await connection.rollback();
      return {
        outcome: "blocked",
        scheduleChanged: true,
        evaluation,
      };
    }

    const id = await createGameUsingConnection(connection, input);
    await connection.commit();

    return {
      outcome: "written",
      scheduleChanged: true,
      evaluation,
      game: await loadCommittedGame(id),
    };
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}

export async function updateGameWithScheduleTransaction(
  existing: Game,
  input: GameInput,
  allowHardConflict: boolean,
): Promise<ScheduleMutationResult> {
  const scheduleChanged = scheduleRelevantFieldsChanged(existing, input);
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    if (scheduleChanged) {
      await lockOrganizations(
        connection,
        scheduleMutationOrganizationIds(
          existing.organizationId,
          input.organizationId,
        ),
      );
    }

    const evaluation = scheduleChanged
      ? await evaluateInsideTransaction(connection, existing.id, input)
      : { conflicts: [], hardConflict: false };

    if (evaluation.hardConflict && !allowHardConflict) {
      await connection.rollback();
      return {
        outcome: "blocked",
        scheduleChanged: true,
        evaluation,
      };
    }

    const updated = await updateGameUsingConnection(
      connection,
      existing.id,
      input,
    );

    if (!updated) {
      await connection.rollback();
      throw new Error("Game disappeared during schedule transaction");
    }

    await connection.commit();

    return {
      outcome: "written",
      scheduleChanged,
      evaluation,
      game: await loadCommittedGame(existing.id),
    };
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}
