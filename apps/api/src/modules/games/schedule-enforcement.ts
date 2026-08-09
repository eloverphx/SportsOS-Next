import type { GameInput } from "./schemas.js";
import type { Game } from "./types.js";
import { listGames, listGameTeamOptions } from "./repository.js";
import {
  detectServerScheduleConflicts,
  hasHardScheduleConflicts,
  type ProposedScheduleGame,
  type ServerScheduleConflict,
} from "./schedule-conflicts.js";

export const MAX_SCHEDULE_OVERRIDE_REASON_LENGTH = 500;

export type ScheduleEvaluation = {
  readonly conflicts: readonly ServerScheduleConflict[];
  readonly hardConflict: boolean;
};

export type ScheduleOverride = {
  readonly override: boolean;
  readonly reason: string | null;
  readonly reasonTooLong: boolean;
};

export function parseScheduleOverride(body: unknown): ScheduleOverride {
  const record =
    body && typeof body === "object"
      ? (body as Record<string, unknown>)
      : {};

  const override = record.scheduleConflictOverride === true;
  const rawReason =
    typeof record.scheduleConflictOverrideReason === "string"
      ? record.scheduleConflictOverrideReason.trim()
      : "";

  return {
    override,
    reason: rawReason.length > 0 ? rawReason : null,
    reasonTooLong: rawReason.length > MAX_SCHEDULE_OVERRIDE_REASON_LENGTH,
  };
}

export function scheduleRelevantFieldsChanged(
  existing: Game,
  input: GameInput,
): boolean {
  return (
    existing.scheduledStart !== input.scheduledStart ||
    (existing.venue ?? null) !== (input.venue ?? null) ||
    existing.homeTeamId !== input.homeTeamId ||
    existing.awayTeamId !== input.awayTeamId ||
    existing.status !== input.status ||
    existing.regulationPeriods !== input.regulationPeriods ||
    existing.regulationPeriodLengthMs !== input.regulationPeriodLengthMs ||
    existing.intermissionLengthMs !== input.intermissionLengthMs ||
    existing.overtimeEnabled !== input.overtimeEnabled ||
    existing.overtimeLengthMs !== input.overtimeLengthMs
  );
}

async function resolveTeamNames(input: {
  readonly homeTeamId: number | null;
  readonly awayTeamId: number | null;
  readonly homeExternalName: string | null;
  readonly awayExternalName: string | null;
}): Promise<{
  readonly homeTeamName: string;
  readonly awayTeamName: string;
}> {
  const teams = await listGameTeamOptions();

  const homeTeamName =
    input.homeTeamId === null
      ? input.homeExternalName
      : teams.find((team) => team.id === input.homeTeamId)?.name ?? null;

  const awayTeamName =
    input.awayTeamId === null
      ? input.awayExternalName
      : teams.find((team) => team.id === input.awayTeamId)?.name ?? null;

  if (!homeTeamName || !awayTeamName) {
    throw new Error("Could not resolve team names for schedule validation");
  }

  return { homeTeamName, awayTeamName };
}

async function evaluate(
  organizationId: number,
  proposed: ProposedScheduleGame,
): Promise<ScheduleEvaluation> {
  const existingGames = await listGames({ organizationId });
  const conflicts = detectServerScheduleConflicts(proposed, existingGames);

  return {
    conflicts,
    hardConflict: hasHardScheduleConflicts(conflicts),
  };
}

export async function evaluateGameInputSchedule(
  gameId: number,
  input: GameInput,
): Promise<ScheduleEvaluation> {
  const names = await resolveTeamNames(input);

  return evaluate(input.organizationId, {
    id: gameId,
    homeTeamId: input.homeTeamId,
    awayTeamId: input.awayTeamId,
    homeTeamName: names.homeTeamName,
    awayTeamName: names.awayTeamName,
    scheduledStart: input.scheduledStart,
    venue: input.venue,
    status: input.status,
    regulationPeriods: input.regulationPeriods,
    regulationPeriodLengthMs: input.regulationPeriodLengthMs,
    intermissionLengthMs: input.intermissionLengthMs,
    overtimeEnabled: input.overtimeEnabled,
    overtimeLengthMs: input.overtimeLengthMs,
  });
}

export async function evaluateNewGameSchedule(
  input: GameInput,
): Promise<ScheduleEvaluation> {
  return evaluateGameInputSchedule(0, input);
}

export async function evaluateSchedulePreview(
  game: Game,
  proposed: {
    readonly scheduledStart: string;
    readonly venue: string | null;
  },
): Promise<ScheduleEvaluation> {
  return evaluate(game.organizationId, {
    id: game.id,
    homeTeamId: game.homeTeamId,
    awayTeamId: game.awayTeamId,
    homeTeamName: game.homeTeamName,
    awayTeamName: game.awayTeamName,
    scheduledStart: proposed.scheduledStart,
    venue: proposed.venue,
    status: game.status,
    regulationPeriods: game.regulationPeriods,
    regulationPeriodLengthMs: game.regulationPeriodLengthMs,
    intermissionLengthMs: game.intermissionLengthMs,
    overtimeEnabled: game.overtimeEnabled,
    overtimeLengthMs: game.overtimeLengthMs,
  });
}
