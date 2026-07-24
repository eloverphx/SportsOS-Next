import mysql, { type RowDataPacket } from 'mysql2/promise';
import { pool } from '../../infrastructure/database.js';
import { logoUrl } from '../../lib/media.js';
import type { Player } from './types.js';
import type { PlayerInput } from './schemas.js';

const SELECT_PLAYER = `SELECT p.*, o.name AS organization_name, t.name AS team_name
  FROM players p
  JOIN organizations o ON o.id = p.organization_id
  LEFT JOIN teams t ON t.id = p.team_id`;

function formatDateOnly(value: unknown): string | null {
  if (!value) return null;
  if (value instanceof Date) {
    const year = value.getFullYear();
    const month = String(value.getMonth() + 1).padStart(2, '0');
    const day = String(value.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  const text = String(value);
  const isoDate = text.match(/^(\d{4}-\d{2}-\d{2})/);
  if (isoDate) return isoDate[1];

  const parsed = new Date(text);
  if (Number.isNaN(parsed.getTime())) return null;
  const year = parsed.getFullYear();
  const month = String(parsed.getMonth() + 1).padStart(2, '0');
  const day = String(parsed.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function mapPlayer(row: RowDataPacket): Player {
  return {
    id: Number(row.id),
    organizationId: Number(row.organization_id),
    organizationName: String(row.organization_name),
    teamId: row.team_id ? Number(row.team_id) : null,
    teamName: row.team_name ? String(row.team_name) : null,
    firstName: String(row.first_name),
    lastName: String(row.last_name),
    preferredName: row.preferred_name ? String(row.preferred_name) : null,
    jerseyNumber: row.jersey_number === null ? null : Number(row.jersey_number),
    position: row.position,
    shoots: row.shoots,
    birthDate: formatDateOnly(row.birth_date),
    heightCm: row.height_cm === null ? null : Number(row.height_cm),
    weightKg: row.weight_kg === null ? null : Number(row.weight_kg),
    email: row.email ? String(row.email) : null,
    phone: row.phone ? String(row.phone) : null,
    photoAssetId: row.photo_asset_id ? Number(row.photo_asset_id) : null,
    photoUrl: logoUrl(row.photo_asset_id ? Number(row.photo_asset_id) : null),
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

export async function listPlayers(filters: {
  organizationId?: number; teamId?: number; position?: string; status?: string; search?: string;
}): Promise<Player[]> {
  const conditions: string[] = [];
  const params: Array<string | number> = [];
  if (filters.organizationId) { conditions.push('p.organization_id = ?'); params.push(filters.organizationId); }
  if (filters.teamId) { conditions.push('p.team_id = ?'); params.push(filters.teamId); }
  if (filters.position) { conditions.push('p.position = ?'); params.push(filters.position); }
  if (filters.status) { conditions.push('p.status = ?'); params.push(filters.status); }
  if (filters.search) {
    conditions.push(`(p.first_name LIKE ? OR p.last_name LIKE ? OR p.preferred_name LIKE ? OR CAST(p.jersey_number AS CHAR) LIKE ?)`);
    const search = `%${filters.search}%`;
    params.push(search, search, search, search);
  }
  const where = conditions.length ? ` WHERE ${conditions.join(' AND ')}` : '';
  const [rows] = await pool.execute<RowDataPacket[]>(`${SELECT_PLAYER}${where} ORDER BY p.last_name, p.first_name`, params);
  return rows.map(mapPlayer);
}

export async function findPlayerById(id: number): Promise<Player | null> {
  const [rows] = await pool.execute<RowDataPacket[]>(`${SELECT_PLAYER} WHERE p.id = ?`, [id]);
  return rows[0] ? mapPlayer(rows[0]) : null;
}

export async function createPlayer(input: PlayerInput): Promise<Player> {
  const [result] = await pool.execute<mysql.ResultSetHeader>(`INSERT INTO players
    (organization_id, team_id, first_name, last_name, preferred_name, jersey_number, position, shoots, birth_date, height_cm, weight_kg, email, phone, photo_asset_id, status)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`, [
      input.organizationId, input.teamId ?? null, input.firstName, input.lastName, input.preferredName ?? null,
      input.jerseyNumber ?? null, input.position, input.shoots ?? null, input.birthDate ?? null,
      input.heightCm ?? null, input.weightKg ?? null, input.email ?? null, input.phone ?? null,
      input.photoAssetId ?? null, input.status
    ]);
  const player = await findPlayerById(result.insertId);
  if (!player) throw new Error('Player could not be read after creation');
  return player;
}

export async function updatePlayer(id: number, input: PlayerInput): Promise<Player | null> {
  const [result] = await pool.execute<mysql.ResultSetHeader>(`UPDATE players SET
    organization_id=?, team_id=?, first_name=?, last_name=?, preferred_name=?, jersey_number=?, position=?, shoots=?, birth_date=?, height_cm=?, weight_kg=?, email=?, phone=?, photo_asset_id=?, status=?
    WHERE id=?`, [
      input.organizationId, input.teamId ?? null, input.firstName, input.lastName, input.preferredName ?? null,
      input.jerseyNumber ?? null, input.position, input.shoots ?? null, input.birthDate ?? null,
      input.heightCm ?? null, input.weightKg ?? null, input.email ?? null, input.phone ?? null,
      input.photoAssetId ?? null, input.status, id
    ]);
  if (!result.affectedRows) return null;
  return findPlayerById(id);
}

export async function deletePlayer(id: number): Promise<boolean> {
  const [result] = await pool.execute<mysql.ResultSetHeader>('DELETE FROM players WHERE id = ?', [id]);
  return result.affectedRows > 0;
}

export async function validatePlayerRelationships(input: PlayerInput): Promise<'organization' | 'team' | null> {
  const [organizations] = await pool.execute<RowDataPacket[]>('SELECT id FROM organizations WHERE id=?', [input.organizationId]);
  if (!organizations[0]) return 'organization';
  if (input.teamId) {
    const [teams] = await pool.execute<RowDataPacket[]>('SELECT id FROM teams WHERE id=? AND organization_id=?', [input.teamId, input.organizationId]);
    if (!teams[0]) return 'team';
  }
  return null;
}
