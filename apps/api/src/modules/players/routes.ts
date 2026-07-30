import type { FastifyInstance } from "fastify";
import { realtime } from "../../infrastructure/realtime.js";
import { audit } from "../../lib/audit.js";
import { PERMISSIONS, ROLES, requirePermission } from "../auth/index.js";
import {
  createPlayer,
  deletePlayer,
  findPlayerById,
  listPlayers,
  updatePlayer,
  validatePlayerRelationships,
} from "./repository.js";
import { playerIdSchema, playerListQuerySchema, playerSchema } from "./schemas.js";

export async function playerRoutes(app: FastifyInstance): Promise<void> {
  app.get("/players", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.PLAYER_READ,
    });

    const query = playerListQuerySchema.safeParse(request.query);

    if (!query.success) {
      return reply.code(400).send({
        error: "Invalid player filters",
        details: query.error.flatten(),
      });
    }

    const filters =
      identity.role === ROLES.SYSTEM_ADMIN
        ? query.data
        : {
            ...query.data,
            organizationId: identity.organizationId,
          };

    return { players: await listPlayers(filters) };
  });

  app.get("/players/:id", async (request, reply) => {
    const id = playerIdSchema.safeParse((request.params as { id: string }).id);

    if (!id.success) {
      return reply.code(400).send({ error: "Invalid player id" });
    }

    const player = await findPlayerById(id.data);

    if (!player) {
      return reply.code(404).send({ error: "Player not found" });
    }

    await requirePermission(request, {
      permission: PERMISSIONS.PLAYER_READ,
      organizationId: player.organizationId,
    });

    return { player, statistics: {}, history: [] };
  });

  app.post("/players", async (request, reply) => {
    const parsed = playerSchema.safeParse(request.body);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid player data",
        details: parsed.error.flatten(),
      });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.PLAYER_MANAGE,
      organizationId: parsed.data.organizationId,
    });

    const relationError = await validatePlayerRelationships(parsed.data);

    if (relationError === "organization") {
      return reply.code(404).send({ error: "Organization not found" });
    }

    if (relationError === "team") {
      return reply.code(400).send({
        error: "Team does not belong to the selected organization",
      });
    }

    const player = await createPlayer(parsed.data);

    await audit(identity.sub, "player.created", {
      playerId: player.id,
      organizationId: player.organizationId,
      name: `${player.firstName} ${player.lastName}`,
    });

    realtime().emit("player:created", {
      id: player.id,
      organizationId: player.organizationId,
    });

    return reply.code(201).send({ player });
  });

  app.put("/players/:id", async (request, reply) => {
    const id = playerIdSchema.safeParse((request.params as { id: string }).id);
    const parsed = playerSchema.safeParse(request.body);

    if (!id.success) {
      return reply.code(400).send({
        error: "Invalid player id",
        details: id.error.flatten(),
      });
    }

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid player data",
        details: parsed.error.flatten(),
      });
    }

    const existingPlayer = await findPlayerById(id.data);

    if (!existingPlayer) {
      return reply.code(404).send({ error: "Player not found" });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.PLAYER_MANAGE,
      organizationId: existingPlayer.organizationId,
    });

    if (
      identity.role !== ROLES.SYSTEM_ADMIN &&
      parsed.data.organizationId !== existingPlayer.organizationId
    ) {
      return reply.code(403).send({
        error: "You do not have permission to move this player to another organization",
      });
    }

    await requirePermission(request, {
      permission: PERMISSIONS.PLAYER_MANAGE,
      organizationId: parsed.data.organizationId,
    });

    const relationError = await validatePlayerRelationships(parsed.data);

    if (relationError === "organization") {
      return reply.code(404).send({ error: "Organization not found" });
    }

    if (relationError === "team") {
      return reply.code(400).send({
        error: "Team does not belong to the selected organization",
      });
    }

    const player = await updatePlayer(id.data, parsed.data);

    if (!player) {
      return reply.code(404).send({ error: "Player not found" });
    }

    await audit(identity.sub, "player.updated", {
      playerId: player.id,
      previousOrganizationId: existingPlayer.organizationId,
      organizationId: player.organizationId,
    });

    realtime().emit("player:updated", {
      id: player.id,
      organizationId: player.organizationId,
    });

    return { player };
  });

  app.delete("/players/:id", async (request, reply) => {
    const id = playerIdSchema.safeParse((request.params as { id: string }).id);

    if (!id.success) {
      return reply.code(400).send({ error: "Invalid player id" });
    }

    const player = await findPlayerById(id.data);

    if (!player) {
      return reply.code(404).send({ error: "Player not found" });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.PLAYER_MANAGE,
      organizationId: player.organizationId,
    });

    if (!(await deletePlayer(id.data))) {
      return reply.code(404).send({ error: "Player not found" });
    }

    await audit(identity.sub, "player.deleted", {
      playerId: id.data,
      organizationId: player.organizationId,
    });

    realtime().emit("player:deleted", {
      id: id.data,
      organizationId: player.organizationId,
    });

    return { success: true };
  });
}
