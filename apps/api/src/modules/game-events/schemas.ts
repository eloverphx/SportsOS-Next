import { z } from "zod";
import { gameEventSides } from "./types.js";

const emptyToNull = (value: unknown): unknown =>
  value === "" || value === undefined ? null : value;
const nullablePlayerId = z.preprocess(emptyToNull, z.coerce.number().int().positive().nullable());

export const gameEventIdSchema = z.coerce.number().int().positive();

export const gameEventInputSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("GOAL"),
    side: z.enum(gameEventSides),
    playerId: nullablePlayerId,
    assist1PlayerId: nullablePlayerId,
    assist2PlayerId: nullablePlayerId,
    notes: z.preprocess(emptyToNull, z.string().trim().max(500).nullable()),
  }),
  z.object({
    type: z.literal("PENALTY"),
    side: z.enum(gameEventSides),
    playerId: nullablePlayerId,
    penaltyCode: z.string().trim().min(1).max(100),
    penaltyMinutes: z.coerce.number().min(1).max(10),
    notes: z.preprocess(emptyToNull, z.string().trim().max(500).nullable()),
  }),
]);

export type GameEventInput = z.infer<typeof gameEventInputSchema>;
