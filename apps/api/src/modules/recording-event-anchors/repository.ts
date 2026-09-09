import type { PoolConnection, RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";

export type RecordingEventAnchorSource = "SCOREKEEPER" | "SYSTEM";

export type RecordingEventAnchorCreateResult =
  | {
      readonly anchored: true;
      readonly recordingId: number;
      readonly recordingOffsetMs: number;
    }
  | {
      readonly anchored: false;
      readonly reason: "no-active-recording" | "event-before-recording";
    };

interface ActiveRecordingRow extends RowDataPacket {
  id: number | string;
  started_at: Date | string;
}

export async function createAuthoritativeRecordingAnchor(
  connection: PoolConnection,
  input: {
    readonly gameId: number;
    readonly eventId: number;
    readonly eventCreatedAt: string;
  },
): Promise<RecordingEventAnchorCreateResult> {
  const [recordings] = await connection.execute<ActiveRecordingRow[]>(
    `SELECT id, started_at
       FROM recordings
       WHERE game_id = ?
         AND status = 'RECORDING'
         AND started_at IS NOT NULL
       ORDER BY id DESC
       LIMIT 1
       FOR UPDATE`,
    [input.gameId],
  );

  const recording = recordings[0];

  if (!recording) {
    return {
      anchored: false,
      reason: "no-active-recording",
    };
  }

  const recordingStartedAt = new Date(recording.started_at).getTime();

  const eventCreatedAt = new Date(input.eventCreatedAt).getTime();

  if (!Number.isFinite(recordingStartedAt) || !Number.isFinite(eventCreatedAt)) {
    throw new Error("Recording or event timestamp is invalid");
  }

  if (eventCreatedAt < recordingStartedAt) {
    return {
      anchored: false,
      reason: "event-before-recording",
    };
  }

  const recordingOffsetMs = Math.floor(eventCreatedAt - recordingStartedAt);

  await connection.execute(
    `INSERT INTO recording_event_anchors (
       recording_id,
       game_event_id,
       recording_offset_ms,
       anchor_source
     )
     VALUES (?, ?, ?, 'SCOREKEEPER')`,
    [Number(recording.id), input.eventId, recordingOffsetMs],
  );

  return {
    anchored: true,
    recordingId: Number(recording.id),
    recordingOffsetMs,
  };
}

interface RecordingEventAnchorRow extends RowDataPacket {
  id: number | string;
  recording_id: number | string;
  game_event_id: number | string;
  recording_offset_ms: number | string;
  anchor_source: RecordingEventAnchorSource;
  event_type: "GOAL" | "PENALTY";
  side: "home" | "away";
  period: number | string;
  clock_remaining_ms: number | string;
  player_id: number | string | null;
  assist1_player_id: number | string | null;
  assist2_player_id: number | string | null;
  player_first_name: string | null;
  player_last_name: string | null;
  player_preferred_name: string | null;
  player_jersey_number: number | string | null;
  voided_at: Date | string | null;
  event_created_at: Date | string;
}

export interface RecordingEventAnchor {
  readonly id: number;
  readonly recordingId: number;
  readonly gameEventId: number;
  readonly recordingOffsetMs: number;
  readonly anchorSource: RecordingEventAnchorSource;
  readonly eventType: "GOAL" | "PENALTY";
  readonly side: "home" | "away";
  readonly period: number;
  readonly clockRemainingMs: number;
  readonly playerId: number | null;
  readonly playerName: string | null;
  readonly playerJerseyNumber: number | null;
  readonly assist1PlayerId: number | null;
  readonly assist2PlayerId: number | null;
  readonly voidedAt: string | null;
  readonly eventCreatedAt: string;
}

function iso(value: Date | string | null): string | null {
  if (value == null) return null;

  return (value instanceof Date ? value : new Date(value)).toISOString();
}

function playerName(row: RecordingEventAnchorRow): string | null {
  if (row.player_first_name == null) {
    return null;
  }

  return `${
    row.player_preferred_name || row.player_first_name
  } ${row.player_last_name || ""}`.trim();
}

function mapAnchor(row: RecordingEventAnchorRow): RecordingEventAnchor {
  return {
    id: Number(row.id),
    recordingId: Number(row.recording_id),
    gameEventId: Number(row.game_event_id),
    recordingOffsetMs: Number(row.recording_offset_ms),
    anchorSource: row.anchor_source,
    eventType: row.event_type,
    side: row.side,
    period: Number(row.period),
    clockRemainingMs: Number(row.clock_remaining_ms),
    playerId: row.player_id == null ? null : Number(row.player_id),
    playerName: playerName(row),
    playerJerseyNumber: row.player_jersey_number == null ? null : Number(row.player_jersey_number),
    assist1PlayerId: row.assist1_player_id == null ? null : Number(row.assist1_player_id),
    assist2PlayerId: row.assist2_player_id == null ? null : Number(row.assist2_player_id),
    voidedAt: iso(row.voided_at),
    eventCreatedAt: iso(row.event_created_at) ?? "",
  };
}

export async function listRecordingEventAnchors(
  recordingId: number,
): Promise<RecordingEventAnchor[]> {
  const [rows] = await pool.execute<RecordingEventAnchorRow[]>(
    `SELECT
         rea.id,
         rea.recording_id,
         rea.game_event_id,
         rea.recording_offset_ms,
         rea.anchor_source,
         ge.type AS event_type,
         ge.side,
         ge.period,
         ge.clock_remaining_ms,
         ge.player_id,
         ge.assist1_player_id,
         ge.assist2_player_id,
         p.first_name AS player_first_name,
         p.last_name AS player_last_name,
         p.preferred_name AS player_preferred_name,
         p.jersey_number AS player_jersey_number,
         ge.voided_at,
         ge.created_at AS event_created_at
       FROM recording_event_anchors rea
       JOIN game_events ge
         ON ge.id = rea.game_event_id
       LEFT JOIN players p
         ON p.id = ge.player_id
       WHERE rea.recording_id = ?
       ORDER BY
         rea.recording_offset_ms ASC,
         rea.id ASC`,
    [recordingId],
  );

  return rows.map(mapAnchor);
}
