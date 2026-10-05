import type { FastifyInstance } from "fastify";
import { findGameById } from "../modules/games/repository.js";
import { PERMISSIONS, requirePermission } from "../modules/auth/index.js";
import { issueCameraIngestSession } from "../services/cameraIngestSession.js";

export async function registerCameraIngestSessionRoutes(app: FastifyInstance): Promise<void> {
  app.post("/streaming/camera-ingest/:gameId/session", async (request, reply) => {
    const params = request.params as {
      gameId?: string;
    };

    const gameId = params.gameId?.trim();

    if (!gameId) {
      return reply.code(400).send({
        success: false,
        requestId: request.id,
        error: {
          code: "CAMERA_INGEST_GAME_REQUIRED",
          message: "Game ID is required",
        },
      });
    }

    const numericGameId = Number.parseInt(gameId, 10);

    if (!Number.isSafeInteger(numericGameId) || numericGameId <= 0) {
      return reply.code(400).send({
        success: false,
        requestId: request.id,
        error: {
          code: "CAMERA_INGEST_GAME_INVALID",
          message: "Game ID is invalid",
        },
      });
    }

    const game = await findGameById(numericGameId);

    if (!game) {
      return reply.code(404).send({
        success: false,
        requestId: request.id,
        error: {
          code: "CAMERA_INGEST_GAME_NOT_FOUND",
          message: "Game was not found",
        },
      });
    }

    await requirePermission(request, {
      permission: PERMISSIONS.STREAM_MANAGE,
      organizationId: game.organizationId,
    });

    try {
      const session = issueCameraIngestSession({
        gameId,
      });

      return reply.code(201).send({
        success: true,
        requestId: request.id,
        data: {
          session,
        },
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Camera ingest is not configured";

      return reply.code(503).send({
        success: false,
        requestId: request.id,
        error: {
          code: "CAMERA_INGEST_UNAVAILABLE",
          message,
        },
      });
    }
  });
}
