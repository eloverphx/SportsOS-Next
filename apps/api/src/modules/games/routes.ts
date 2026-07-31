import type { FastifyInstance } from "fastify";
import { realtime } from "../../infrastructure/realtime.js";
import { audit } from "../../lib/audit.js";
import { PERMISSIONS, ROLES, requirePermission } from "../auth/index.js";
import {
  createGame,
  deleteGame,
  findGameById,
  listGames,
  updateGame,
  validateGameRelationships,
} from "./repository.js";
import { gameIdSchema, gameInputSchema, gameListQuerySchema } from "./schemas.js";

function relationshipErrorMessage(
  error: "organization" | "season" | "homeTeam" | "awayTeam",
): string {
  switch (error) {
    case "organization":
      return "Organization not found";
    case "season":
      return "Season does not belong to the selected organization";
    case "homeTeam":
      return "Home team does not belong to the selected organization";
    case "awayTeam":
      return "Away team does not belong to the selected organization";
  }
}

export async function gameRoutes(app: FastifyInstance): Promise<void> {
  app.get("/games", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_READ,
    });

    const parsed = gameListQuerySchema.safeParse(request.query);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid game filters",
        details: parsed.error.flatten(),
      });
    }

    return {
      games: await listGames(
        identity.role === ROLES.SYSTEM_ADMIN
          ? parsed.data
          : {
              ...parsed.data,
              organizationId: identity.organizationId,
            },
      ),
    };
  });

  app.get("/games/:id", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);

    if (!id.success) {
      return reply.code(400).send({
        error: "Invalid game id",
      });
    }

    const game = await findGameById(id.data);

    if (!game) {
      return reply.code(404).send({
        error: "Game not found",
      });
    }

    await requirePermission(request, {
      permission: PERMISSIONS.GAME_READ,
      organizationId: game.organizationId,
    });

    return { game };
  });

  app.post("/games", async (request, reply) => {
    const parsed = gameInputSchema.safeParse(request.body);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid game data",
        details: parsed.error.flatten(),
      });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
      organizationId: parsed.data.organizationId,
    });

    const relationshipError = await validateGameRelationships(parsed.data);

    if (relationshipError) {
      return reply.code(400).send({
        error: relationshipErrorMessage(relationshipError),
      });
    }

    const game = await createGame(parsed.data);

    await audit(identity.sub, "game.created", {
      gameId: game.id,
      organizationId: game.organizationId,
      seasonId: game.seasonId,
      homeTeamId: game.homeTeamId,
      awayTeamId: game.awayTeamId,
    });

    realtime().emit("game:created", {
      id: game.id,
      organizationId: game.organizationId,
    });

    return reply.code(201).send({ game });
  });

  app.put("/games/:id", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);
    const parsed = gameInputSchema.safeParse(request.body);

    if (!id.success || !parsed.success) {
      return reply.code(400).send({
        error: "Invalid game data",
        details: parsed.success ? undefined : parsed.error.flatten(),
      });
    }

    const existing = await findGameById(id.data);

    if (!existing) {
      return reply.code(404).send({
        error: "Game not found",
      });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
      organizationId: existing.organizationId,
    });

    if (
      identity.role !== ROLES.SYSTEM_ADMIN &&
      parsed.data.organizationId !== existing.organizationId
    ) {
      return reply.code(403).send({
        error: "You do not have permission to move this game to another organization",
      });
    }

    await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
      organizationId: parsed.data.organizationId,
    });

    const relationshipError = await validateGameRelationships(parsed.data);

    if (relationshipError) {
      return reply.code(400).send({
        error: relationshipErrorMessage(relationshipError),
      });
    }

    const game = await updateGame(id.data, parsed.data);

    if (!game) {
      return reply.code(404).send({
        error: "Game not found",
      });
    }

    await audit(identity.sub, "game.updated", {
      gameId: game.id,
      previousOrganizationId: existing.organizationId,
      organizationId: game.organizationId,
    });

    realtime().emit("game:updated", {
      id: game.id,
      organizationId: game.organizationId,
    });

    return { game };
  });

  app.delete("/games/:id", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);

    if (!id.success) {
      return reply.code(400).send({
        error: "Invalid game id",
      });
    }

    const game = await findGameById(id.data);

    if (!game) {
      return reply.code(404).send({
        error: "Game not found",
      });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
      organizationId: game.organizationId,
    });

    if (!(await deleteGame(id.data))) {
      return reply.code(404).send({
        error: "Game not found",
      });
    }

    await audit(identity.sub, "game.deleted", {
      gameId: id.data,
      organizationId: game.organizationId,
    });

    realtime().emit("game:deleted", {
      id: id.data,
      organizationId: game.organizationId,
    });

    return { success: true };
  });
}
