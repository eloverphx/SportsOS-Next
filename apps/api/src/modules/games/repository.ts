import mysql, { type RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import type { GameInput } from "./schemas.js";
import type { Game, GameStatus } from "./types.js";

const SELECT_GAME = `SELECT
  g.*,
  o.name AS organization_name,
  s.name AS season_name,
  home.name AS home_team_name,
  away.name AS away_team_name
FROM games g
JOIN organizations o ON o.id = g.organization_id
JOIN seasons s ON s.id = g.season_id
JOIN teams home ON home.id = g.home_team_id
JOIN teams away ON away.id = g.away_team_id`;

function mapGame(row: RowDataPacket): Game {
  return {
    id: Number(row.id),
    organizationId: Number(row.organization_id),
    organizationName: String(row.organization_name),
    seasonId: Number(row.season_id),
    seasonName: String(row.season_name),
    homeTeamId: Number(row.home_team_id),
    homeTeamName: String(row.home_team_name),
    awayTeamId: Number(row.away_team_id),
    awayTeamName: String(row.away_team_name),
    scheduledStart:
      row.scheduled_start instanceof Date
        ? row.scheduled_start.toISOString()
        : String(row.scheduled_start),
    timezone: String(row.timezone),
    venue: row.venue == null ? null : String(row.venue),
    status: String(row.status) as GameStatus,
    homeScore: Number(row.home_score),
    awayScore: Number(row.away_score),
    notes: row.notes == null ? null : String(row.notes),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export interface GameFilters {
  organizationId?: number;
  seasonId?: number;
  teamId?: number;
  status?: GameStatus;
  search?: string;
}

export async function listGames(filters: GameFilters): Promise<Game[]> {
  const conditions: string[] = [];
  const params: Array<string | number> = [];

  if (filters.organizationId !== undefined) {
    conditions.push("g.organization_id = ?");
    params.push(filters.organizationId);
  }

  if (filters.seasonId !== undefined) {
    conditions.push("g.season_id = ?");
    params.push(filters.seasonId);
  }

  if (filters.teamId !== undefined) {
    conditions.push("(g.home_team_id = ? OR g.away_team_id = ?)");
    params.push(filters.teamId, filters.teamId);
  }

  if (filters.status !== undefined) {
    conditions.push("g.status = ?");
    params.push(filters.status);
  }

  const search = filters.search?.trim();

  if (search) {
    conditions.push("(home.name LIKE ? OR away.name LIKE ? OR g.venue LIKE ?)");
    const like = `%${search}%`;
    params.push(like, like, like);
  }

  const where = conditions.length ? ` WHERE ${conditions.join(" AND ")}` : "";

  const [rows] = await pool.execute<RowDataPacket[]>(
    `${SELECT_GAME}${where}
     ORDER BY g.scheduled_start DESC, g.id DESC`,
    params,
  );

  return rows.map(mapGame);
}

export async function findGameById(id: number): Promise<Game | null> {
  const [rows] = await pool.execute<RowDataPacket[]>(`${SELECT_GAME} WHERE g.id = ? LIMIT 1`, [id]);

  return rows[0] ? mapGame(rows[0]) : null;
}

export async function validateGameRelationships(
  input: Pick<GameInput, "organizationId" | "seasonId" | "homeTeamId" | "awayTeamId">,
): Promise<"organization" | "season" | "homeTeam" | "awayTeam" | null> {
  const [organizations] = await pool.execute<RowDataPacket[]>(
    "SELECT id FROM organizations WHERE id = ? LIMIT 1",
    [input.organizationId],
  );

  if (!organizations[0]) {
    return "organization";
  }

  const [seasons] = await pool.execute<RowDataPacket[]>(
    `SELECT id
     FROM seasons
     WHERE id = ? AND organization_id = ?
     LIMIT 1`,
    [input.seasonId, input.organizationId],
  );

  if (!seasons[0]) {
    return "season";
  }

  const [homeTeams] = await pool.execute<RowDataPacket[]>(
    `SELECT id
     FROM teams
     WHERE id = ? AND organization_id = ?
     LIMIT 1`,
    [input.homeTeamId, input.organizationId],
  );

  if (!homeTeams[0]) {
    return "homeTeam";
  }

  const [awayTeams] = await pool.execute<RowDataPacket[]>(
    `SELECT id
     FROM teams
     WHERE id = ? AND organization_id = ?
     LIMIT 1`,
    [input.awayTeamId, input.organizationId],
  );

  if (!awayTeams[0]) {
    return "awayTeam";
  }

  return null;
}

export async function createGame(input: GameInput): Promise<Game> {
  const [result] = await pool.execute<mysql.ResultSetHeader>(
    `INSERT INTO games (
         organization_id,
         season_id,
         home_team_id,
         away_team_id,
         scheduled_start,
         timezone,
         venue,
         status,
         home_score,
         away_score,
         notes
       )
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      input.organizationId,
      input.seasonId,
      input.homeTeamId,
      input.awayTeamId,
      new Date(input.scheduledStart),
      input.timezone,
      input.venue,
      input.status,
      input.homeScore,
      input.awayScore,
      input.notes,
    ],
  );

  const game = await findGameById(result.insertId);

  if (!game) {
    throw new Error("Game could not be read after creation");
  }

  return game;
}

export async function updateGame(id: number, input: GameInput): Promise<Game | null> {
  const [result] = await pool.execute<mysql.ResultSetHeader>(
    `UPDATE games SET
         organization_id = ?,
         season_id = ?,
         home_team_id = ?,
         away_team_id = ?,
         scheduled_start = ?,
         timezone = ?,
         venue = ?,
         status = ?,
         home_score = ?,
         away_score = ?,
         notes = ?
       WHERE id = ?`,
    [
      input.organizationId,
      input.seasonId,
      input.homeTeamId,
      input.awayTeamId,
      new Date(input.scheduledStart),
      input.timezone,
      input.venue,
      input.status,
      input.homeScore,
      input.awayScore,
      input.notes,
      id,
    ],
  );

  if (!result.affectedRows) {
    return null;
  }

  return findGameById(id);
}

export async function deleteGame(id: number): Promise<boolean> {
  const [result] = await pool.execute<mysql.ResultSetHeader>("DELETE FROM games WHERE id = ?", [
    id,
  ]);

  return result.affectedRows > 0;
}
