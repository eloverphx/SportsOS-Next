import type { ResultSetHeader, RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import type { MediaGrantPermission, MediaVisibility } from "../media-library/access-policy.js";
import type { MediaKind } from "../media-library/repository.js";

export type RecordingSource = "LIVE" | "UPLOAD" | "IMPORT";

export type RecordingStatus =
  | "CREATED"
  | "RECORDING"
  | "PROCESSING"
  | "READY"
  | "FAILED"
  | "ARCHIVED";

interface RecordingRow extends RowDataPacket {
  id: number | string;
  organization_id: number | string;
  game_id: number | string | null;
  owner_user_id: number | string;
  media_asset_id: number | string | null;
  source: RecordingSource;
  status: RecordingStatus;
  title: string | null;
  started_at: Date | string | null;
  ended_at: Date | string | null;
  duration_ms: number | string | null;
  published_at: Date | string | null;
  created_at: Date | string;
  updated_at: Date | string;
  media_organization_id: number | string | null;
  media_owner_user_id: number | string | null;
  media_kind: MediaKind | null;
  media_visibility: MediaVisibility | null;
  media_grant_permission: MediaGrantPermission | null;
}

export interface RecordingRecord {
  readonly id: number;
  readonly organizationId: number;
  readonly gameId: number | null;
  readonly ownerUserId: number;
  readonly mediaAssetId: number | null;
  readonly source: RecordingSource;
  readonly status: RecordingStatus;
  readonly title: string | null;
  readonly startedAt: string | null;
  readonly endedAt: string | null;
  readonly durationMs: number | null;
  readonly publishedAt: string | null;
  readonly createdAt: string;
  readonly updatedAt: string;
  readonly media: {
    readonly organizationId: number | null;
    readonly ownerUserId: number | null;
    readonly visibility: MediaVisibility;
    readonly grantPermission: MediaGrantPermission | null;
    readonly mediaKind: MediaKind;
  } | null;
}

function iso(value: Date | string | null): string | null {
  if (value == null) return null;

  return (value instanceof Date ? value : new Date(value)).toISOString();
}

function mapRecording(row: RecordingRow): RecordingRecord {
  return {
    id: Number(row.id),
    organizationId: Number(row.organization_id),
    gameId: row.game_id == null ? null : Number(row.game_id),
    ownerUserId: Number(row.owner_user_id),
    mediaAssetId: row.media_asset_id == null ? null : Number(row.media_asset_id),
    source: row.source,
    status: row.status,
    title: row.title,
    startedAt: iso(row.started_at),
    endedAt: iso(row.ended_at),
    durationMs: row.duration_ms == null ? null : Number(row.duration_ms),
    publishedAt: iso(row.published_at),
    createdAt: iso(row.created_at) ?? "",
    updatedAt: iso(row.updated_at) ?? "",
    media:
      row.media_asset_id == null || row.media_visibility == null || row.media_kind == null
        ? null
        : {
            organizationId:
              row.media_organization_id == null ? null : Number(row.media_organization_id),
            ownerUserId: row.media_owner_user_id == null ? null : Number(row.media_owner_user_id),
            visibility: row.media_visibility,
            grantPermission: row.media_grant_permission,
            mediaKind: row.media_kind,
          },
  };
}

const RECORDING_SELECT = `SELECT
  r.id,
  r.organization_id,
  r.game_id,
  r.owner_user_id,
  r.media_asset_id,
  r.source,
  r.status,
  r.title,
  r.started_at,
  r.ended_at,
  r.duration_ms,
  r.published_at,
  r.created_at,
  r.updated_at,
  m.organization_id AS media_organization_id,
  m.owner_user_id AS media_owner_user_id,
  m.media_kind,
  m.visibility AS media_visibility,
  g.permission AS media_grant_permission
FROM recordings r
LEFT JOIN media_assets m
  ON m.id = r.media_asset_id
LEFT JOIN media_access_grants g
  ON g.media_asset_id = m.id
 AND g.grantee_user_id = ?`;

export async function findRecording(
  recordingId: number,
  granteeUserId: number,
): Promise<RecordingRecord | null> {
  const [rows] = await pool.execute<RecordingRow[]>(
    `${RECORDING_SELECT}
       WHERE r.id = ?
       LIMIT 1`,
    [granteeUserId, recordingId],
  );

  return rows[0] ? mapRecording(rows[0]) : null;
}

export async function listRecordings(
  organizationId: number,
  granteeUserId: number,
  limit: number,
): Promise<RecordingRecord[]> {
  const [rows] = await pool.execute<RecordingRow[]>(
    `${RECORDING_SELECT}
       WHERE r.organization_id = ?
       ORDER BY r.created_at DESC, r.id DESC
       LIMIT ?`,
    [granteeUserId, organizationId, limit],
  );

  return rows.map(mapRecording);
}

export async function gameBelongsToOrganization(
  gameId: number,
  organizationId: number,
): Promise<boolean> {
  const [rows] = await pool.execute<RowDataPacket[]>(
    `SELECT id
     FROM games
     WHERE id = ?
       AND organization_id = ?
     LIMIT 1`,
    [gameId, organizationId],
  );

  return rows.length > 0;
}

export async function createRecording(input: {
  organizationId: number;
  gameId: number | null;
  ownerUserId: number;
  source: RecordingSource;
  title: string | null;
}): Promise<number> {
  const [result] = await pool.execute<ResultSetHeader>(
    `INSERT INTO recordings (
         organization_id,
         game_id,
         owner_user_id,
         source,
         title
       )
       VALUES (?, ?, ?, ?, ?)`,
    [input.organizationId, input.gameId, input.ownerUserId, input.source, input.title],
  );

  return Number(result.insertId);
}

export async function updateRecordingMetadata(input: {
  recordingId: number;
  title: string | null;
  mediaAssetId: number | null;
}): Promise<boolean> {
  const [result] = await pool.execute<ResultSetHeader>(
    `UPDATE recordings
       SET title = ?,
           media_asset_id = ?
       WHERE id = ?`,
    [input.title, input.mediaAssetId, input.recordingId],
  );

  return result.affectedRows > 0;
}
