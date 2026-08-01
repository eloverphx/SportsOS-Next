import { randomBytes } from "node:crypto";
import type { ResultSetHeader, RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import type { ScoreboardDevice, ScoreboardDeviceInput } from "./types.js";

interface ScoreboardDeviceRow extends RowDataPacket {
  id: number;
  organization_id: number;
  organization_name: string;
  game_id: number | null;
  game_label: string | null;
  name: string;
  location: string | null;
  device_key: string;
  status: "OFFLINE" | "ONLINE";
  last_seen_at: Date | string | null;
  created_at: Date | string;
  updated_at: Date | string;
}

function mapRow(row: ScoreboardDeviceRow): ScoreboardDevice {
  return {
    id: Number(row.id),
    organizationId: Number(row.organization_id),
    organizationName: row.organization_name,
    gameId: row.game_id === null ? null : Number(row.game_id),
    gameLabel: row.game_label,
    name: row.name,
    location: row.location,
    deviceKey: row.device_key,
    status: row.status,
    lastSeenAt: row.last_seen_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

const selectSql = `
  SELECT
    d.id,
    d.organization_id,
    o.name AS organization_name,
    d.game_id,
    CASE
      WHEN g.id IS NULL THEN NULL
      ELSE CONCAT(away.name, ' at ', home.name)
    END AS game_label,
    d.name,
    d.location,
    d.device_key,
    CASE
      WHEN d.last_seen_at IS NOT NULL
       AND d.last_seen_at >= DATE_SUB(UTC_TIMESTAMP(), INTERVAL 90 SECOND)
      THEN 'ONLINE'
      ELSE 'OFFLINE'
    END AS status,
    d.last_seen_at,
    d.created_at,
    d.updated_at
  FROM scoreboard_devices d
  JOIN organizations o ON o.id = d.organization_id
  LEFT JOIN games g ON g.id = d.game_id
  LEFT JOIN teams home ON home.id = g.home_team_id
  LEFT JOIN teams away ON away.id = g.away_team_id
`;

export async function listScoreboardDevices(organizationId?: number): Promise<ScoreboardDevice[]> {
  const [rows] = organizationId
    ? await pool.query<ScoreboardDeviceRow[]>(
        `${selectSql} WHERE d.organization_id = ? ORDER BY d.name`,
        [organizationId],
      )
    : await pool.query<ScoreboardDeviceRow[]>(`${selectSql} ORDER BY o.name, d.name`);

  return rows.map(mapRow);
}

export async function findScoreboardDeviceById(id: number): Promise<ScoreboardDevice | null> {
  const [rows] = await pool.query<ScoreboardDeviceRow[]>(`${selectSql} WHERE d.id = ? LIMIT 1`, [
    id,
  ]);

  return rows[0] ? mapRow(rows[0]) : null;
}

export async function validateScoreboardDeviceRelationships(
  input: ScoreboardDeviceInput,
): Promise<"organization" | "game" | null> {
  const [organizations] = await pool.query<RowDataPacket[]>(
    "SELECT id FROM organizations WHERE id = ? LIMIT 1",
    [input.organizationId],
  );

  if (!organizations.length) return "organization";
  if (input.gameId === null) return null;

  const [games] = await pool.query<RowDataPacket[]>(
    "SELECT id FROM games WHERE id = ? AND organization_id = ? LIMIT 1",
    [input.gameId, input.organizationId],
  );

  return games.length ? null : "game";
}

export async function createScoreboardDevice(
  input: ScoreboardDeviceInput,
): Promise<ScoreboardDevice> {
  const deviceKey = randomBytes(32).toString("hex");

  const [result] = await pool.execute<ResultSetHeader>(
    `INSERT INTO scoreboard_devices
      (organization_id, game_id, name, location, device_key)
     VALUES (?, ?, ?, ?, ?)`,
    [input.organizationId, input.gameId, input.name, input.location, deviceKey],
  );

  const device = await findScoreboardDeviceById(result.insertId);
  if (!device) throw new Error("Created scoreboard device could not be loaded");
  return device;
}

export async function updateScoreboardDevice(
  id: number,
  input: ScoreboardDeviceInput,
): Promise<ScoreboardDevice | null> {
  const [result] = await pool.execute<ResultSetHeader>(
    `UPDATE scoreboard_devices
     SET organization_id = ?, game_id = ?, name = ?, location = ?
     WHERE id = ?`,
    [input.organizationId, input.gameId, input.name, input.location, id],
  );

  if (!result.affectedRows) return null;
  return findScoreboardDeviceById(id);
}

export async function rotateScoreboardDeviceKey(id: number): Promise<ScoreboardDevice | null> {
  const deviceKey = randomBytes(32).toString("hex");

  const [result] = await pool.execute<ResultSetHeader>(
    "UPDATE scoreboard_devices SET device_key = ?, last_seen_at = NULL WHERE id = ?",
    [deviceKey, id],
  );

  if (!result.affectedRows) return null;
  return findScoreboardDeviceById(id);
}

export async function recordScoreboardHeartbeat(
  id: number,
  deviceKey: string,
): Promise<ScoreboardDevice | null> {
  const [result] = await pool.execute<ResultSetHeader>(
    `UPDATE scoreboard_devices
     SET last_seen_at = UTC_TIMESTAMP(3)
     WHERE id = ? AND device_key = ?`,
    [id, deviceKey],
  );

  if (!result.affectedRows) return null;
  return findScoreboardDeviceById(id);
}

export async function deleteScoreboardDevice(id: number): Promise<boolean> {
  const [result] = await pool.execute<ResultSetHeader>(
    "DELETE FROM scoreboard_devices WHERE id = ?",
    [id],
  );

  return result.affectedRows > 0;
}
