import type { FastifyInstance } from "fastify";
import { realtime } from "../../infrastructure/realtime.js";
import { audit } from "../../lib/audit.js";
import { PERMISSIONS, requirePermission } from "../auth/index.js";
import { findGameById } from "../games/repository.js";
import { gameIdSchema } from "../games/schemas.js";
import {
  createGameEvent,
  listGameEventPlayers,
  listGameEvents,
  voidGameEvent,
} from "./repository.js";
import { gameEventIdSchema, gameEventInputSchema } from "./schemas.js";

export async function gameEventRoutes(app: FastifyInstance): Promise<void> {
  app.get("/games/:id/events", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);
    if (!id.success) return reply.code(400).send({ error: "Invalid game id" });
    const game = await findGameById(id.data);
    if (!game) return reply.code(404).send({ error: "Game not found" });
    await requirePermission(request, {
      permission: PERMISSIONS.GAME_READ,
      organizationId: game.organizationId,
    });
    return { events: await listGameEvents(id.data) };
  });

  app.get("/games/:id/event-players", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);
    if (!id.success) return reply.code(400).send({ error: "Invalid game id" });
    const game = await findGameById(id.data);
    if (!game) return reply.code(404).send({ error: "Game not found" });
    await requirePermission(request, {
      permission: PERMISSIONS.GAME_READ,
      organizationId: game.organizationId,
    });
    return { players: await listGameEventPlayers(id.data) };
  });

  app.post("/games/:id/events", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);
    const parsed = gameEventInputSchema.safeParse(request.body);
    if (!id.success || !parsed.success) {
      return reply.code(400).send({
        error: "Invalid game event",
        details: parsed.success ? undefined : parsed.error.flatten(),
      });
    }
    const game = await findGameById(id.data);
    if (!game) return reply.code(404).send({ error: "Game not found" });
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_SCORE,
      organizationId: game.organizationId,
    });
    try {
      const result = await createGameEvent(id.data, parsed.data, identity.sub);
      await audit(identity.sub, "game.event.created", {
        gameId: id.data,
        eventId: result.event.id,
        type: result.event.type,
      });
      realtime().emit("game:event-created", { gameId: id.data, event: result.event });
      realtime().emit("game:updated", { id: id.data, organizationId: game.organizationId });
      return reply.code(201).send(result);
    } catch (cause) {
      return reply.code(400).send({
        error: cause instanceof Error ? cause.message : "Could not create game event",
      });
    }
  });

  app.delete("/games/:id/events/:eventId", async (request, reply) => {
    const params = request.params as { id: string; eventId: string };
    const id = gameIdSchema.safeParse(params.id);
    const eventId = gameEventIdSchema.safeParse(params.eventId);
    if (!id.success || !eventId.success) {
      return reply.code(400).send({ error: "Invalid game event id" });
    }
    const game = await findGameById(id.data);
    if (!game) return reply.code(404).send({ error: "Game not found" });
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_SCORE,
      organizationId: game.organizationId,
    });
    try {
      const result = await voidGameEvent(id.data, eventId.data, identity.sub);
      await audit(identity.sub, "game.event.voided", {
        gameId: id.data,
        eventId: eventId.data,
        type: result.event.type,
      });
      realtime().emit("game:event-voided", { gameId: id.data, event: result.event });
      realtime().emit("game:updated", { id: id.data, organizationId: game.organizationId });
      return result;
    } catch (cause) {
      return reply.code(400).send({
        error: cause instanceof Error ? cause.message : "Could not void game event",
      });
    }
  });
}
