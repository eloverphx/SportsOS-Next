import mysql, { type RowDataPacket } from 'mysql2/promise';
import { pool } from '../../infrastructure/database.js';
import type { SeasonInput } from './schemas.js';
import type { Season } from './types.js';

const SELECT_SEASON = `SELECT s.*, o.name AS organization_name
  FROM seasons s
  JOIN organizations o ON o.id = s.organization_id`;

function nullableDate(value: unknown): string | null {
  if (value === null || value === undefined || value === '') return null;
  if (value instanceof Date) {
    const year = value.getFullYear();
    const month = String(value.getMonth() + 1).padStart(2, '0');
    const day = String(value.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
  const match = String(value).match(/^(\d{4}-\d{2}-\d{2})/);
  return match?.[1] ?? null;
}

function mapSeason(row: RowDataPacket): Season {
  return {
    id: Number(row.id),
    organizationId: Number(row.organization_id),
    organizationName: String(row.organization_name),
    name: String(row.name),
    startDate: nullableDate(row.start_date),
    endDate: nullableDate(row.end_date),
    active: Boolean(row.active),
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

export async function listSeasons(filters: { organizationId?: number; active?: boolean; search?: string }): Promise<Season[]> {
  const conditions: string[] = [];
  const params: Array<string | number | boolean> = [];
  if (filters.organizationId) {
    conditions.push('s.organization_id = ?');
    params.push(filters.organizationId);
  }
  if (filters.active !== undefined) {
    conditions.push('s.active = ?');
    params.push(filters.active);
  }
  const search = filters.search?.trim();
  if (search) {
    conditions.push('(s.name LIKE ? OR o.name LIKE ?)');
    const like = `%${search}%`;
    params.push(like, like);
  }
  const where = conditions.length ? ` WHERE ${conditions.join(' AND ')}` : '';
  const [rows] = await pool.execute<RowDataPacket[]>(`${SELECT_SEASON}${where} ORDER BY s.start_date DESC, s.name`, params);
  return rows.map(mapSeason);
}

export async function findSeasonById(id: number): Promise<Season | null> {
  const [rows] = await pool.execute<RowDataPacket[]>(`${SELECT_SEASON} WHERE s.id = ?`, [id]);
  return rows[0] ? mapSeason(rows[0]) : null;
}

export async function createSeason(input: SeasonInput): Promise<Season> {
  const [result] = await pool.execute<mysql.ResultSetHeader>(
    'INSERT INTO seasons (organization_id, name, start_date, end_date, active) VALUES (?, ?, ?, ?, ?)',
    [input.organizationId, input.name, input.startDate, input.endDate, input.active]
  );
  const season = await findSeasonById(result.insertId);
  if (!season) throw new Error('Season could not be read after creation');
  return season;
}

export async function updateSeason(id: number, input: SeasonInput): Promise<Season | null> {
  const [result] = await pool.execute<mysql.ResultSetHeader>(
    'UPDATE seasons SET organization_id = ?, name = ?, start_date = ?, end_date = ?, active = ? WHERE id = ?',
    [input.organizationId, input.name, input.startDate, input.endDate, input.active, id]
  );
  if (!result.affectedRows) return null;
  return findSeasonById(id);
}

export async function deleteSeason(id: number): Promise<boolean> {
  const [result] = await pool.execute<mysql.ResultSetHeader>('DELETE FROM seasons WHERE id = ?', [id]);
  return result.affectedRows > 0;
}

export async function organizationExists(organizationId: number): Promise<boolean> {
  const [rows] = await pool.execute<RowDataPacket[]>('SELECT id FROM organizations WHERE id = ?', [organizationId]);
  return Boolean(rows[0]);
}
