import type { PoolConnection, ResultSetHeader, RowDataPacket } from "mysql2/promise";
import { pool } from "./database.js";
import { realtime } from "./realtime.js";

export interface RealtimeOutboxEvent {
  readonly event: string;
  readonly room?: string | null;
  readonly payload: unknown;
}

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

export async function dispatchRealtimeOutboxBatch(limit = 100): Promise<number> {
  const safeLimit = Math.max(1, Math.min(500, Math.trunc(limit)));

  const [rows] = await pool.query<OutboxRow[]>(
    `SELECT id, event_name, room_name, payload_json, attempts
     FROM realtime_outbox
     WHERE delivered_at IS NULL
       AND available_at <= UTC_TIMESTAMP(3)
     ORDER BY id
     LIMIT ${safeLimit}`,
  );

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
             last_error = NULL
         WHERE id = ? AND delivered_at IS NULL`,
        [row.id],
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
             )
         WHERE id = ? AND delivered_at IS NULL`,
        [message, row.id],
      );
    }
  }

  return delivered;
}

export function startRealtimeOutboxDispatcher(
  options: {
    intervalMs?: number;
    onError?: (error: unknown) => void;
  } = {},
): () => void {
  const intervalMs = Math.max(100, options.intervalMs ?? 250);
  let running = false;

  const tick = async (): Promise<void> => {
    if (running) return;
    running = true;

    try {
      await dispatchRealtimeOutboxBatch();
    } catch (error) {
      options.onError?.(error);
    } finally {
      running = false;
    }
  };

  const timer = setInterval(() => {
    void tick();
  }, intervalMs);

  timer.unref();
  void tick();

  return () => clearInterval(timer);
}
