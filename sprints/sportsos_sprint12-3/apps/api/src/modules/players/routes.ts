import type { FastifyInstance } from 'fastify';
import { realtime } from '../../infrastructure/realtime.js';
import { audit } from '../../lib/audit.js';
import { authUser, requireAuth } from '../../lib/auth.js';
import { createPlayer, deletePlayer, findPlayerById, listPlayers, updatePlayer, validatePlayerRelationships } from './repository.js';
import { playerIdSchema, playerListQuerySchema, playerSchema } from './schemas.js';

export async function playerRoutes(app: FastifyInstance): Promise<void> {
  app.get('/players', { preHandler: requireAuth }, async (request, reply) => {
    const query = playerListQuerySchema.safeParse(request.query);
    if (!query.success) return reply.code(400).send({ error: 'Invalid player filters', details: query.error.flatten() });
    return { players: await listPlayers(query.data) };
  });

  app.get('/players/:id', { preHandler: requireAuth }, async (request, reply) => {
    const id = playerIdSchema.safeParse((request.params as { id: string }).id);
    if (!id.success) return reply.code(400).send({ error: 'Invalid player id' });
    const player = await findPlayerById(id.data);
    if (!player) return reply.code(404).send({ error: 'Player not found' });
    return { player, statistics: {}, history: [] };
  });

  app.post('/players', { preHandler: requireAuth }, async (request, reply) => {
    const parsed = playerSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'Invalid player data', details: parsed.error.flatten() });
    const relationError = await validatePlayerRelationships(parsed.data);
    if (relationError === 'organization') return reply.code(404).send({ error: 'Organization not found' });
    if (relationError === 'team') return reply.code(400).send({ error: 'Team does not belong to the selected organization' });
    const player = await createPlayer(parsed.data);
    await audit(authUser(request).sub, 'player.created', { playerId: player.id, name: `${player.firstName} ${player.lastName}` });
    realtime().emit('player:created', { id: player.id });
    return reply.code(201).send({ player });
  });

  app.put('/players/:id', { preHandler: requireAuth }, async (request, reply) => {
    const id = playerIdSchema.safeParse((request.params as { id: string }).id);
    const parsed = playerSchema.safeParse(request.body);
    if (!id.success || !parsed.success) return reply.code(400).send({ error: 'Invalid player data' });
    const relationError = await validatePlayerRelationships(parsed.data);
    if (relationError === 'organization') return reply.code(404).send({ error: 'Organization not found' });
    if (relationError === 'team') return reply.code(400).send({ error: 'Team does not belong to the selected organization' });
    const player = await updatePlayer(id.data, parsed.data);
    if (!player) return reply.code(404).send({ error: 'Player not found' });
    await audit(authUser(request).sub, 'player.updated', { playerId: player.id });
    realtime().emit('player:updated', { id: player.id });
    return { player };
  });

  app.delete('/players/:id', { preHandler: requireAuth }, async (request, reply) => {
    const id = playerIdSchema.safeParse((request.params as { id: string }).id);
    if (!id.success) return reply.code(400).send({ error: 'Invalid player id' });
    if (!(await deletePlayer(id.data))) return reply.code(404).send({ error: 'Player not found' });
    await audit(authUser(request).sub, 'player.deleted', { playerId: id.data });
    realtime().emit('player:deleted', { id: id.data });
    return { success: true };
  });
}
