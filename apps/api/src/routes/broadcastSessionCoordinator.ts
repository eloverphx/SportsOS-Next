import type {
  FastifyInstance,
} from "fastify";
import {
  listBroadcastCoordinatorAudit,
} from "../services/broadcastCoordinatorAudit.js";

import {
  configureBroadcastCoordinatorRetry,
  evaluateBroadcastCoordinatorHealth,
  executeBroadcastCoordinatorRetry,
  getBroadcastCoordinatorRetry,
  getBroadcastCoordinatorSnapshot,
  listActiveBroadcastGameIds,
  runBroadcastCoordinatorSupervisorTick,
  scheduleBroadcastCoordinatorRetry,
  prepareBroadcastSession,
  reconcileBroadcastCoordinator,
  setBroadcastCoordinatorIntent,
  startCoordinatedBroadcast,
  stopCoordinatedBroadcast,
} from "../services/broadcastSessionCoordinator.js";

export async function registerBroadcastSessionCoordinatorRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.post(
    "/broadcast-coordinator/:gameId/supervisor/tick",
    async (request, reply) => {
      const gameId = (request.params as { gameId?: string }).gameId?.trim();
      if (!gameId) {
        return reply.code(400).send({ success: false, error: "Game ID is required." });
      }
      const result = await runBroadcastCoordinatorSupervisorTick(gameId);
      if (result.action === "REFUSED") {
        return reply.code(409).send({ success: false, error: result.message, data: result });
      }
      return { success: true, data: result };
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId/retry",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data: {
          retry:
            getBroadcastCoordinatorRetry(
              gameId,
            ),
        },
      };
    },
  );

  app.put(
    "/broadcast-coordinator/:gameId/retry",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          maxAttempts?: number;
          backoffSeconds?: number;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data: {
          retry:
            configureBroadcastCoordinatorRetry({
              gameId,
              maxAttempts:
                body.maxAttempts,
              backoffSeconds:
                body.backoffSeconds,
            }),
        },
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/retry/schedule",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          error?: string;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data: {
          retry:
            scheduleBroadcastCoordinatorRetry(
              gameId,
              body.error?.trim() ||
                "Coordinator retry requested.",
            ),
        },
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/retry/execute",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      try {
        return {
          success: true,
          data:
            await executeBroadcastCoordinatorRetry(
              gameId,
            ),
        };
      } catch (error) {
        return reply.code(409).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Coordinator retry failed.",
          data: {
            retry:
              getBroadcastCoordinatorRetry(
                gameId,
              ),
          },
        });
      }
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/reconcile",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const result =
        await reconcileBroadcastCoordinator(
          gameId,
        );

      if (
        result.action ===
        "REFUSE_AMBIGUOUS"
      ) {
        return reply.code(409).send({
          success: false,
          error:
            result.message,
          data:
            result,
        });
      }

      return {
        success: true,
        data:
          result,
      };
    },
  );

  app.get(
    "/broadcast-coordinator/active",
    async () => {
      const gameIds =
        listActiveBroadcastGameIds();

      return {
        success: true,
        data: {
          gameIds,
          count:
            gameIds.length,
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId/audit",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const query =
        request.query as {
          limit?: string;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const parsed =
        Number.parseInt(
          query.limit ??
          "100",
          10,
        );

      return {
        success: true,
        data: {
          events:
            listBroadcastCoordinatorAudit(
              gameId,
              Number.isFinite(parsed)
                ? parsed
                : 100,
            ),
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId/health",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data: {
          health:
            evaluateBroadcastCoordinatorHealth(
              gameId,
            ),
          snapshot:
            getBroadcastCoordinatorSnapshot(
              gameId,
            ),
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data:
          getBroadcastCoordinatorSnapshot(
            gameId,
          ),
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/prepare",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const snapshot =
        prepareBroadcastSession(
          gameId,
        );

      if (
        !snapshot.preflight.ready
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Broadcast preparation is blocked by final go-live preflight.",
          data:
            snapshot,
        });
      }

      return {
        success: true,
        data:
          snapshot,
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/start",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      try {
        return {
          success: true,
          data:
            await startCoordinatedBroadcast(
              gameId,
            ),
        };
      } catch (error) {
        return reply.code(409).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Unable to start coordinated broadcast.",
          data:
            getBroadcastCoordinatorSnapshot(
              gameId,
            ),
        });
      }
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/stop",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data:
          await stopCoordinatedBroadcast(
            gameId,
          ),
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/reset",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      setBroadcastCoordinatorIntent({
        gameId,
        intent:
          "IDLE",
      });

      return {
        success: true,
        data:
          getBroadcastCoordinatorSnapshot(
            gameId,
          ),
      };
    },
  );
}
