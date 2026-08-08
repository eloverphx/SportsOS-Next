import type { RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import { applyGameScoringAction } from "./repository.js";

interface RegulationTransitionCandidate extends RowDataPacket {
  id: number;
  period: number;
}

interface IntermissionTransitionCandidate extends RowDataPacket {
  id: number;
  period: number;
}

export interface AutomaticLifecycleResult {
  intermissionsStarted: number;
  periodsPrepared: number;
}

export async function processAutomaticLifecycleTransitions(): Promise<AutomaticLifecycleResult> {
  const [periodEndRows] = await pool.execute<RegulationTransitionCandidate[]>(
    `SELECT id, period
     FROM games
     WHERE status = 'LIVE'
       AND game_phase = 'REGULATION'
       AND clock_running = FALSE
       AND clock_remaining_ms = 0
       AND period < regulation_periods
     ORDER BY id
     LIMIT 100`,
  );

  let intermissionsStarted = 0;

  for (const row of periodEndRows) {
    const result = await applyGameScoringAction(
      Number(row.id),
      { action: "startIntermission" },
      `runtime:period-end:${Number(row.id)}:${Number(row.period)}`,
    );

    if (result?.applied) intermissionsStarted += 1;
  }

  const [intermissionRows] = await pool.execute<IntermissionTransitionCandidate[]>(
    `SELECT id, period
     FROM games
     WHERE status = 'LIVE'
       AND game_phase = 'INTERMISSION'
       AND intermission_running = FALSE
       AND intermission_remaining_ms = 0
       AND period < regulation_periods
     ORDER BY id
     LIMIT 100`,
  );

  let periodsPrepared = 0;

  for (const row of intermissionRows) {
    const result = await applyGameScoringAction(
      Number(row.id),
      { action: "nextPeriod" },
      `runtime:intermission-complete:${Number(row.id)}:${Number(row.period)}`,
    );

    if (result?.applied) periodsPrepared += 1;
  }

  return {
    intermissionsStarted,
    periodsPrepared,
  };
}

export function startGameRuntimeSupervisor(
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
      await processAutomaticLifecycleTransitions();
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
