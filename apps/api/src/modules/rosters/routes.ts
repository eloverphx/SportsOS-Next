import type { FastifyInstance } from 'fastify';
import { realtime } from '../../infrastructure/realtime.js';
import { audit } from '../../lib/audit.js';
import { authUser, requireAuth } from '../../lib/auth.js';
import {
  createRosterEntry, deleteRosterEntry, findRosterEntryById, jerseyConflict, listAvailablePlayers,
  listRoster, rosterEntryExists, updateRosterEntry, validateRosterRelationships
} from './repository.js';
import { availablePlayersQuerySchema, rosterIdSchema, rosterInputSchema, rosterListQuerySchema, rosterUpdateSchema } from './schemas.js';

export async function rosterRoutes(app: FastifyInstance): Promise<void> {
  app.get('/rosters', { preHandler: requireAuth }, async (request, reply) => {
    const parsed = rosterListQuerySchema.safeParse(request.query);
    if (!parsed.success) return reply.code(400).send({ error: 'Invalid roster filters', details: parsed.error.flatten() });
    const active = parsed.data.active === undefined ? undefined : parsed.data.active === 'true';
    return { roster: await listRoster({ seasonId: parsed.data.seasonId, teamId: parsed.data.teamId, active }) };
  });

  app.get('/rosters/available', { preHandler: requireAuth }, async (request, reply) => {
    const parsed = availablePlayersQuerySchema.safeParse(request.query);
    if (!parsed.success) return reply.code(400).send({ error: 'Invalid player filters', details: parsed.error.flatten() });
    return { players: await listAvailablePlayers(parsed.data) };
  });

  app.post('/rosters', { preHandler: requireAuth }, async (request, reply) => {
    const parsed = rosterInputSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'Invalid roster data', details: parsed.error.flatten() });
    const relationshipError = await validateRosterRelationships(parsed.data);
    if (relationshipError) return reply.code(400).send({ error: relationshipError === 'organization' ? 'Season, team, and player must belong to the same organization' : `${relationshipError[0]?.toUpperCase()}${relationshipError.slice(1)} not found` });
    if (await rosterEntryExists(parsed.data.seasonId, parsed.data.teamId, parsed.data.playerId)) return reply.code(409).send({ error: 'Player is already on this roster' });
    if (parsed.data.active && await jerseyConflict(parsed.data.seasonId, parsed.data.teamId, parsed.data.jerseyNumber)) return reply.code(409).send({ error: 'Jersey number is already assigned on this active roster' });
    const entry = await createRosterEntry(parsed.data);
    await audit(authUser(request).sub, 'roster.created', { rosterId: entry.id, teamId: entry.teamId, seasonId: entry.seasonId, playerId: entry.playerId });
    realtime().emit('roster:created', { id: entry.id, teamId: entry.teamId, seasonId: entry.seasonId });
    return reply.code(201).send({ entry });
  });

  app.put('/rosters/:id', { preHandler: requireAuth }, async (request, reply) => {
    const id = rosterIdSchema.safeParse((request.params as { id: string }).id);
    const parsed = rosterUpdateSchema.safeParse(request.body);
    if (!id.success || !parsed.success) return reply.code(400).send({ error: 'Invalid roster data', details: parsed.success ? undefined : parsed.error.flatten() });
    const existing = await findRosterEntryById(id.data);
    if (!existing) return reply.code(404).send({ error: 'Roster entry not found' });
    if (parsed.data.active && await jerseyConflict(existing.seasonId, existing.teamId, parsed.data.jerseyNumber, id.data)) return reply.code(409).send({ error: 'Jersey number is already assigned on this active roster' });
    const entry = await updateRosterEntry(id.data, parsed.data);
    if (!entry) return reply.code(404).send({ error: 'Roster entry not found' });
    await audit(authUser(request).sub, 'roster.updated', { rosterId: entry.id, teamId: entry.teamId, seasonId: entry.seasonId });
    realtime().emit('roster:updated', { id: entry.id, teamId: entry.teamId, seasonId: entry.seasonId });
    return { entry };
  });

  app.delete('/rosters/:id', { preHandler: requireAuth }, async (request, reply) => {
    const id = rosterIdSchema.safeParse((request.params as { id: string }).id);
    if (!id.success) return reply.code(400).send({ error: 'Invalid roster id' });
    const existing = await findRosterEntryById(id.data);
    if (!existing) return reply.code(404).send({ error: 'Roster entry not found' });
    await deleteRosterEntry(id.data);
    await audit(authUser(request).sub, 'roster.deleted', { rosterId: id.data, teamId: existing.teamId, seasonId: existing.seasonId, playerId: existing.playerId });
    realtime().emit('roster:deleted', { id: id.data, teamId: existing.teamId, seasonId: existing.seasonId });
    return { success: true };
  });
}
