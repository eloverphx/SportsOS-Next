import type { FastifyInstance } from "fastify";
import { realtime } from "../../infrastructure/realtime.js";
import { audit } from "../../lib/audit.js";
import { PERMISSIONS, ROLES, requirePermission } from "../auth/index.js";
import {
  createScoreboardDevice,
  deleteScoreboardDevice,
  findScoreboardDeviceById,
  listScoreboardDevices,
  recordScoreboardHeartbeat,
  rotateScoreboardDeviceKey,
  updateScoreboardDevice,
  validateScoreboardDeviceRelationships,
} from "./repository.js";
import {
  scoreboardDeviceHeartbeatSchema,
  scoreboardDeviceIdSchema,
  scoreboardDeviceInputSchema,
  scoreboardDeviceListQuerySchema,
} from "./schemas.js";

export async function scoreboardDeviceRoutes(app: FastifyInstance): Promise<void> {
  app.get("/scoreboard-devices", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.SCOREBOARD_READ,
    });

    const parsed = scoreboardDeviceListQuerySchema.safeParse(request.query);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid scoreboard device filters",
        details: parsed.error.flatten(),
      });
    }

    return {
      devices: await listScoreboardDevices(
        identity.role === ROLES.SYSTEM_ADMIN ? parsed.data.organizationId : identity.organizationId,
      ),
    };
  });

  app.post("/scoreboard-devices", async (request, reply) => {
    const parsed = scoreboardDeviceInputSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid scoreboard device data",
        details: parsed.error.flatten(),
      });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.SCOREBOARD_MANAGE,
      organizationId: parsed.data.organizationId,
    });

    const relationshipError = await validateScoreboardDeviceRelationships(parsed.data);
    if (relationshipError) {
      return reply.code(400).send({
        error:
          relationshipError === "organization"
            ? "Organization not found"
            : "Game does not belong to the selected organization",
      });
    }

    const device = await createScoreboardDevice(parsed.data);

    await audit(identity.sub, "scoreboard_device.created", {
      scoreboardDeviceId: device.id,
      organizationId: device.organizationId,
      gameId: device.gameId,
    });

    realtime().emit("scoreboard-device:created", {
      id: device.id,
      organizationId: device.organizationId,
    });

    return reply.code(201).send({ device });
  });

  app.put("/scoreboard-devices/:id", async (request, reply) => {
    const id = scoreboardDeviceIdSchema.safeParse((request.params as { id: string }).id);
    const parsed = scoreboardDeviceInputSchema.safeParse(request.body);

    if (!id.success || !parsed.success) {
      return reply.code(400).send({
        error: "Invalid scoreboard device data",
        details: parsed.success ? undefined : parsed.error.flatten(),
      });
    }

    const existing = await findScoreboardDeviceById(id.data);
    if (!existing) return reply.code(404).send({ error: "Scoreboard device not found" });

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.SCOREBOARD_MANAGE,
      organizationId: existing.organizationId,
    });

    if (
      identity.role !== ROLES.SYSTEM_ADMIN &&
      parsed.data.organizationId !== existing.organizationId
    ) {
      return reply.code(403).send({
        error: "You do not have permission to move this device to another organization",
      });
    }

    await requirePermission(request, {
      permission: PERMISSIONS.SCOREBOARD_MANAGE,
      organizationId: parsed.data.organizationId,
    });

    const relationshipError = await validateScoreboardDeviceRelationships(parsed.data);
    if (relationshipError) {
      return reply.code(400).send({
        error:
          relationshipError === "organization"
            ? "Organization not found"
            : "Game does not belong to the selected organization",
      });
    }

    const device = await updateScoreboardDevice(id.data, parsed.data);
    if (!device) return reply.code(404).send({ error: "Scoreboard device not found" });

    await audit(identity.sub, "scoreboard_device.updated", {
      scoreboardDeviceId: device.id,
      organizationId: device.organizationId,
      gameId: device.gameId,
    });

    realtime().emit("scoreboard-device:updated", {
      id: device.id,
      organizationId: device.organizationId,
    });

    return { device };
  });

  app.post("/scoreboard-devices/:id/rotate-key", async (request, reply) => {
    const id = scoreboardDeviceIdSchema.safeParse((request.params as { id: string }).id);
    if (!id.success) return reply.code(400).send({ error: "Invalid scoreboard device id" });

    const existing = await findScoreboardDeviceById(id.data);
    if (!existing) return reply.code(404).send({ error: "Scoreboard device not found" });

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.SCOREBOARD_MANAGE,
      organizationId: existing.organizationId,
    });

    const device = await rotateScoreboardDeviceKey(id.data);
    if (!device) return reply.code(404).send({ error: "Scoreboard device not found" });

    await audit(identity.sub, "scoreboard_device.key_rotated", {
      scoreboardDeviceId: device.id,
      organizationId: device.organizationId,
    });

    realtime().emit("scoreboard-device:updated", {
      id: device.id,
      organizationId: device.organizationId,
    });

    return { device };
  });

  app.post("/public/scoreboard-devices/:id/heartbeat", async (request, reply) => {
    const id = scoreboardDeviceIdSchema.safeParse((request.params as { id: string }).id);
    const parsed = scoreboardDeviceHeartbeatSchema.safeParse(request.body);

    if (!id.success || !parsed.success) {
      return reply.code(400).send({ error: "Invalid scoreboard heartbeat" });
    }

    const device = await recordScoreboardHeartbeat(id.data, parsed.data.deviceKey);
    if (!device) return reply.code(401).send({ error: "Invalid scoreboard credentials" });

    realtime().emit("scoreboard-device:status", {
      id: device.id,
      organizationId: device.organizationId,
      status: device.status,
      lastSeenAt: device.lastSeenAt,
    });

    return {
      success: true,
      gameId: device.gameId,
      status: device.status,
      lastSeenAt: device.lastSeenAt,
    };
  });

  app.delete("/scoreboard-devices/:id", async (request, reply) => {
    const id = scoreboardDeviceIdSchema.safeParse((request.params as { id: string }).id);
    if (!id.success) return reply.code(400).send({ error: "Invalid scoreboard device id" });

    const existing = await findScoreboardDeviceById(id.data);
    if (!existing) return reply.code(404).send({ error: "Scoreboard device not found" });

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.SCOREBOARD_MANAGE,
      organizationId: existing.organizationId,
    });

    if (!(await deleteScoreboardDevice(id.data))) {
      return reply.code(404).send({ error: "Scoreboard device not found" });
    }

    await audit(identity.sub, "scoreboard_device.deleted", {
      scoreboardDeviceId: id.data,
      organizationId: existing.organizationId,
    });

    realtime().emit("scoreboard-device:deleted", {
      id: id.data,
      organizationId: existing.organizationId,
    });

    return { success: true };
  });
}
