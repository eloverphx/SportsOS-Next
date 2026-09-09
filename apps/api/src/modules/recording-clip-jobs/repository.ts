import type { ResultSetHeader, RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
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
  readonly createdAt: string;
  readonly updatedAt: string;
}

function iso(value: Date | string): string {
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
    createdAt: iso(row.created_at),
    updatedAt: iso(row.updated_at),
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
