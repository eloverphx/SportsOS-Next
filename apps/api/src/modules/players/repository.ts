import mysql, { type RowDataPacket } from 'mysql2/promise';
import { pool } from '../../infrastructure/database.js';
import { logoUrl } from '../../lib/media.js';
import type { Player, PlayerPosition, PlayerShoots, PlayerStatus } from './types.js';
import type { PlayerInput } from './schemas.js';

const SELECT_PLAYER = `SELECT p.*, o.name AS organization_name, t.name AS team_name
  FROM players p
  JOIN organizations o ON o.id = p.organization_id
  LEFT JOIN teams t ON t.id = p.team_id`;

export interface PlayerFilters {
  organizationId?: number;
  teamId?: number;
  position?: PlayerPosition;
  status?: PlayerStatus;
  search?: string;
}

function nullableString(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value);
}

function nullableNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function requiredString(value: unknown, field: string): string {
  if (value === null || value === undefined) {
    throw new Error(`Missing required player field: ${field}`);
  }
  return String(value);
}

function requiredNumber(value: unknown, field: string): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    throw new Error(`Invalid numeric player field: ${field}`);
  }
  return parsed;
}

function formatDateOnly(value: unknown): string | null {
  if (value === null || value === undefined || value === '') return null;

  if (value instanceof Date) {
    const year = value.getFullYear();
    const month = String(value.getMonth() + 1).padStart(2, '0');
    const day = String(value.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  const text = String(value);
  const isoDate = text.match(/^(\d{4}-\d{2}-\d{2})/);
  const matchedDate = isoDate?.[1];
  if (matchedDate !== undefined) return matchedDate;

  const parsed = new Date(text);
  if (Number.isNaN(parsed.getTime())) return null;

  const year = parsed.getFullYear();
  const month = String(parsed.getMonth() + 1).padStart(2, '0');
  const day = String(parsed.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function mapPlayer(row: RowDataPacket): Player {
  const photoAssetId = nullableNumber(row.photo_asset_id);

  return {
    id: requiredNumber(row.id, 'id'),
    organizationId: requiredNumber(row.organization_id, 'organization_id'),
    organizationName: requiredString(row.organization_name, 'organization_name'),
    teamId: nullableNumber(row.team_id),
    teamName: nullableString(row.team_name),
    firstName: requiredString(row.first_name, 'first_name'),
    lastName: requiredString(row.last_name, 'last_name'),
    preferredName: nullableString(row.preferred_name),
    jerseyNumber: nullableNumber(row.jersey_number),
    position: requiredString(row.position, 'position') as PlayerPosition,
    shoots: nullableString(row.shoots) as PlayerShoots | null,
    birthDate: formatDateOnly(row.birth_date),
    heightCm: nullableNumber(row.height_cm),
    weightKg: nullableNumber(row.weight_kg),
    email: nullableString(row.email),
    phone: nullableString(row.phone),
    photoAssetId,
    photoUrl: logoUrl(photoAssetId),
    status: requiredString(row.status, 'status') as PlayerStatus,
    createdAt: row.created_at as Date | string,
    updatedAt: row.updated_at as Date | string
  };
}

export async function listPlayers(filters: PlayerFilters): Promise<Player[]> {
  const conditions: string[] = [];
  const params: Array<string | number> = [];

  if (filters.organizationId !== undefined) {
    conditions.push('p.organization_id = ?');
    params.push(filters.organizationId);
  }

  if (filters.teamId !== undefined) {
    conditions.push('p.team_id = ?');
    params.push(filters.teamId);
  }

  if (filters.position !== undefined) {
    conditions.push('p.position = ?');
    params.push(filters.position);
  }

  if (filters.status !== undefined) {
    conditions.push('p.status = ?');
    params.push(filters.status);
  }

  const search = filters.search?.trim();
  if (search) {
    const jerseyNumber = Number(search);

    if (Number.isInteger(jerseyNumber) && jerseyNumber >= 0 && jerseyNumber <= 99) {
      conditions.push(`(
        p.first_name LIKE ?
        OR p.last_name LIKE ?
        OR p.preferred_name LIKE ?
        OR p.jersey_number = ?
      )`);
      const like = `%${search}%`;
      params.push(like, like, like, jerseyNumber);
    } else {
      conditions.push(`(
        p.first_name LIKE ?
        OR p.last_name LIKE ?
        OR p.preferred_name LIKE ?
      )`);
      const like = `%${search}%`;
      params.push(like, like, like);
    }
  }

  const where = conditions.length > 0 ? ` WHERE ${conditions.join(' AND ')}` : '';
  const [rows] = await pool.execute<RowDataPacket[]>(
    `${SELECT_PLAYER}${where} ORDER BY p.last_name, p.first_name`,
    params
  );

  return rows.map(mapPlayer);
}

export async function findPlayerById(id: number): Promise<Player | null> {
  const [rows] = await pool.execute<RowDataPacket[]>(
    `${SELECT_PLAYER} WHERE p.id = ?`,
    [id]
  );

  const row = rows[0];
  return row === undefined ? null : mapPlayer(row);
}

export async function createPlayer(input: PlayerInput): Promise<Player> {
  const [result] = await pool.execute<mysql.ResultSetHeader>(
    `INSERT INTO players
      (organization_id, team_id, first_name, last_name, preferred_name, jersey_number, position, shoots, birth_date, height_cm, weight_kg, email, phone, photo_asset_id, status)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      input.organizationId,
      input.teamId ?? null,
      input.firstName,
      input.lastName,
      input.preferredName ?? null,
      input.jerseyNumber ?? null,
      input.position,
      input.shoots ?? null,
      input.birthDate ?? null,
      input.heightCm ?? null,
      input.weightKg ?? null,
      input.email ?? null,
      input.phone ?? null,
      input.photoAssetId ?? null,
      input.status
    ]
  );

  const player = await findPlayerById(result.insertId);
  if (player === null) {
    throw new Error(`Player ${result.insertId} could not be read after creation`);
  }

  return player;
}

export async function updatePlayer(id: number, input: PlayerInput): Promise<Player | null> {
  const [result] = await pool.execute<mysql.ResultSetHeader>(
    `UPDATE players SET
      organization_id = ?,
      team_id = ?,
      first_name = ?,
      last_name = ?,
      preferred_name = ?,
      jersey_number = ?,
      position = ?,
      shoots = ?,
      birth_date = ?,
      height_cm = ?,
      weight_kg = ?,
      email = ?,
      phone = ?,
      photo_asset_id = ?,
      status = ?
      WHERE id = ?`,
    [
      input.organizationId,
      input.teamId ?? null,
      input.firstName,
      input.lastName,
      input.preferredName ?? null,
      input.jerseyNumber ?? null,
      input.position,
      input.shoots ?? null,
      input.birthDate ?? null,
      input.heightCm ?? null,
      input.weightKg ?? null,
      input.email ?? null,
      input.phone ?? null,
      input.photoAssetId ?? null,
      input.status,
      id
    ]
  );

  if (result.affectedRows === 0) return null;
  return findPlayerById(id);
}

export async function deletePlayer(id: number): Promise<boolean> {
  const [result] = await pool.execute<mysql.ResultSetHeader>(
    'DELETE FROM players WHERE id = ?',
    [id]
  );

  return result.affectedRows > 0;
}

export async function validatePlayerRelationships(
  input: PlayerInput
): Promise<'organization' | 'team' | null> {
  const [organizations] = await pool.execute<RowDataPacket[]>(
    'SELECT id FROM organizations WHERE id = ?',
    [input.organizationId]
  );

  if (organizations[0] === undefined) return 'organization';

  if (input.teamId !== null && input.teamId !== undefined) {
    const [teams] = await pool.execute<RowDataPacket[]>(
      'SELECT id FROM teams WHERE id = ? AND organization_id = ?',
      [input.teamId, input.organizationId]
    );

    if (teams[0] === undefined) return 'team';
  }

  return null;
}
