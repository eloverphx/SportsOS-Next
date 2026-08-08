import { randomUUID } from "node:crypto";
import type { RealtimeOutboxEvent } from "@sportsos/core";
import type { PoolConnection, ResultSetHeader, RowDataPacket } from "mysql2/promise";
import { pool } from "./database.js";
import { realtime } from "./realtime.js";

interface OutboxRow extends RowDataPacket {
  id: number;
  event_name: string;
  room_name: string | null;
  payload_json: string;
  attempts: number;
}

export async function enqueueRealtimeEvent(
  connection: PoolConnection,
  event: RealtimeOutboxEvent,
): Promise<void> {
  await connection.execute(
    `INSERT INTO realtime_outbox
      (event_name, room_name, payload_json)
     VALUES (?, ?, ?)`,
    [event.event, event.room ?? null, JSON.stringify(event.payload)],
  );
}

export const REALTIME_OUTBOX_CLAIM_TTL_SECONDS = 30;
export const REALTIME_OUTBOX_RETENTION_DAYS = 7;

export async function claimRealtimeOutboxBatch(
  workerId: string,
  limit = 100,
): Promise<OutboxRow[]> {
  const safeLimit = Math.max(1, Math.min(500, Math.trunc(limit)));

  await pool.execute(
    `UPDATE realtime_outbox
     SET claimed_at = UTC_TIMESTAMP(3),
         claimed_by = ?
     WHERE delivered_at IS NULL
       AND available_at <= UTC_TIMESTAMP(3)
       AND (
         claimed_at IS NULL
         OR claimed_at < DATE_SUB(
           UTC_TIMESTAMP(3),
           INTERVAL ${REALTIME_OUTBOX_CLAIM_TTL_SECONDS} SECOND
         )
       )
     ORDER BY id
     LIMIT ${safeLimit}`,
    [workerId],
  );

  const [rows] = await pool.query<OutboxRow[]>(
    `SELECT id, event_name, room_name, payload_json, attempts
     FROM realtime_outbox
     WHERE delivered_at IS NULL
       AND claimed_by = ?
     ORDER BY id
     LIMIT ${safeLimit}`,
    [workerId],
  );

  return rows;
}

export async function dispatchRealtimeOutboxBatch(
  limit = 100,
  workerId = randomUUID(),
): Promise<number> {
  const rows = await claimRealtimeOutboxBatch(workerId, limit);
  let delivered = 0;

  for (const row of rows) {
    try {
      const payload = JSON.parse(String(row.payload_json)) as unknown;
      const target = row.room_name ? realtime().to(row.room_name) : realtime();

      target.emit(String(row.event_name), payload);

      const [result] = await pool.execute<ResultSetHeader>(
        `UPDATE realtime_outbox
         SET delivered_at = UTC_TIMESTAMP(3),
             attempts = attempts + 1,
             last_error = NULL,
             claimed_at = NULL,
             claimed_by = NULL
         WHERE id = ?
           AND delivered_at IS NULL
           AND claimed_by = ?`,
        [row.id, workerId],
      );

      if (Number(result.affectedRows) > 0) delivered += 1;
    } catch (error) {
      const message =
        error instanceof Error ? error.message.slice(0, 1000) : "Realtime dispatch failed";

      await pool.execute(
        `UPDATE realtime_outbox
         SET attempts = attempts + 1,
             last_error = ?,
             available_at = DATE_ADD(
               UTC_TIMESTAMP(3),
               INTERVAL LEAST(30, POW(2, LEAST(attempts, 5))) SECOND
             ),
             claimed_at = NULL,
             claimed_by = NULL
         WHERE id = ?
           AND delivered_at IS NULL
           AND claimed_by = ?`,
        [message, row.id, workerId],
      );
    }
  }

  return delivered;
}

export async function cleanupDeliveredRealtimeOutbox(
  retentionDays = REALTIME_OUTBOX_RETENTION_DAYS,
  limit = 500,
): Promise<number> {
  const safeRetentionDays = Math.max(1, Math.min(365, Math.trunc(retentionDays)));
  const safeLimit = Math.max(1, Math.min(5000, Math.trunc(limit)));

  const [result] = await pool.execute<ResultSetHeader>(
    `DELETE FROM realtime_outbox
     WHERE delivered_at IS NOT NULL
       AND delivered_at < DATE_SUB(
         UTC_TIMESTAMP(3),
         INTERVAL ${safeRetentionDays} DAY
       )
     ORDER BY id
     LIMIT ${safeLimit}`,
  );

  return Number(result.affectedRows);
}

export function startRealtimeOutboxDispatcher(
  options: {
    intervalMs?: number;
    onError?: (error: unknown) => void;
  } = {},
): () => void {
  const intervalMs = Math.max(100, options.intervalMs ?? 250);
  const workerId = randomUUID();
  let running = false;
  let cleanupRunning = false;

  const tick = async (): Promise<void> => {
    if (running) return;
    running = true;

    try {
      await dispatchRealtimeOutboxBatch(100, workerId);
    } catch (error) {
      options.onError?.(error);
    } finally {
      running = false;
    }
  };

  const cleanup = async (): Promise<void> => {
    if (cleanupRunning) return;
    cleanupRunning = true;

    try {
      await cleanupDeliveredRealtimeOutbox();
    } catch (error) {
      options.onError?.(error);
    } finally {
      cleanupRunning = false;
    }
  };

  const timer = setInterval(() => {
    void tick();
  }, intervalMs);

  const cleanupTimer = setInterval(
    () => {
      void cleanup();
    },
    60 * 60 * 1000,
  );

  timer.unref();
  cleanupTimer.unref();
  void tick();

  return () => {
    clearInterval(timer);
    clearInterval(cleanupTimer);
  };
}
