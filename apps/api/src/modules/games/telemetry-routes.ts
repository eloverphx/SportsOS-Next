import type { FastifyInstance } from "fastify";
import { PERMISSIONS, ROLES, requirePermission } from "../auth/index.js";
import { getGameEngineTelemetry } from "./telemetry.js";

export async function gameEngineTelemetryRoutes(app: FastifyInstance): Promise<void> {
  app.get("/system/game-engine", async (request) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_READ,
    });

    return getGameEngineTelemetry(
      identity.role === ROLES.SYSTEM_ADMIN ? undefined : identity.organizationId,
    );
  });
}
