import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { realtime } from "../../infrastructure/realtime.js";
import { audit } from "../../lib/audit.js";
import { PERMISSIONS, ROLES, requirePermission } from "../auth/index.js";
import {
  createSeason,
  deleteSeason,
  findSeasonById,
  listSeasons,
  organizationExists,
  updateSeason,
} from "./repository.js";
import { seasonInputSchema } from "./schemas.js";

const idSchema = z.coerce.number().int().positive();

export async function seasonRoutes(app: FastifyInstance): Promise<void> {
  app.get("/seasons", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.SEASON_READ,
    });

    const query = request.query as {
      organizationId?: string;
      active?: string;
      search?: string;
    };

    const organizationId = query.organizationId ? idSchema.safeParse(query.organizationId) : null;

    if (organizationId && !organizationId.success) {
      return reply.code(400).send({
        error: "Invalid organization id",
      });
    }

    const active =
      query.active === undefined
        ? undefined
        : query.active === "true"
          ? true
          : query.active === "false"
            ? false
            : undefined;

    if (query.active !== undefined && active === undefined) {
      return reply.code(400).send({
        error: "Invalid active filter",
      });
    }

    return {
      seasons: await listSeasons({
        organizationId:
          identity.role === ROLES.SYSTEM_ADMIN ? organizationId?.data : identity.organizationId,
        active,
        search: query.search,
      }),
    };
  });

  app.get("/seasons/:id", async (request, reply) => {
    const id = idSchema.safeParse((request.params as { id: string }).id);

    if (!id.success) {
      return reply.code(400).send({
        error: "Invalid season id",
      });
    }

    const season = await findSeasonById(id.data);

    if (!season) {
      return reply.code(404).send({
        error: "Season not found",
      });
    }

    await requirePermission(request, {
      permission: PERMISSIONS.SEASON_READ,
      organizationId: season.organizationId,
    });

    return { season };
  });

  app.post("/seasons", async (request, reply) => {
    const parsed = seasonInputSchema.safeParse(request.body);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid season data",
        details: parsed.error.flatten(),
      });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.SEASON_MANAGE,
      organizationId: parsed.data.organizationId,
    });

    if (!(await organizationExists(parsed.data.organizationId))) {
      return reply.code(400).send({
        error: "Organization not found",
      });
    }

    const season = await createSeason(parsed.data);

    await audit(identity.sub, "season.created", {
      seasonId: season.id,
      organizationId: season.organizationId,
      name: season.name,
    });

    realtime().emit("season:created", {
      id: season.id,
      organizationId: season.organizationId,
    });

    return reply.code(201).send({ season });
  });

  app.put("/seasons/:id", async (request, reply) => {
    const id = idSchema.safeParse((request.params as { id: string }).id);
    const parsed = seasonInputSchema.safeParse(request.body);

    if (!id.success || !parsed.success) {
      return reply.code(400).send({
        error: "Invalid season data",
        details: parsed.success ? undefined : parsed.error.flatten(),
      });
    }

    const existingSeason = await findSeasonById(id.data);

    if (!existingSeason) {
      return reply.code(404).send({
        error: "Season not found",
      });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.SEASON_MANAGE,
      organizationId: existingSeason.organizationId,
    });

    if (
      identity.role !== ROLES.SYSTEM_ADMIN &&
      parsed.data.organizationId !== existingSeason.organizationId
    ) {
      return reply.code(403).send({
        error: "You do not have permission to move this season to another organization",
      });
    }

    await requirePermission(request, {
      permission: PERMISSIONS.SEASON_MANAGE,
      organizationId: parsed.data.organizationId,
    });

    if (!(await organizationExists(parsed.data.organizationId))) {
      return reply.code(400).send({
        error: "Organization not found",
      });
    }

    const season = await updateSeason(id.data, parsed.data);

    if (!season) {
      return reply.code(404).send({
        error: "Season not found",
      });
    }

    await audit(identity.sub, "season.updated", {
      seasonId: season.id,
      previousOrganizationId: existingSeason.organizationId,
      organizationId: season.organizationId,
    });

    realtime().emit("season:updated", {
      id: season.id,
      organizationId: season.organizationId,
    });

    return { season };
  });

  app.delete("/seasons/:id", async (request, reply) => {
    const id = idSchema.safeParse((request.params as { id: string }).id);

    if (!id.success) {
      return reply.code(400).send({
        error: "Invalid season id",
      });
    }

    const season = await findSeasonById(id.data);

    if (!season) {
      return reply.code(404).send({
        error: "Season not found",
      });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.SEASON_MANAGE,
      organizationId: season.organizationId,
    });

    try {
      if (!(await deleteSeason(id.data))) {
        return reply.code(404).send({
          error: "Season not found",
        });
      }
    } catch (error) {
      if (
        typeof error === "object" &&
        error !== null &&
        "code" in error &&
        error.code === "ER_ROW_IS_REFERENCED_2"
      ) {
        return reply.code(409).send({
          error: "Season is in use and cannot be deleted",
        });
      }

      throw error;
    }

    await audit(identity.sub, "season.deleted", {
      seasonId: id.data,
      organizationId: season.organizationId,
    });

    realtime().emit("season:deleted", {
      id: id.data,
      organizationId: season.organizationId,
    });

    return { success: true };
  });
}
