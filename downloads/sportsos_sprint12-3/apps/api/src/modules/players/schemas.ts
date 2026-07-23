import { z } from 'zod';
import { playerPositions, playerShoots, playerStatuses } from './types.js';

const nullableText = (max: number) => z.string().trim().max(max).nullable().optional();
const optionalPositiveInt = z.number().int().positive().nullable().optional();

export const playerSchema = z.object({
  organizationId: z.number().int().positive(),
  teamId: optionalPositiveInt,
  firstName: z.string().trim().min(1).max(100),
  lastName: z.string().trim().min(1).max(100),
  preferredName: nullableText(100),
  jerseyNumber: z.number().int().min(0).max(99).nullable().optional(),
  position: z.enum(playerPositions),
  shoots: z.enum(playerShoots).nullable().optional(),
  birthDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  heightCm: z.number().int().min(50).max(260).nullable().optional(),
  weightKg: z.number().int().min(15).max(250).nullable().optional(),
  email: z.string().trim().email().max(255).nullable().optional(),
  phone: nullableText(50),
  photoAssetId: optionalPositiveInt,
  status: z.enum(playerStatuses).default('ACTIVE')
});

export const playerListQuerySchema = z.object({
  organizationId: z.coerce.number().int().positive().optional(),
  teamId: z.coerce.number().int().positive().optional(),
  position: z.enum(playerPositions).optional(),
  status: z.enum(playerStatuses).optional(),
  search: z.string().trim().max(120).optional()
});

export const playerIdSchema = z.coerce.number().int().positive();
export type PlayerInput = z.infer<typeof playerSchema>;
