import type { PoolConnection, RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import { realtime } from "../../infrastructure/realtime.js";
import { materializePenaltyClocks } from "../penalties/repository.js";
import { findGameById } from "./repository.js";

interface ExpirationCandidate extends RowDataPacket {
  id: number;
  organization_id: number;
  clock_remaining_ms: number;
  clock_running: number;
  clock_started_at: Date | null;
  intermission_remaining_ms: number;
  intermission_running: number;
  intermission_started_at: Date | null;
}

export interface ClockExpirationResult {
  gameId: number;
  organizationId: number;
  gameClockExpired: boolean;
  intermissionExpired: boolean;
}

function elapsedMs(startedAt: Date | string | null, nowMs: number): number {
  if (!startedAt) return 0;
  const timestamp = startedAt instanceof Date ? startedAt.getTime() : new Date(startedAt).getTime();
  return Number.isFinite(timestamp) ? Math.max(0, nowMs - timestamp) : 0;
}

export function hasExpired(
  running: boolean,
  remainingMs: number,
  startedAt: Date | string | null,
  nowMs = Date.now(),
): boolean {
  return running && remainingMs > 0 && elapsedMs(startedAt, nowMs) >= remainingMs;
}

async function lockCandidate(
  connection: PoolConnection,
  gameId: number,
): Promise<ExpirationCandidate | null> {
  const [rows] = await connection.execute<ExpirationCandidate[]>(
    `SELECT
       id,
       organization_id,
       clock_remaining_ms,
       clock_running,
       clock_started_at,
       intermission_remaining_ms,
       intermission_running,
       intermission_started_at
     FROM games
     WHERE id = ?
     FOR UPDATE`,
    [gameId],
  );

  return rows[0] ?? null;
}

export async function materializeGameClockExpiration(
  gameId: number,
  nowMs = Date.now(),
): Promise<ClockExpirationResult | null> {
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    const row = await lockCandidate(connection, gameId);
    if (!row) {
      await connection.rollback();
      return null;
    }

    const gameClockExpired = hasExpired(
      Boolean(row.clock_running),
      Number(row.clock_remaining_ms),
      row.clock_started_at,
      nowMs,
    );

    const intermissionExpired = hasExpired(
      Boolean(row.intermission_running),
      Number(row.intermission_remaining_ms),
      row.intermission_started_at,
      nowMs,
    );

    if (!gameClockExpired && !intermissionExpired) {
      await connection.rollback();
      return null;
    }

    if (gameClockExpired) {
      await materializePenaltyClocks(connection, gameId);

      await connection.execute(
        `UPDATE games
         SET clock_remaining_ms = 0,
             clock_running = FALSE,
             clock_started_at = NULL
         WHERE id = ? AND clock_running = TRUE`,
        [gameId],
      );
    }

    if (intermissionExpired) {
      await connection.execute(
        `UPDATE games
         SET intermission_remaining_ms = 0,
             intermission_running = FALSE,
             intermission_started_at = NULL
         WHERE id = ? AND intermission_running = TRUE`,
        [gameId],
      );
    }

    await connection.commit();

    return {
      gameId,
      organizationId: Number(row.organization_id),
      gameClockExpired,
      intermissionExpired,
    };
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}

export async function processExpiredGameClocks(nowMs = Date.now()): Promise<number> {
  const [rows] = await pool.execute<ExpirationCandidate[]>(
    `SELECT
       id,
       organization_id,
       clock_remaining_ms,
       clock_running,
       clock_started_at,
       intermission_remaining_ms,
       intermission_running,
       intermission_started_at
     FROM games
     WHERE
       (clock_running = TRUE AND clock_started_at IS NOT NULL)
       OR
       (intermission_running = TRUE AND intermission_started_at IS NOT NULL)
     ORDER BY id
     LIMIT 100`,
  );

  let processed = 0;

  for (const row of rows) {
    const gameExpired = hasExpired(
      Boolean(row.clock_running),
      Number(row.clock_remaining_ms),
      row.clock_started_at,
      nowMs,
    );
    const intermissionExpired = hasExpired(
      Boolean(row.intermission_running),
      Number(row.intermission_remaining_ms),
      row.intermission_started_at,
      nowMs,
    );

    if (!gameExpired && !intermissionExpired) continue;

    const result = await materializeGameClockExpiration(Number(row.id), nowMs);
    if (!result) continue;

    const game = await findGameById(result.gameId);
    if (!game) continue;

    if (result.gameClockExpired) {
      realtime().to(`game:${game.id}`).emit("game:clock-expired", {
        game,
        gameId: game.id,
        organizationId: game.organizationId,
      });

      realtime()
        .to(`game:${game.id}`)
        .emit("scoreboard:sound", {
          gameId: game.id,
          soundId: `period-end-${game.id}-${game.period}-${Date.now()}`,
          type: "HORN",
        });
    }

    if (result.intermissionExpired) {
      realtime().to(`game:${game.id}`).emit("game:intermission-expired", {
        game,
        gameId: game.id,
        organizationId: game.organizationId,
      });

      realtime()
        .to(`game:${game.id}`)
        .emit("scoreboard:sound", {
          gameId: game.id,
          soundId: `intermission-complete-${game.id}-${game.period}-${Date.now()}`,
          type: "INTERMISSION_COMPLETE",
        });
    }

    realtime().to(`game:${game.id}`).emit("game:updated", {
      id: game.id,
      organizationId: game.organizationId,
    });
    realtime().emit("games:changed", {
      reason: result.gameClockExpired ? "clock-expired" : "intermission-expired",
      id: game.id,
      organizationId: game.organizationId,
    });

    processed += 1;
  }

  return processed;
}

export function startClockExpirationService(
  options: {
    intervalMs?: number;
    onError?: (error: unknown) => void;
  } = {},
): () => void {
  const intervalMs = Math.max(250, options.intervalMs ?? 500);
  let running = false;

  const tick = async (): Promise<void> => {
    if (running) return;
    running = true;

    try {
      await processExpiredGameClocks();
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
