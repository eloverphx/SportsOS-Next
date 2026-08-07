import type { FastifyInstance } from "fastify";
import { realtime } from "../../infrastructure/realtime.js";
import { audit } from "../../lib/audit.js";
import { PERMISSIONS, requirePermission } from "../auth/index.js";
import { findGameById } from "../games/repository.js";
import { gameIdSchema } from "../games/schemas.js";
import {
  createGameEvent,
  GameEventIdempotencyConflictError,
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
    const rawBody =
      request.body && typeof request.body === "object"
        ? (request.body as Record<string, unknown>)
        : {};
    const actionId = typeof rawBody.actionId === "string" ? rawBody.actionId : undefined;
    const validActionId = actionId === undefined || /^[A-Za-z0-9._:-]{8,80}$/.test(actionId);

    if (!id.success || !parsed.success || !validActionId) {
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
      const result = await createGameEvent(id.data, parsed.data, identity.sub, actionId);

      if (result.replayed) {
        return { ...result, replayed: true };
      }

      await audit(identity.sub, "game.event.created", {
        gameId: id.data,
        eventId: result.event.id,
        type: result.event.type,
      });
      realtime()
        .to(`game:${id.data}`)
        .emit("game:event-created", { gameId: id.data, event: result.event });
      realtime()
        .to(`game:${id.data}`)
        .emit("scoreboard:effect", {
          gameId: id.data,
          effectId: `game-event-${result.event.id}`,
          type: result.event.type === "GOAL" ? "GOAL" : "PENALTY",
          side: result.event.side,
          playerName: result.event.playerName,
          jerseyNumber: result.event.playerJerseyNumber,
          infraction: result.event.penaltyCode,
          penaltyMinutes: result.event.penaltyMinutes,
          createdAt: result.event.createdAt,
        });
      realtime()
        .to(`game:${id.data}`)
        .emit("scoreboard:sound", {
          gameId: id.data,
          soundId: `game-event-sound-${result.event.id}`,
          type: result.event.type === "GOAL" ? "GOAL" : "PENALTY",
        });
      realtime()
        .to(`game:${id.data}`)
        .emit("game:updated", { id: id.data, organizationId: game.organizationId });
      realtime().emit("games:changed", {
        reason: "event",
        id: id.data,
        organizationId: game.organizationId,
      });
      return reply.code(201).send(result);
    } catch (cause) {
      if (cause instanceof GameEventIdempotencyConflictError) {
        return reply.code(409).send({ error: cause.message });
      }

      return reply.code(400).send({
        error: cause instanceof Error ? cause.message : "Could not create game event",
      });
    }
  });

  app.delete("/games/:id/events/:eventId", async (request, reply) => {
    const params = request.params as { id: string; eventId: string };
    const id = gameIdSchema.safeParse(params.id);
    const eventId = gameEventIdSchema.safeParse(params.eventId);
    const actionIdHeader = request.headers["x-action-id"];
    const actionId = typeof actionIdHeader === "string" ? actionIdHeader : undefined;
    const validActionId = actionId === undefined || /^[A-Za-z0-9._:-]{8,80}$/.test(actionId);

    if (!id.success || !eventId.success || !validActionId) {
      return reply.code(400).send({ error: "Invalid game event id" });
    }
    const game = await findGameById(id.data);
    if (!game) return reply.code(404).send({ error: "Game not found" });
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_SCORE,
      organizationId: game.organizationId,
    });
    try {
      const result = await voidGameEvent(id.data, eventId.data, identity.sub, actionId);

      if (result.replayed) {
        return { ...result, replayed: true };
      }

      await audit(identity.sub, "game.event.voided", {
        gameId: id.data,
        eventId: eventId.data,
        type: result.event.type,
      });
      realtime()
        .to(`game:${id.data}`)
        .emit("game:event-voided", { gameId: id.data, event: result.event });
      realtime()
        .to(`game:${id.data}`)
        .emit("game:updated", { id: id.data, organizationId: game.organizationId });
      realtime().emit("games:changed", {
        reason: "event",
        id: id.data,
        organizationId: game.organizationId,
      });
      return result;
    } catch (cause) {
      if (cause instanceof GameEventIdempotencyConflictError) {
        return reply.code(409).send({ error: cause.message });
      }

      return reply.code(400).send({
        error: cause instanceof Error ? cause.message : "Could not void game event",
      });
    }
  });
}
