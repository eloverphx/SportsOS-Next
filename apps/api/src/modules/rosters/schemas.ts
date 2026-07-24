import { z } from 'zod';
import { playerPositions } from '../players/types.js';
import { rosterRoles } from './types.js';

const emptyToNull = (value: unknown): unknown => value === '' ? null : value;

export const rosterInputSchema = z.object({
  seasonId: z.coerce.number().int().positive(),
  teamId: z.coerce.number().int().positive(),
  playerId: z.coerce.number().int().positive(),
  jerseyNumber: z.preprocess(emptyToNull, z.coerce.number().int().min(0).max(99).nullable().optional()),
  position: z.enum(playerPositions),
  role: z.enum(rosterRoles).default('PLAYER'),
  active: z.coerce.boolean().default(true)
});

export const rosterUpdateSchema = rosterInputSchema.omit({ seasonId: true, teamId: true, playerId: true });

export const rosterListQuerySchema = z.object({
  seasonId: z.coerce.number().int().positive(),
  teamId: z.coerce.number().int().positive(),
  active: z.enum(['true', 'false']).optional()
});

export const availablePlayersQuerySchema = z.object({
  organizationId: z.coerce.number().int().positive(),
  seasonId: z.coerce.number().int().positive(),
  teamId: z.coerce.number().int().positive(),
  search: z.string().trim().max(120).optional()
});

export const rosterIdSchema = z.coerce.number().int().positive();
export type RosterInput = z.infer<typeof rosterInputSchema>;
export type RosterUpdateInput = z.infer<typeof rosterUpdateSchema>;
