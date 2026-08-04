import { z } from "zod";
import { gameStatuses } from "./types.js";

const emptyToNull = (value: unknown): unknown =>
  value === "" || value === undefined ? null : value;

const nullablePositiveId = z.preprocess(emptyToNull, z.coerce.number().int().positive().nullable());

export const gameInputSchema = z
  .object({
    organizationId: z.coerce.number().int().positive(),
    seasonId: z.coerce.number().int().positive(),

    homeTeamId: nullablePositiveId,
    homeExternalName: z.preprocess(emptyToNull, z.string().trim().min(1).max(160).nullable()),

    awayTeamId: nullablePositiveId,
    awayExternalName: z.preprocess(emptyToNull, z.string().trim().min(1).max(160).nullable()),

    scheduledStart: z.string().datetime({ offset: true }),
    timezone: z.string().trim().min(1).max(100),
    venue: z.preprocess(emptyToNull, z.string().trim().max(160).nullable()),
    status: z.enum(gameStatuses).default("SCHEDULED"),
    homeScore: z.coerce.number().int().min(0).max(999).default(0),
    awayScore: z.coerce.number().int().min(0).max(999).default(0),
    regulationPeriods: z.coerce.number().int().min(1).max(10).default(3),
    regulationPeriodLengthMs: z.coerce.number().int().min(60_000).max(7_200_000).default(1_200_000),
    intermissionLengthMs: z.coerce.number().int().min(0).max(3_600_000).default(900_000),
    overtimeEnabled: z.coerce.boolean().default(true),
    overtimeLengthMs: z.coerce.number().int().min(60_000).max(3_600_000).default(300_000),
    notes: z.preprocess(emptyToNull, z.string().trim().max(2000).nullable()),
  })
  .superRefine((value, context) => {
    if (!value.homeTeamId && !value.homeExternalName) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["homeExternalName"],
        message: "Select a registered home team or enter an external home team",
      });
    }

    if (!value.awayTeamId && !value.awayExternalName) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["awayExternalName"],
        message: "Select a registered away team or enter an external away team",
      });
    }

    if (value.homeTeamId && value.awayTeamId && value.homeTeamId === value.awayTeamId) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["awayTeamId"],
        message: "Home and away teams must be different",
      });
    }

    if (
      !value.homeTeamId &&
      !value.awayTeamId &&
      value.homeExternalName?.toLowerCase() === value.awayExternalName?.toLowerCase()
    ) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["awayExternalName"],
        message: "Home and away teams must be different",
      });
    }
  });

export const gameListQuerySchema = z.object({
  organizationId: z.coerce.number().int().positive().optional(),
  seasonId: z.coerce.number().int().positive().optional(),
  teamId: z.coerce.number().int().positive().optional(),
  status: z.enum(gameStatuses).optional(),
  search: z.string().trim().max(120).optional(),
});

export const scoreActionSchema = z.discriminatedUnion("action", [
  z.object({
    action: z.literal("adjustScore"),
    side: z.enum(["home", "away"]),
    amount: z.coerce.number().int().min(-20).max(20),
  }),
  z.object({
    action: z.literal("setScore"),
    homeScore: z.coerce.number().int().min(0).max(999),
    awayScore: z.coerce.number().int().min(0).max(999),
  }),
  z.object({ action: z.literal("startClock") }),
  z.object({ action: z.literal("pauseClock") }),
  z.object({ action: z.literal("nextPeriod") }),
  z.object({
    action: z.literal("resetClock"),
    periodLengthMs: z.coerce.number().int().min(60_000).max(7_200_000).optional(),
  }),
  z.object({
    action: z.literal("adjustClock"),
    amountMs: z.coerce.number().int().min(-3_600_000).max(3_600_000),
  }),
  z.object({
    action: z.literal("setClock"),
    clockRemainingMs: z.coerce.number().int().min(0).max(7_200_000),
  }),
  z.object({
    action: z.literal("setPeriod"),
    period: z.coerce.number().int().min(1).max(20),
  }),
  z.object({
    action: z.literal("setStatus"),
    status: z.enum(gameStatuses),
  }),
]);

export const gameIdSchema = z.coerce.number().int().positive();

export type GameInput = z.infer<typeof gameInputSchema>;
export type ScoreAction = z.infer<typeof scoreActionSchema>;
