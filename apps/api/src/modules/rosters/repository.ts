import mysql, { type RowDataPacket } from 'mysql2/promise';
import { pool } from '../../infrastructure/database.js';
import { logoUrl } from '../../lib/media.js';
import type { Player } from '../players/types.js';
import type { RosterInput, RosterUpdateInput } from './schemas.js';
import type { RosterEntry } from './types.js';

const SELECT_ROSTER = `SELECT r.*, s.name AS season_name, t.name AS team_name, t.organization_id,
  p.first_name, p.last_name, p.preferred_name, p.status AS player_status, p.photo_asset_id
  FROM team_rosters r
  JOIN seasons s ON s.id = r.season_id
  JOIN teams t ON t.id = r.team_id
  JOIN players p ON p.id = r.player_id`;

function nullableNumber(value: unknown): number | null {
  return value === null || value === undefined ? null : Number(value);
}

function nullableString(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value);
}

function mapRosterEntry(row: RowDataPacket): RosterEntry {
  const photoAssetId = nullableNumber(row.photo_asset_id);
  return {
    id: Number(row.id),
    seasonId: Number(row.season_id),
    seasonName: String(row.season_name),
    teamId: Number(row.team_id),
    teamName: String(row.team_name),
    organizationId: Number(row.organization_id),
    playerId: Number(row.player_id),
    firstName: String(row.first_name),
    lastName: String(row.last_name),
    preferredName: nullableString(row.preferred_name),
    playerStatus: row.player_status as RosterEntry['playerStatus'],
    photoUrl: logoUrl(photoAssetId),
    jerseyNumber: nullableNumber(row.jersey_number),
    position: row.position as RosterEntry['position'],
    role: row.role as RosterEntry['role'],
    active: Boolean(row.active),
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function mapAvailablePlayer(row: RowDataPacket): Player {
  const photoAssetId = nullableNumber(row.photo_asset_id);
  return {
    id: Number(row.id),
    organizationId: Number(row.organization_id),
    organizationName: String(row.organization_name),
    teamId: nullableNumber(row.team_id),
    teamName: nullableString(row.team_name),
    firstName: String(row.first_name),
    lastName: String(row.last_name),
    preferredName: nullableString(row.preferred_name),
    jerseyNumber: nullableNumber(row.jersey_number),
    position: row.position as Player['position'],
    shoots: row.shoots === null || row.shoots === undefined ? null : row.shoots as Player['shoots'],
    birthDate: null,
    heightCm: nullableNumber(row.height_cm),
    weightKg: nullableNumber(row.weight_kg),
    email: nullableString(row.email),
    phone: nullableString(row.phone),
    photoAssetId,
    photoUrl: logoUrl(photoAssetId),
    status: row.status as Player['status'],
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

export async function listRoster(filters: { seasonId: number; teamId: number; active?: boolean }): Promise<RosterEntry[]> {
  const params: Array<number | boolean> = [filters.seasonId, filters.teamId];
  let activeSql = '';
  if (filters.active !== undefined) {
    activeSql = ' AND r.active = ?';
    params.push(filters.active);
  }
  const [rows] = await pool.execute<RowDataPacket[]>(
    `${SELECT_ROSTER} WHERE r.season_id = ? AND r.team_id = ?${activeSql} ORDER BY r.active DESC, r.jersey_number IS NULL, r.jersey_number, p.last_name, p.first_name`,
    params
  );
  return rows.map(mapRosterEntry);
}

export async function findRosterEntryById(id: number): Promise<RosterEntry | null> {
  const [rows] = await pool.execute<RowDataPacket[]>(`${SELECT_ROSTER} WHERE r.id = ?`, [id]);
  return rows[0] ? mapRosterEntry(rows[0]) : null;
}

export async function listAvailablePlayers(filters: { organizationId: number; seasonId: number; teamId: number; search?: string }): Promise<Player[]> {
  const params: Array<string | number> = [filters.organizationId, filters.seasonId, filters.teamId];
  let searchSql = '';
  const search = filters.search?.trim();
  if (search) {
    searchSql = ' AND (p.first_name LIKE ? OR p.last_name LIKE ? OR p.preferred_name LIKE ? OR CAST(p.jersey_number AS CHAR) LIKE ?)';
    const like = `%${search}%`;
    params.push(like, like, like, like);
  }
  const [rows] = await pool.execute<RowDataPacket[]>(`SELECT p.*, o.name AS organization_name, t.name AS team_name
    FROM players p
    JOIN organizations o ON o.id = p.organization_id
    LEFT JOIN teams t ON t.id = p.team_id
    LEFT JOIN team_rosters r ON r.player_id = p.id AND r.season_id = ? AND r.team_id = ?
    WHERE p.organization_id = ? AND r.id IS NULL${searchSql}
    ORDER BY p.last_name, p.first_name`, [filters.seasonId, filters.teamId, filters.organizationId, ...params.slice(3)]);
  return rows.map(mapAvailablePlayer);
}

export async function createRosterEntry(input: RosterInput): Promise<RosterEntry> {
  const [result] = await pool.execute<mysql.ResultSetHeader>(`INSERT INTO team_rosters
    (season_id, team_id, player_id, jersey_number, position, role, active)
    VALUES (?, ?, ?, ?, ?, ?, ?)`, [
      input.seasonId, input.teamId, input.playerId, input.jerseyNumber ?? null, input.position, input.role, input.active
    ]);
  const entry = await findRosterEntryById(result.insertId);
  if (!entry) throw new Error('Roster entry could not be read after creation');
  return entry;
}

export async function updateRosterEntry(id: number, input: RosterUpdateInput): Promise<RosterEntry | null> {
  const [result] = await pool.execute<mysql.ResultSetHeader>(`UPDATE team_rosters SET
    jersey_number = ?, position = ?, role = ?, active = ? WHERE id = ?`, [
      input.jerseyNumber ?? null, input.position, input.role, input.active, id
    ]);
  if (!result.affectedRows) return null;
  return findRosterEntryById(id);
}

export async function deleteRosterEntry(id: number): Promise<boolean> {
  const [result] = await pool.execute<mysql.ResultSetHeader>('DELETE FROM team_rosters WHERE id = ?', [id]);
  return result.affectedRows > 0;
}

export async function validateRosterRelationships(input: Pick<RosterInput, 'seasonId' | 'teamId' | 'playerId'>): Promise<'season' | 'team' | 'player' | 'organization' | null> {
  const [rows] = await pool.execute<RowDataPacket[]>(`SELECT s.organization_id AS season_org, t.organization_id AS team_org, p.organization_id AS player_org
    FROM seasons s JOIN teams t ON t.id = ? JOIN players p ON p.id = ? WHERE s.id = ?`, [input.teamId, input.playerId, input.seasonId]);
  const row = rows[0];
  if (!row) {
    const [season] = await pool.execute<RowDataPacket[]>('SELECT id FROM seasons WHERE id = ?', [input.seasonId]);
    if (!season[0]) return 'season';
    const [team] = await pool.execute<RowDataPacket[]>('SELECT id FROM teams WHERE id = ?', [input.teamId]);
    if (!team[0]) return 'team';
    return 'player';
  }
  if (Number(row.season_org) !== Number(row.team_org) || Number(row.team_org) !== Number(row.player_org)) return 'organization';
  return null;
}

export async function rosterEntryExists(seasonId: number, teamId: number, playerId: number, excludeId?: number): Promise<boolean> {
  const params: number[] = [seasonId, teamId, playerId];
  let excludeSql = '';
  if (excludeId !== undefined) { excludeSql = ' AND id <> ?'; params.push(excludeId); }
  const [rows] = await pool.execute<RowDataPacket[]>(`SELECT id FROM team_rosters WHERE season_id = ? AND team_id = ? AND player_id = ?${excludeSql}`, params);
  return Boolean(rows[0]);
}

export async function jerseyConflict(seasonId: number, teamId: number, jerseyNumber: number | null | undefined, excludeId?: number): Promise<boolean> {
  if (jerseyNumber === null || jerseyNumber === undefined) return false;
  const params: number[] = [seasonId, teamId, jerseyNumber];
  let excludeSql = '';
  if (excludeId !== undefined) { excludeSql = ' AND id <> ?'; params.push(excludeId); }
  const [rows] = await pool.execute<RowDataPacket[]>(`SELECT id FROM team_rosters
    WHERE season_id = ? AND team_id = ? AND jersey_number = ? AND active = TRUE${excludeSql}`, params);
  return Boolean(rows[0]);
}
