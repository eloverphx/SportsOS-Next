import type { ResultSetHeader, RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import type { MediaGrantPermission, MediaVisibility } from "./access-policy.js";

export type MediaKind = "IMAGE" | "VIDEO" | "AUDIO" | "OTHER";

interface MediaAssetRow extends RowDataPacket {
  id: number | string;
  organization_id: number | string | null;
  owner_user_id: number | string | null;
  media_kind: MediaKind;
  visibility: MediaVisibility;
  bucket: string;
  object_key: string;
  original_name: string;
  mime_type: string;
  size_bytes: number | string;
  captured_at: Date | string | null;
  duration_ms: number | string | null;
  checksum_sha256: string | null;
  created_at: Date | string;
  grant_permission: MediaGrantPermission | null;
}

export interface MediaAssetRecord {
  readonly id: number;
  readonly organizationId: number | null;
  readonly ownerUserId: number | null;
  readonly mediaKind: MediaKind;
  readonly visibility: MediaVisibility;
  readonly bucket: string;
  readonly objectKey: string;
  readonly originalName: string;
  readonly mimeType: string;
  readonly sizeBytes: number;
  readonly capturedAt: string | null;
  readonly durationMs: number | null;
  readonly checksumSha256: string | null;
  readonly createdAt: string;
  readonly grantPermission: MediaGrantPermission | null;
}

function iso(value: Date | string | null): string | null {
  if (value == null) return null;

  return (value instanceof Date ? value : new Date(value)).toISOString();
}

function mapMediaAsset(row: MediaAssetRow): MediaAssetRecord {
  return {
    id: Number(row.id),
    organizationId: row.organization_id == null ? null : Number(row.organization_id),
    ownerUserId: row.owner_user_id == null ? null : Number(row.owner_user_id),
    mediaKind: row.media_kind,
    visibility: row.visibility,
    bucket: row.bucket,
    objectKey: row.object_key,
    originalName: row.original_name,
    mimeType: row.mime_type,
    sizeBytes: Number(row.size_bytes),
    capturedAt: iso(row.captured_at),
    durationMs: row.duration_ms == null ? null : Number(row.duration_ms),
    checksumSha256: row.checksum_sha256,
    createdAt: iso(row.created_at) ?? "",
    grantPermission: row.grant_permission,
  };
}

const MEDIA_SELECT = `SELECT
  m.id,
  m.organization_id,
  m.owner_user_id,
  m.media_kind,
  m.visibility,
  m.bucket,
  m.object_key,
  m.original_name,
  m.mime_type,
  m.size_bytes,
  m.captured_at,
  m.duration_ms,
  m.checksum_sha256,
  m.created_at,
  g.permission AS grant_permission
FROM media_assets m
LEFT JOIN media_access_grants g
  ON g.media_asset_id = m.id
 AND g.grantee_user_id = ?`;

export async function findMediaAsset(
  assetId: number,
  granteeUserId: number | null,
): Promise<MediaAssetRecord | null> {
  const [rows] = await pool.execute<MediaAssetRow[]>(
    `${MEDIA_SELECT}
     WHERE m.id = ?
     LIMIT 1`,
    [granteeUserId ?? 0, assetId],
  );

  return rows[0] ? mapMediaAsset(rows[0]) : null;
}

export async function listMediaAssetsForIdentity(
  organizationId: number,
  userId: number,
  limit: number,
): Promise<MediaAssetRecord[]> {
  const [rows] = await pool.execute<MediaAssetRow[]>(
    `${MEDIA_SELECT}
     WHERE m.organization_id = ?
        OR m.owner_user_id = ?
        OR g.grantee_user_id = ?
     ORDER BY m.created_at DESC, m.id DESC
     LIMIT ?`,
    [userId, organizationId, userId, userId, limit],
  );

  return rows.map(mapMediaAsset);
}

export async function updateMediaVisibility(
  assetId: number,
  visibility: MediaVisibility,
): Promise<boolean> {
  const [result] = await pool.execute<ResultSetHeader>(
    `UPDATE media_assets
       SET visibility = ?
       WHERE id = ?`,
    [visibility, assetId],
  );

  return result.affectedRows > 0;
}

interface MediaGrantRow extends RowDataPacket {
  user_id: number | string;
  first_name: string;
  last_name: string;
  username: string;
  permission: MediaGrantPermission;
}

export interface MediaGrantRecord {
  readonly userId: number;
  readonly firstName: string;
  readonly lastName: string;
  readonly username: string;
  readonly permission: MediaGrantPermission;
}

export async function listMediaGrants(assetId: number): Promise<MediaGrantRecord[]> {
  const [rows] = await pool.execute<MediaGrantRow[]>(
    `SELECT
       u.id AS user_id,
       u.first_name,
       u.last_name,
       u.username,
       g.permission
     FROM media_access_grants g
     JOIN users u ON u.id = g.grantee_user_id
     WHERE g.media_asset_id = ?
     ORDER BY u.last_name, u.first_name, u.id`,
    [assetId],
  );

  return rows.map((row) => ({
    userId: Number(row.user_id),
    firstName: row.first_name,
    lastName: row.last_name,
    username: row.username,
    permission: row.permission,
  }));
}

export async function userBelongsToOrganization(
  userId: number,
  organizationId: number,
): Promise<boolean> {
  const [rows] = await pool.execute<RowDataPacket[]>(
    `SELECT id
     FROM users
     WHERE id = ?
       AND organization_id = ?
       AND account_status = 'ACTIVE'
     LIMIT 1`,
    [userId, organizationId],
  );

  return rows.length > 0;
}

export async function grantMediaAccess(input: {
  assetId: number;
  granteeUserId: number;
  permission: MediaGrantPermission;
  grantedByUserId: number;
}): Promise<void> {
  await pool.execute(
    `INSERT INTO media_access_grants (
       media_asset_id,
       grantee_user_id,
       permission,
       granted_by_user_id
     )
     VALUES (?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE
       permission = VALUES(permission),
       granted_by_user_id = VALUES(granted_by_user_id),
       updated_at = CURRENT_TIMESTAMP(3)`,
    [input.assetId, input.granteeUserId, input.permission, input.grantedByUserId],
  );
}

export async function revokeMediaAccess(assetId: number, granteeUserId: number): Promise<boolean> {
  const [result] = await pool.execute<ResultSetHeader>(
    `DELETE FROM media_access_grants
       WHERE media_asset_id = ?
         AND grantee_user_id = ?`,
    [assetId, granteeUserId],
  );

  return result.affectedRows > 0;
}
