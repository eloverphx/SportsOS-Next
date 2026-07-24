import { z } from 'zod';
import { playerPositions, playerShoots, playerStatuses } from './types.js';

const emptyToNull = (value: unknown): unknown => value === '' ? null : value;
const nullableText = (max: number) => z.preprocess(
  emptyToNull,
  z.string().trim().max(max).nullable().optional()
);
const optionalPositiveInt = z.preprocess(
  emptyToNull,
  z.coerce.number().int().positive().nullable().optional()
);
const optionalBoundedInt = (min: number, max: number) => z.preprocess(
  emptyToNull,
  z.coerce.number().int().min(min).max(max).nullable().optional()
);

export const playerSchema = z.object({
  organizationId: z.coerce.number().int().positive(),
  teamId: optionalPositiveInt,
  firstName: z.string().trim().min(1).max(100),
  lastName: z.string().trim().min(1).max(100),
  preferredName: nullableText(100),
  jerseyNumber: optionalBoundedInt(0, 99),
  position: z.enum(playerPositions),
  shoots: z.preprocess(emptyToNull, z.enum(playerShoots).nullable().optional()),
  birthDate: z.preprocess(
    emptyToNull,
    z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional()
  ),
  heightCm: optionalBoundedInt(50, 260),
  weightKg: optionalBoundedInt(15, 250),
  email: z.preprocess(
    emptyToNull,
    z.string().trim().email().max(255).nullable().optional()
  ),
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
