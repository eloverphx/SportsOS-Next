import mysql, { type RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import type { GameEventInput } from "./schemas.js";
import type { GameEvent, GameEventPlayerOption } from "./types.js";
import {
  clearEarliestEligibleMinorOnGoal,
  clearPenaltyForVoidedEvent,
  createPenaltyClock,
} from "../penalties/repository.js";

const SELECT_EVENT = `SELECT ge.*,
  p.first_name player_first_name, p.last_name player_last_name,
  p.preferred_name player_preferred_name, p.jersey_number player_jersey_number,
  a1.first_name assist1_first_name, a1.last_name assist1_last_name,
  a1.preferred_name assist1_preferred_name,
  a2.first_name assist2_first_name, a2.last_name assist2_last_name,
  a2.preferred_name assist2_preferred_name
FROM game_events ge
LEFT JOIN players p ON p.id = ge.player_id
LEFT JOIN players a1 ON a1.id = ge.assist1_player_id
LEFT JOIN players a2 ON a2.id = ge.assist2_player_id`;

function name(preferred: unknown, first: unknown, last: unknown): string | null {
  if (first == null) return null;
  return `${preferred || first} ${last || ""}`.trim();
}
function iso(value: unknown): string {
  return (value instanceof Date ? value : new Date(String(value))).toISOString();
}
function mapEvent(row: RowDataPacket): GameEvent {
  return {
    id: Number(row.id),
    gameId: Number(row.game_id),
    organizationId: Number(row.organization_id),
    type: row.type,
    side: row.side,
    period: Number(row.period),
    clockRemainingMs: Number(row.clock_remaining_ms),
    playerId: row.player_id == null ? null : Number(row.player_id),
    playerName: name(row.player_preferred_name, row.player_first_name, row.player_last_name),
    playerJerseyNumber: row.player_jersey_number == null ? null : Number(row.player_jersey_number),
    assist1PlayerId: row.assist1_player_id == null ? null : Number(row.assist1_player_id),
    assist1PlayerName: name(
      row.assist1_preferred_name,
      row.assist1_first_name,
      row.assist1_last_name,
    ),
    assist2PlayerId: row.assist2_player_id == null ? null : Number(row.assist2_player_id),
    assist2PlayerName: name(
      row.assist2_preferred_name,
      row.assist2_first_name,
      row.assist2_last_name,
    ),
    penaltyCode: row.penalty_code == null ? null : String(row.penalty_code),
    penaltyMinutes: row.penalty_minutes == null ? null : Number(row.penalty_minutes),
    notes: row.notes == null ? null : String(row.notes),
    voidedAt: row.voided_at == null ? null : iso(row.voided_at),
    createdAt: iso(row.created_at),
  };
}

export async function listGameEvents(gameId: number): Promise<GameEvent[]> {
  const [rows] = await pool.execute<RowDataPacket[]>(
    `${SELECT_EVENT} WHERE ge.game_id = ? ORDER BY ge.id DESC LIMIT 100`,
    [gameId],
  );
  return rows.map(mapEvent);
}

export async function listGameEventPlayers(gameId: number): Promise<GameEventPlayerOption[]> {
  const [rows] = await pool.execute<RowDataPacket[]>(
    `SELECT r.player_id id, r.team_id, p.first_name, p.last_name,
      p.preferred_name, r.jersey_number
     FROM games g
     JOIN team_rosters r ON r.season_id = g.season_id
      AND r.active = TRUE
      AND (r.team_id = g.home_team_id OR r.team_id = g.away_team_id)
     JOIN players p ON p.id = r.player_id
     WHERE g.id = ?
     ORDER BY r.team_id, r.jersey_number IS NULL, r.jersey_number, p.last_name`,
    [gameId],
  );
  return rows.map((row) => ({
    id: Number(row.id),
    teamId: Number(row.team_id),
    firstName: String(row.first_name),
    lastName: String(row.last_name),
    preferredName: row.preferred_name == null ? null : String(row.preferred_name),
    jerseyNumber: row.jersey_number == null ? null : Number(row.jersey_number),
  }));
}

export async function createGameEvent(gameId: number, input: GameEventInput, userId: string) {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const [games] = await connection.execute<RowDataPacket[]>(
      `SELECT * FROM games WHERE id = ? FOR UPDATE`,
      [gameId],
    );
    const game = games[0];
    if (!game) throw new Error("Game not found");

    const teamId = input.side === "home" ? game.home_team_id : game.away_team_id;
    const ids =
      input.type === "GOAL"
        ? [input.playerId, input.assist1PlayerId, input.assist2PlayerId]
        : [input.playerId];

    for (const playerId of ids) {
      if (playerId == null) continue;
      if (teamId == null) throw new Error("External teams cannot use roster players");
      const [valid] = await connection.execute<RowDataPacket[]>(
        `SELECT r.id FROM team_rosters r
         WHERE r.season_id = ? AND r.team_id = ? AND r.player_id = ?
           AND r.active = TRUE LIMIT 1`,
        [game.season_id, teamId, playerId],
      );
      if (!valid[0]) throw new Error("Selected player is not on the active roster");
    }

    let homeScore = Number(game.home_score);
    let awayScore = Number(game.away_score);
    if (input.type === "GOAL") {
      if (input.side === "home") homeScore += 1;
      else awayScore += 1;
      await connection.execute("UPDATE games SET home_score = ?, away_score = ? WHERE id = ?", [
        homeScore,
        awayScore,
        gameId,
      ]);
    }

    let remaining = Number(game.clock_remaining_ms);
    if (game.clock_running && game.clock_started_at) {
      remaining = Math.max(0, remaining - (Date.now() - new Date(game.clock_started_at).getTime()));
    }

    const [result] = await connection.execute<mysql.ResultSetHeader>(
      `INSERT INTO game_events (
        game_id, organization_id, type, side, period, clock_remaining_ms,
        player_id, assist1_player_id, assist2_player_id,
        penalty_code, penalty_minutes, notes, created_by_user_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        gameId,
        game.organization_id,
        input.type,
        input.side,
        game.period,
        remaining,
        input.playerId,
        input.type === "GOAL" ? input.assist1PlayerId : null,
        input.type === "GOAL" ? input.assist2PlayerId : null,
        input.type === "PENALTY" ? input.penaltyCode : null,
        input.type === "PENALTY" ? input.penaltyMinutes : null,
        input.notes,
        Number(userId),
      ],
    );
    if (input.type === "PENALTY") {
      await createPenaltyClock(connection, {
        gameEventId: result.insertId,
        gameId,
        side: input.side,
        durationMs: Math.round(input.penaltyMinutes * 60_000),
        gameClockRunning: Boolean(game.clock_running),
      });
    }

    if (input.type === "GOAL") {
      await clearEarliestEligibleMinorOnGoal(connection, gameId, input.side);
    }

    await connection.commit();

    const [rows] = await pool.execute<RowDataPacket[]>(`${SELECT_EVENT} WHERE ge.id = ? LIMIT 1`, [
      result.insertId,
    ]);
    return { event: mapEvent(rows[0]!), homeScore, awayScore };
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}

export async function voidGameEvent(gameId: number, eventId: number, userId: string) {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const [events] = await connection.execute<RowDataPacket[]>(
      "SELECT * FROM game_events WHERE id = ? AND game_id = ? FOR UPDATE",
      [eventId, gameId],
    );
    const event = events[0];
    if (!event) throw new Error("Game event not found");
    if (event.voided_at) throw new Error("Game event already voided");

    const [games] = await connection.execute<RowDataPacket[]>(
      "SELECT home_score, away_score FROM games WHERE id = ? FOR UPDATE",
      [gameId],
    );
    const game = games[0]!;
    let homeScore = Number(game.home_score);
    let awayScore = Number(game.away_score);
    if (event.type === "GOAL") {
      if (event.side === "home") homeScore = Math.max(0, homeScore - 1);
      else awayScore = Math.max(0, awayScore - 1);
      await connection.execute("UPDATE games SET home_score = ?, away_score = ? WHERE id = ?", [
        homeScore,
        awayScore,
        gameId,
      ]);
    }
    if (event.type === "PENALTY") {
      await clearPenaltyForVoidedEvent(connection, eventId);
    }

    await connection.execute(
      `UPDATE game_events SET voided_at = CURRENT_TIMESTAMP(3),
       voided_by_user_id = ? WHERE id = ?`,
      [Number(userId), eventId],
    );
    await connection.commit();
    const [rows] = await pool.execute<RowDataPacket[]>(`${SELECT_EVENT} WHERE ge.id = ? LIMIT 1`, [
      eventId,
    ]);
    return { event: mapEvent(rows[0]!), homeScore, awayScore };
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}
