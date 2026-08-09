import type { RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import {
  createGameWithScheduleTransaction,
  type ScheduleMutationResult,
} from "./schedule-mutations.js";
import type { GameInput } from "./schemas.js";

type ParentFixture = {
  readonly organizationId: number;
  readonly seasonId: number;
};

export type ScheduleConcurrencyQualificationResult = {
  readonly passed: boolean;
  readonly committed: number;
  readonly blocked: number;
  readonly createdGameIds: readonly number[];
};

async function findParentFixture(): Promise<ParentFixture> {
  const [rows] = await pool.execute<RowDataPacket[]>(
    `SELECT
       s.organization_id,
       s.id AS season_id
     FROM seasons s
     JOIN organizations o ON o.id = s.organization_id
     ORDER BY s.id
     LIMIT 1`,
  );

  const row = rows[0];
  if (!row) {
    throw new Error(
      "Schedule concurrency qualification requires at least one existing organization with a season",
    );
  }

  return {
    organizationId: Number(row.organization_id),
    seasonId: Number(row.season_id),
  };
}

function futureQualificationStart(): string {
  const now = new Date();
  const start = new Date(now.getTime() + 180 * 24 * 60 * 60_000);
  start.setUTCMinutes(0, 0, 0);
  return start.toISOString();
}

function qualificationGame(
  fixture: ParentFixture,
  suffix: string,
  scheduledStart: string,
): GameInput {
  return {
    organizationId: fixture.organizationId,
    seasonId: fixture.seasonId,
    homeTeamId: null,
    homeExternalName: `Concurrency Home ${suffix}`,
    awayTeamId: null,
    awayExternalName: `Concurrency Away ${suffix}`,
    scheduledStart,
    timezone: "America/Chicago",
    venue: `SportsOS Concurrency Qualification ${Date.now()}`,
    status: "SCHEDULED",
    homeScore: 0,
    awayScore: 0,
    regulationPeriods: 3,
    regulationPeriodLengthMs: 20 * 60_000,
    intermissionLengthMs: 10 * 60_000,
    overtimeEnabled: false,
    overtimeLengthMs: 0,
    notes: "SportsOS Milestone 6.14 temporary concurrency qualification",
  };
}

function isWritten(
  result: ScheduleMutationResult,
): result is Extract<ScheduleMutationResult, { outcome: "written" }> {
  return result.outcome === "written";
}

export async function runScheduleConcurrencyQualification(): Promise<ScheduleConcurrencyQualificationResult> {
  const fixture = await findParentFixture();
  const scheduledStart = futureQualificationStart();
  const base = qualificationGame(fixture, "A", scheduledStart);

  // Both inputs intentionally target exactly the same organization, rink and time.
  // They differ only by external matchup names.
  const first: GameInput = {
    ...base,
    homeExternalName: "Concurrency Home A",
    awayExternalName: "Concurrency Away A",
  };

  const second: GameInput = {
    ...base,
    homeExternalName: "Concurrency Home B",
    awayExternalName: "Concurrency Away B",
  };

  const createdGameIds: number[] = [];

  try {
    const results = await Promise.all([
      createGameWithScheduleTransaction(first, false),
      createGameWithScheduleTransaction(second, false),
    ]);

    for (const result of results) {
      if (isWritten(result)) {
        createdGameIds.push(result.game.id);
      }
    }

    const committed = results.filter((result) => result.outcome === "written").length;
    const blocked = results.filter((result) => result.outcome === "blocked").length;
    const passed = committed === 1 && blocked === 1;

    if (!passed) {
      throw new Error(
        `Concurrency qualification failed: expected 1 committed and 1 blocked, got ${committed} committed and ${blocked} blocked`,
      );
    }

    return {
      passed,
      committed,
      blocked,
      createdGameIds,
    };
  } finally {
    if (createdGameIds.length > 0) {
      const placeholders = createdGameIds.map(() => "?").join(", ");
      await pool.execute(
        `DELETE FROM games
         WHERE id IN (${placeholders})
           AND notes = ?`,
        [
          ...createdGameIds,
          "SportsOS Milestone 6.14 temporary concurrency qualification",
        ],
      );
    }
  }
}
