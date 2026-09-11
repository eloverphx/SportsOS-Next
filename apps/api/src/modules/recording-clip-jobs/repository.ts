import type { ResultSetHeader, RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import type { MediaVisibility } from "../media-library/access-policy.js";
import { assertValidClipWindow } from "./policy.js";

export type RecordingClipSelectionSource = "SCOREKEEPER_EVENT" | "AI_SELECTION";

export type RecordingClipJobStatus = "PENDING" | "PROCESSING" | "READY" | "FAILED" | "CANCELLED";

interface RecordingClipJobRow extends RowDataPacket {
  id: number | string;
  organization_id: number | string;
  recording_id: number | string;
  game_event_id: number | string;
  requested_by_user_id: number | string;
  selection_source: RecordingClipSelectionSource;
  start_ms: number | string;
  end_ms: number | string;
  status: RecordingClipJobStatus;
  output_media_asset_id: number | string | null;
  error_message: string | null;
  attempt_count: number | string;
  claimed_at: Date | string | null;
  created_at: Date | string;
  updated_at: Date | string;
}

export interface RecordingClipJob {
  readonly id: number;
  readonly organizationId: number;
  readonly recordingId: number;
  readonly gameEventId: number;
  readonly requestedByUserId: number;
  readonly selectionSource: RecordingClipSelectionSource;
  readonly startMs: number;
  readonly endMs: number;
  readonly durationMs: number;
  readonly status: RecordingClipJobStatus;
  readonly outputMediaAssetId: number | null;
  readonly errorMessage: string | null;
  readonly attemptCount: number;
  readonly claimedAt: string | null;
  readonly createdAt: string;
  readonly updatedAt: string;
}

function iso(value: Date | string | null): string | null {
  if (value == null) return null;
  return (value instanceof Date ? value : new Date(value)).toISOString();
}

function mapJob(row: RecordingClipJobRow): RecordingClipJob {
  const startMs = Number(row.start_ms);
  const endMs = Number(row.end_ms);

  return {
    id: Number(row.id),
    organizationId: Number(row.organization_id),
    recordingId: Number(row.recording_id),
    gameEventId: Number(row.game_event_id),
    requestedByUserId: Number(row.requested_by_user_id),
    selectionSource: row.selection_source,
    startMs,
    endMs,
    durationMs: endMs - startMs,
    status: row.status,
    outputMediaAssetId:
      row.output_media_asset_id == null ? null : Number(row.output_media_asset_id),
    errorMessage: row.error_message,
    attemptCount: Number(row.attempt_count),
    claimedAt: iso(row.claimed_at),
    createdAt: iso(row.created_at) ?? "",
    updatedAt: iso(row.updated_at) ?? "",
  };
}

const CLIP_JOB_SELECT = `SELECT
  id,
  organization_id,
  recording_id,
  game_event_id,
  requested_by_user_id,
  selection_source,
  start_ms,
  end_ms,
  status,
  output_media_asset_id,
  error_message,
  attempt_count,
  claimed_at,
  created_at,
  updated_at
FROM recording_clip_jobs`;

export async function findRecordingClipJob(jobId: number): Promise<RecordingClipJob | null> {
  const [rows] = await pool.execute<RecordingClipJobRow[]>(
    `${CLIP_JOB_SELECT}
       WHERE id = ?
       LIMIT 1`,
    [jobId],
  );

  return rows[0] ? mapJob(rows[0]) : null;
}

export async function listRecordingClipJobs(recordingId: number): Promise<RecordingClipJob[]> {
  const [rows] = await pool.execute<RecordingClipJobRow[]>(
    `${CLIP_JOB_SELECT}
       WHERE recording_id = ?
       ORDER BY created_at DESC, id DESC`,
    [recordingId],
  );

  return rows.map(mapJob);
}

export async function createRecordingClipJob(input: {
  readonly organizationId: number;
  readonly recordingId: number;
  readonly gameEventId: number;
  readonly requestedByUserId: number;
  readonly selectionSource: RecordingClipSelectionSource;
  readonly startMs: number;
  readonly endMs: number;
}): Promise<RecordingClipJob> {
  assertValidClipWindow(input.startMs, input.endMs);

  const [result] = await pool.execute<ResultSetHeader>(
    `INSERT INTO recording_clip_jobs (
         organization_id,
         recording_id,
         game_event_id,
         requested_by_user_id,
         selection_source,
         start_ms,
         end_ms
       )
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         id = LAST_INSERT_ID(id)`,
    [
      input.organizationId,
      input.recordingId,
      input.gameEventId,
      input.requestedByUserId,
      input.selectionSource,
      input.startMs,
      input.endMs,
    ],
  );

  const job = await findRecordingClipJob(Number(result.insertId));

  if (!job) {
    throw new Error("Created clip job could not be loaded");
  }

  return job;
}

interface WorkerClaimRow extends RecordingClipJobRow {
  source_media_asset_id: number | string;
  source_owner_user_id: number | string | null;
  source_visibility: MediaVisibility;
  source_bucket: string;
  source_object_key: string;
}

export interface ClaimedRecordingClipJob extends RecordingClipJob {
  readonly sourceMediaAssetId: number;
  readonly sourceOwnerUserId: number | null;
  readonly sourceVisibility: MediaVisibility;
  readonly sourceBucket: string;
  readonly sourceObjectKey: string;
}

const WORKER_CLAIM_SELECT = `SELECT
  j.id,
  j.organization_id,
  j.recording_id,
  j.game_event_id,
  j.requested_by_user_id,
  j.selection_source,
  j.start_ms,
  j.end_ms,
  j.status,
  j.output_media_asset_id,
  j.error_message,
  j.attempt_count,
  j.claimed_at,
  j.created_at,
  j.updated_at,
  m.id AS source_media_asset_id,
  m.owner_user_id AS source_owner_user_id,
  m.visibility AS source_visibility,
  m.bucket AS source_bucket,
  m.object_key AS source_object_key
FROM recording_clip_jobs j
JOIN recordings r
  ON r.id = j.recording_id
JOIN media_assets m
  ON m.id = r.media_asset_id`;

function mapClaim(row: WorkerClaimRow): ClaimedRecordingClipJob {
  return {
    ...mapJob(row),
    sourceMediaAssetId: Number(row.source_media_asset_id),
    sourceOwnerUserId: row.source_owner_user_id == null ? null : Number(row.source_owner_user_id),
    sourceVisibility: row.source_visibility,
    sourceBucket: row.source_bucket,
    sourceObjectKey: row.source_object_key,
  };
}

export async function claimNextRecordingClipJob(): Promise<ClaimedRecordingClipJob | null> {
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    const [rows] = await connection.execute<WorkerClaimRow[]>(
      `${WORKER_CLAIM_SELECT}
         WHERE (
           j.status = 'PENDING'
           OR (
             j.status = 'PROCESSING'
             AND j.claimed_at IS NOT NULL
             AND j.claimed_at <
               DATE_SUB(CURRENT_TIMESTAMP(3), INTERVAL 15 MINUTE)
           )
         )
           AND j.output_media_asset_id IS NULL
           AND m.organization_id = j.organization_id
           AND m.media_kind = 'VIDEO'
         ORDER BY j.created_at ASC, j.id ASC
         LIMIT 1
         FOR UPDATE SKIP LOCKED`,
    );

    const row = rows[0];

    if (!row) {
      await connection.commit();
      return null;
    }

    await connection.execute(
      `UPDATE recording_clip_jobs
       SET status = 'PROCESSING',
           claimed_at = CURRENT_TIMESTAMP(3),
           attempt_count = attempt_count + 1,
           error_message = NULL
       WHERE id = ?`,
      [Number(row.id)],
    );

    await connection.commit();

    return {
      ...mapClaim(row),
      status: "PROCESSING",
      attemptCount: Number(row.attempt_count) + 1,
      claimedAt: new Date().toISOString(),
    };
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}

export async function markRecordingClipJobAttemptFailed(
  jobId: number,
  attemptCount: number,
  errorMessage: string,
  maxAttempts = 3,
): Promise<void> {
  const nextStatus: RecordingClipJobStatus = attemptCount >= maxAttempts ? "FAILED" : "PENDING";

  await pool.execute(
    `UPDATE recording_clip_jobs
     SET status = ?,
         error_message = ?,
         claimed_at = NULL
     WHERE id = ?
       AND status = 'PROCESSING'
       AND attempt_count = ?`,
    [nextStatus, errorMessage.slice(0, 1000), jobId, attemptCount],
  );
}

interface CompletionRow extends RowDataPacket {
  id: number | string;
  organization_id: number | string;
  attempt_count: number | string;
  game_event_id: number | string;
  start_ms: number | string;
  end_ms: number | string;
  status: RecordingClipJobStatus;
  source_media_asset_id: number | string | null;
  source_owner_user_id: number | string | null;
  source_visibility: MediaVisibility | null;
}

export async function completeRecordingClipJob(input: {
  readonly jobId: number;
  readonly attemptCount: number;
  readonly bucket: string;
  readonly objectKey: string;
  readonly sizeBytes: number;
  readonly checksumSha256: string;
}): Promise<number> {
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    const [rows] = await connection.execute<CompletionRow[]>(
      `SELECT
           j.id,
           j.organization_id,
           j.attempt_count,
           j.game_event_id,
           j.start_ms,
           j.end_ms,
           j.status,
           m.id AS source_media_asset_id,
           m.owner_user_id AS source_owner_user_id,
           m.visibility AS source_visibility
         FROM recording_clip_jobs j
         JOIN recordings r
           ON r.id = j.recording_id
         LEFT JOIN media_assets m
           ON m.id = r.media_asset_id
         WHERE j.id = ?
         LIMIT 1
         FOR UPDATE`,
      [input.jobId],
    );

    const row = rows[0];

    if (
      !row ||
      row.status !== "PROCESSING" ||
      Number(row.attempt_count) !== input.attemptCount ||
      row.source_media_asset_id == null ||
      row.source_visibility == null
    ) {
      throw new Error("Clip job is not claimable for completion");
    }

    const durationMs = Number(row.end_ms) - Number(row.start_ms);

    assertValidClipWindow(Number(row.start_ms), Number(row.end_ms));

    const [assetResult] = await connection.execute<ResultSetHeader>(
      `INSERT INTO media_assets (
           organization_id,
           owner_user_id,
           media_kind,
           visibility,
           bucket,
           object_key,
           original_name,
           mime_type,
           size_bytes,
           duration_ms,
           checksum_sha256
         )
         VALUES (?, ?, 'VIDEO', ?, ?, ?, ?, 'video/mp4', ?, ?, ?)`,
      [
        Number(row.organization_id),
        row.source_owner_user_id == null ? null : Number(row.source_owner_user_id),
        row.source_visibility,
        input.bucket,
        input.objectKey,
        `game-event-${Number(row.game_event_id)}-clip.mp4`,
        input.sizeBytes,
        durationMs,
        input.checksumSha256,
      ],
    );

    const outputMediaAssetId = Number(assetResult.insertId);

    await connection.execute(
      `INSERT INTO media_access_grants (
         media_asset_id,
         grantee_user_id,
         permission,
         granted_by_user_id
       )
       SELECT
         ?,
         grantee_user_id,
         permission,
         granted_by_user_id
       FROM media_access_grants
       WHERE media_asset_id = ?`,
      [outputMediaAssetId, Number(row.source_media_asset_id)],
    );

    await connection.execute(
      `UPDATE recording_clip_jobs
       SET status = 'READY',
           output_media_asset_id = ?,
           error_message = NULL,
           claimed_at = NULL
       WHERE id = ?
         AND status = 'PROCESSING'
         AND attempt_count = ?`,
      [outputMediaAssetId, input.jobId, input.attemptCount],
    );

    await connection.commit();

    return outputMediaAssetId;
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}
