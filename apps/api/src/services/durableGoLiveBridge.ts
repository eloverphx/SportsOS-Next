import { randomUUID } from "node:crypto";
import type { ResultSetHeader, RowDataPacket } from "mysql2/promise";
import { pool } from "../infrastructure/database.js";
import type { GoLiveSessionStatus } from "./goLiveSession.js";

type DurableGoLiveStatus = Exclude<GoLiveSessionStatus, "IDLE">;

type DurableRecordingStatus = "RECORDING" | "PROCESSING" | "FAILED";

interface DurableStreamSessionRow extends RowDataPacket {
  id: number | string;
  status: DurableGoLiveStatus;
  recording_id: number | string | null;
}

export interface DurableGoLiveSyncResult {
  readonly synced: boolean;
  readonly skippedReason:
    | "non-numeric-game-id"
    | "game-not-found"
    | "idle-without-active-session"
    | null;
  readonly streamSessionId: number | null;
  readonly recordingId: number | null;
}

const TERMINAL_STATUSES = new Set<DurableGoLiveStatus>(["COMPLETE", "ERROR", "EMERGENCY_STOPPED"]);

export function parseDurableGameId(value: string): number | null {
  if (!/^[1-9]\d*$/.test(value.trim())) {
    return null;
  }

  const parsed = Number(value);

  return Number.isSafeInteger(parsed) ? parsed : null;
}

export function recordingStatusForGoLiveStatus(
  status: GoLiveSessionStatus,
): DurableRecordingStatus | null {
  switch (status) {
    case "LIVE":
    case "DEGRADED":
      return "RECORDING";

    case "COMPLETE":
      return "PROCESSING";

    case "ERROR":
    case "EMERGENCY_STOPPED":
      return "FAILED";

    default:
      return null;
  }
}

function shouldStartNewLifecycle(
  current: DurableStreamSessionRow | undefined,
  incoming: DurableGoLiveStatus,
): boolean {
  if (!current) {
    return true;
  }

  return TERMINAL_STATUSES.has(current.status) && !TERMINAL_STATUSES.has(incoming);
}

function startsRuntime(status: DurableGoLiveStatus): boolean {
  return [
    "STARTING",
    "LIVE",
    "DEGRADED",
    "STOPPING",
    "COMPLETE",
    "ERROR",
    "EMERGENCY_STOPPED",
  ].includes(status);
}

function reachedLive(status: DurableGoLiveStatus): boolean {
  return ["LIVE", "DEGRADED", "STOPPING", "COMPLETE"].includes(status);
}

function endsRuntime(status: DurableGoLiveStatus): boolean {
  return TERMINAL_STATUSES.has(status);
}

