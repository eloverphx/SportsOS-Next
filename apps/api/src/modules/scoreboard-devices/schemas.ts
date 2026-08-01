import { z } from "zod";

export const scoreboardDeviceIdSchema = z.coerce.number().int().positive();

export const scoreboardDeviceListQuerySchema = z.object({
  organizationId: z.coerce.number().int().positive().optional(),
});

export const scoreboardDeviceInputSchema = z.object({
  organizationId: z.coerce.number().int().positive(),
  gameId: z.coerce.number().int().positive().nullable().optional().default(null),
  name: z.string().trim().min(1).max(160),
  location: z.string().trim().max(160).nullable().optional().default(null),
});

export const scoreboardDeviceHeartbeatSchema = z.object({
  deviceKey: z.string().trim().min(20).max(128),
});
