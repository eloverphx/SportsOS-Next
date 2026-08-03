import mysql, { type PoolConnection, type RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import type { ActivePenalty, PenaltySide } from "./types.js";

const SELECT_ACTIVE = `SELECT gp.*, p.first_name, p.last_name, p.preferred_name,
  ge.penalty_code, p.jersey_number
FROM game_penalties gp
JOIN game_events ge ON ge.id = gp.game_event_id
LEFT JOIN players p ON p.id = ge.player_id`;

function effectiveRemaining(row: RowDataPacket, now = Date.now()): number {
  const stored = Number(row.remaining_ms);
  if (!row.running || !row.started_at) return Math.max(0, stored);
  return Math.max(0, stored - (now - new Date(row.started_at).getTime()));
}

function mapPenalty(row: RowDataPacket): ActivePenalty {
  const first = row.preferred_name || row.first_name;
  const remainingMs = effectiveRemaining(row);
  return {
    id: Number(row.id),
    gameEventId: Number(row.game_event_id),
    gameId: Number(row.game_id),
    side: row.side,
    playerName: first == null ? null : `${first} ${row.last_name || ""}`.trim(),
    jerseyNumber: row.jersey_number == null ? null : Number(row.jersey_number),
    infraction: String(row.penalty_code || "Penalty"),
    originalDurationMs: Number(row.original_duration_ms),
    remainingMs,
    running: Boolean(row.running) && remainingMs > 0,
    startedAt: Boolean(row.running) && remainingMs > 0 ? new Date().toISOString() : null,
    createdAt: (row.created_at instanceof Date
      ? row.created_at
      : new Date(String(row.created_at))
    ).toISOString(),
  };
}

export async function listActivePenalties(gameId: number): Promise<ActivePenalty[]> {
  const [rows] = await pool.execute<RowDataPacket[]>(
    `${SELECT_ACTIVE}
     WHERE gp.game_id = ? AND gp.cleared_at IS NULL
     ORDER BY gp.id`,
    [gameId],
  );
  return rows.map(mapPenalty).filter((penalty) => penalty.remainingMs > 0);
}

export async function createPenaltyClock(
  connection: PoolConnection,
  input: {
    gameEventId: number;
    gameId: number;
    side: PenaltySide;
    durationMs: number;
    gameClockRunning: boolean;
  },
): Promise<void> {
  await connection.execute(
    `INSERT INTO game_penalties (
      game_event_id, game_id, side, original_duration_ms,
      remaining_ms, running, started_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [
      input.gameEventId,
      input.gameId,
      input.side,
      input.durationMs,
      input.durationMs,
      input.gameClockRunning,
      input.gameClockRunning ? new Date() : null,
    ],
  );
}

export async function materializePenaltyClocks(
  connection: PoolConnection,
  gameId: number,
): Promise<void> {
  const [rows] = await connection.execute<RowDataPacket[]>(
    `SELECT id, remaining_ms, running, started_at
     FROM game_penalties
     WHERE game_id = ? AND cleared_at IS NULL
     FOR UPDATE`,
    [gameId],
  );

  const now = Date.now();
  for (const row of rows) {
    const remaining = effectiveRemaining(row, now);
    await connection.execute(
      `UPDATE game_penalties
       SET remaining_ms = ?, running = FALSE, started_at = NULL,
           cleared_at = CASE WHEN ? = 0 THEN CURRENT_TIMESTAMP(3) ELSE cleared_at END,
           clear_reason = CASE WHEN ? = 0 THEN 'EXPIRED' ELSE clear_reason END
       WHERE id = ?`,
      [remaining, remaining, remaining, row.id],
    );
  }
}

export async function setPenaltyClockRunning(
  connection: PoolConnection,
  gameId: number,
  running: boolean,
): Promise<void> {
  await connection.execute(
    `UPDATE game_penalties
     SET running = ?, started_at = ?
     WHERE game_id = ? AND cleared_at IS NULL AND remaining_ms > 0`,
    [running, running ? new Date() : null, gameId],
  );
}

export async function clearPenalty(
  gameId: number,
  penaltyId: number,
  reason = "MANUAL",
): Promise<boolean> {
  const [result] = await pool.execute<mysql.ResultSetHeader>(
    `UPDATE game_penalties
     SET cleared_at = CURRENT_TIMESTAMP(3), clear_reason = ?,
         running = FALSE, started_at = NULL
     WHERE id = ? AND game_id = ? AND cleared_at IS NULL`,
    [reason, penaltyId, gameId],
  );
  return result.affectedRows > 0;
}

export async function clearPenaltyForVoidedEvent(
  connection: PoolConnection,
  gameEventId: number,
): Promise<void> {
  await connection.execute(
    `UPDATE game_penalties
     SET cleared_at = CURRENT_TIMESTAMP(3), clear_reason = 'EVENT_VOIDED',
         running = FALSE, started_at = NULL
     WHERE game_event_id = ? AND cleared_at IS NULL`,
    [gameEventId],
  );
}

export async function clearEarliestEligibleMinorOnGoal(
  connection: PoolConnection,
  gameId: number,
  scoringSide: PenaltySide,
): Promise<number | null> {
  const penalizedSide = scoringSide === "home" ? "away" : "home";

  const [counts] = await connection.execute<RowDataPacket[]>(
    `SELECT side, COUNT(*) count
     FROM game_penalties
     WHERE game_id = ? AND cleared_at IS NULL AND remaining_ms > 0
     GROUP BY side`,
    [gameId],
  );
  const bySide = new Map(counts.map((row) => [String(row.side), Number(row.count)]));
  if ((bySide.get(penalizedSide) ?? 0) <= (bySide.get(scoringSide) ?? 0)) return null;

  const [rows] = await connection.execute<RowDataPacket[]>(
    `SELECT id FROM game_penalties
     WHERE game_id = ? AND side = ? AND cleared_at IS NULL
       AND remaining_ms > 0 AND original_duration_ms <= 120000
     ORDER BY id LIMIT 1 FOR UPDATE`,
    [gameId, penalizedSide],
  );
  const id = rows[0] ? Number(rows[0].id) : null;
  if (id === null) return null;

  await connection.execute(
    `UPDATE game_penalties
     SET cleared_at = CURRENT_TIMESTAMP(3), clear_reason = 'POWER_PLAY_GOAL',
         running = FALSE, started_at = NULL
     WHERE id = ?`,
    [id],
  );
  return id;
}

export async function adjustActivePenaltyClocks(
  connection: PoolConnection,
  gameId: number,
  amountMs: number,
): Promise<void> {
  if (amountMs === 0) return;

  const [rows] = await connection.execute<RowDataPacket[]>(
    `SELECT id, original_duration_ms, remaining_ms
     FROM game_penalties
     WHERE game_id = ? AND cleared_at IS NULL
     FOR UPDATE`,
    [gameId],
  );

  for (const row of rows) {
    const remainingMs = Math.max(
      0,
      Math.min(Number(row.original_duration_ms), Number(row.remaining_ms) + amountMs),
    );

    await connection.execute(
      `UPDATE game_penalties
       SET remaining_ms = ?,
           cleared_at = CASE
             WHEN ? = 0 THEN CURRENT_TIMESTAMP(3)
             ELSE NULL
           END,
           clear_reason = CASE
             WHEN ? = 0 THEN 'EXPIRED'
             ELSE NULL
           END
       WHERE id = ?`,
      [remainingMs, remainingMs, remainingMs, row.id],
    );
  }
}