export async function syncDurableGoLiveSession(input: {
  readonly gameId: string;
  readonly status: GoLiveSessionStatus;
  readonly transitionAt: string;
  readonly createdByUserId?: number | null;
}): Promise<DurableGoLiveSyncResult> {
  const gameId = parseDurableGameId(input.gameId);

  if (gameId === null) {
    return {
      synced: false,
      skippedReason: "non-numeric-game-id",
      streamSessionId: null,
      recordingId: null,
    };
  }

  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    const [games] = await connection.execute<RowDataPacket[]>(
      `SELECT id, organization_id
         FROM games
         WHERE id = ?
         LIMIT 1
         FOR UPDATE`,
      [gameId],
    );

    const game = games[0];

    if (!game) {
      await connection.rollback();

      return {
        synced: false,
        skippedReason: "game-not-found",
        streamSessionId: null,
        recordingId: null,
      };
    }

    const [sessions] = await connection.execute<DurableStreamSessionRow[]>(
      `SELECT id, status, recording_id
         FROM stream_sessions
         WHERE game_id = ?
         ORDER BY id DESC
         LIMIT 1
         FOR UPDATE`,
      [gameId],
    );

    let current = sessions[0];

    if (input.status === "IDLE") {
      await connection.commit();

      return {
        synced: current !== undefined,
        skippedReason: current === undefined ? "idle-without-active-session" : null,
        streamSessionId: current ? Number(current.id) : null,
        recordingId: current?.recording_id == null ? null : Number(current.recording_id),
      };
    }

    const incoming = input.status;
    const transitionAt = new Date(input.transitionAt);
    const organizationId = Number(game.organization_id);

    let streamSessionId: number;
    let recordingId: number | null = null;

    if (shouldStartNewLifecycle(current, incoming)) {
      const [created] = await connection.execute<ResultSetHeader>(
        `INSERT INTO stream_sessions (
             session_uuid,
             organization_id,
             game_id,
             created_by_user_id,
             status,
             started_at,
             live_at,
             ended_at
           )
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          randomUUID(),
          organizationId,
          gameId,
          input.createdByUserId ?? null,
          incoming,
          startsRuntime(incoming) ? transitionAt : null,
          reachedLive(incoming) ? transitionAt : null,
          endsRuntime(incoming) ? transitionAt : null,
        ],
      );

      streamSessionId = Number(created.insertId);

      current = {
        id: streamSessionId,
        status: incoming,
        recording_id: null,
      } as DurableStreamSessionRow;
    } else {
      if (!current) {
        throw new Error("Durable go-live session unexpectedly missing");
      }

      streamSessionId = Number(current.id);
      recordingId = current.recording_id == null ? null : Number(current.recording_id);

      const assignments = ["status = ?"];
      const values: Array<string | number | Date | null> = [incoming];

      if (startsRuntime(incoming)) {
        assignments.push("started_at = COALESCE(started_at, ?)");
        values.push(transitionAt);
      }

      if (reachedLive(incoming)) {
        assignments.push("live_at = COALESCE(live_at, ?)");
        values.push(transitionAt);
      }

      if (endsRuntime(incoming)) {
        assignments.push("ended_at = COALESCE(ended_at, ?)");
        values.push(transitionAt);
      }

      values.push(streamSessionId);

      await connection.execute(
        `UPDATE stream_sessions
         SET ${assignments.join(", ")}
         WHERE id = ?`,
        values,
      );
    }

    const recordingStatus = recordingStatusForGoLiveStatus(incoming);

    if ((incoming === "LIVE" || incoming === "DEGRADED") && recordingId === null) {
      const [createdRecording] = await connection.execute<ResultSetHeader>(
        `INSERT INTO recordings (
             organization_id,
             game_id,
             owner_user_id,
             source,
             status,
             title,
             started_at
           )
           VALUES (?, ?, ?, 'LIVE', 'RECORDING', ?, ?)`,
        [
          organizationId,
          gameId,
          input.createdByUserId ?? null,
          `Game ${gameId} live recording`,
          transitionAt,
        ],
      );

      recordingId = Number(createdRecording.insertId);

      await connection.execute(
        `UPDATE stream_sessions
         SET recording_id = ?
         WHERE id = ?`,
        [recordingId, streamSessionId],
      );
    } else if (recordingId !== null && recordingStatus !== null) {
      await connection.execute(
        `UPDATE recordings
         SET status = ?,
             ended_at = CASE
               WHEN ? IN ('PROCESSING', 'FAILED')
                 THEN COALESCE(ended_at, ?)
               ELSE ended_at
             END
         WHERE id = ?`,
        [recordingStatus, recordingStatus, transitionAt, recordingId],
      );
    }

    await connection.commit();

    return {
      synced: true,
      skippedReason: null,
      streamSessionId,
      recordingId,
    };
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}

export async function syncDurableGoLiveReset(
  gameIdValue: string,
  transitionAt = new Date().toISOString(),
): Promise<DurableGoLiveSyncResult> {
  const gameId = parseDurableGameId(gameIdValue);

  if (gameId === null) {
    return {
      synced: false,
      skippedReason: "non-numeric-game-id",
      streamSessionId: null,
      recordingId: null,
    };
  }

  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    const [sessions] = await connection.execute<DurableStreamSessionRow[]>(
      `SELECT id, status, recording_id
         FROM stream_sessions
         WHERE game_id = ?
         ORDER BY id DESC
         LIMIT 1
         FOR UPDATE`,
      [gameId],
    );

    const current = sessions[0];

    if (!current || TERMINAL_STATUSES.has(current.status)) {
      await connection.commit();

      return {
        synced: current !== undefined,
        skippedReason: current === undefined ? "idle-without-active-session" : null,
        streamSessionId: current ? Number(current.id) : null,
        recordingId: current?.recording_id == null ? null : Number(current.recording_id),
      };
    }

    const endedAt = new Date(transitionAt);
    const streamSessionId = Number(current.id);
    const recordingId = current.recording_id == null ? null : Number(current.recording_id);

    await connection.execute(
      `UPDATE stream_sessions
       SET status = 'ERROR',
           ended_at = COALESCE(ended_at, ?)
       WHERE id = ?`,
      [endedAt, streamSessionId],
    );

    if (recordingId !== null) {
      await connection.execute(
        `UPDATE recordings
         SET status = 'FAILED',
             ended_at = COALESCE(ended_at, ?)
         WHERE id = ?`,
        [endedAt, recordingId],
      );
    }

    await connection.commit();

    return {
      synced: true,
      skippedReason: null,
      streamSessionId,
      recordingId,
    };
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}
