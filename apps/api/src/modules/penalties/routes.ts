import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { realtime } from "../../infrastructure/realtime.js";
import { audit } from "../../lib/audit.js";
import { PERMISSIONS, requirePermission } from "../auth/index.js";
import { findGameById } from "../games/repository.js";
import { gameIdSchema } from "../games/schemas.js";
import { clearPenalty, listActivePenalties } from "./repository.js";

const penaltyIdSchema = z.coerce.number().int().positive();

export async function penaltyRoutes(app: FastifyInstance): Promise<void> {
  app.get("/games/:id/penalties", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);
    if (!id.success) return reply.code(400).send({ error: "Invalid game id" });

    const game = await findGameById(id.data);
    if (!game) return reply.code(404).send({ error: "Game not found" });

    await requirePermission(request, {
      permission: PERMISSIONS.GAME_READ,
      organizationId: game.organizationId,
    });

    return { penalties: await listActivePenalties(id.data) };
  });

  app.delete("/games/:id/penalties/:penaltyId", async (request, reply) => {
    const params = request.params as { id: string; penaltyId: string };
    const id = gameIdSchema.safeParse(params.id);
    const penaltyId = penaltyIdSchema.safeParse(params.penaltyId);

    if (!id.success || !penaltyId.success) {
      return reply.code(400).send({ error: "Invalid penalty id" });
    }

    const game = await findGameById(id.data);
    if (!game) return reply.code(404).send({ error: "Game not found" });

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_SCORE,
      organizationId: game.organizationId,
    });

    if (!(await clearPenalty(id.data, penaltyId.data))) {
      return reply.code(404).send({ error: "Active penalty not found" });
    }

    await audit(identity.sub, "game.penalty.cleared", {
      gameId: id.data,
      penaltyId: penaltyId.data,
    });

    realtime().to(`game:${id.data}`).emit("game:penalties-updated", { gameId: id.data });

    return {
      success: true,
      penalties: await listActivePenalties(id.data),
    };
  });
}
