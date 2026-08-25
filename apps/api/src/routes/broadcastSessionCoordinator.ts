import type {
  FastifyInstance,
} from "fastify";
import {
  listBroadcastCoordinatorAudit,
} from "../services/broadcastCoordinatorAudit.js";
import {
  listGoLiveAuditEvents,
} from "../services/goLiveAudit.js";
import {
  addBroadcastOperatorNote,
  listBroadcastOperatorNotes,
} from "../services/broadcastOperatorNotes.js";

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
    "/broadcast-coordinator/attention-queue",
    async () => {
      const gameIds =
        listActiveBroadcastGameIds();

      const items =
        gameIds
          .map(
            (gameId) => {
              const snapshot =
                getBroadcastCoordinatorSnapshot(
                  gameId,
                );

              const health =
                evaluateBroadcastCoordinatorHealth(
                  gameId,
                );

              const retry =
                getBroadcastCoordinatorRetry(
                  gameId,
                );

              let severity:
                | "CRITICAL"
                | "HIGH"
                | "MEDIUM"
                | "LOW" =
                "LOW";

              let reason =
                "Active broadcast requires no immediate attention.";

              if (
                snapshot.goLive.status ===
                  "EMERGENCY_STOPPED"
              ) {
                severity =
                  "CRITICAL";

                reason =
                  "Emergency stop is active.";
              } else if (
                !health.healthy
              ) {
                severity =
                  "HIGH";

                reason =
                  health.issues
                    .map(
                      (issue) =>
                        issue.message,
                    )
                    .join(" | ");
              } else if (
                snapshot.goLive.status ===
                  "DEGRADED"
              ) {
                severity =
                  "HIGH";

                reason =
                  snapshot.goLive.degradationReason ??
                  "Broadcast is degraded.";
              } else if (
                retry.state ===
                  "EXHAUSTED"
              ) {
                severity =
                  "HIGH";

                reason =
                  retry.lastError ??
                  "Coordinator retries are exhausted.";
              } else if (
                retry.state ===
                  "SCHEDULED"
              ) {
                severity =
                  "MEDIUM";

                reason =
                  retry.nextRetryAt
                    ? `Coordinator retry scheduled for ${retry.nextRetryAt}.`
                    : "Coordinator retry is scheduled.";
              } else if (
                snapshot.goLive.status ===
                  "STARTING" ||
                snapshot.goLive.status ===
                  "STOPPING"
              ) {
                severity =
                  "MEDIUM";

                reason =
                  `Go-live transition is ${snapshot.goLive.status}.`;
              }

              const score =
                severity === "CRITICAL"
                  ? 400
                  : severity === "HIGH"
                    ? 300
                    : severity === "MEDIUM"
                      ? 200
                      : 100;

              return {
                gameId,
                severity,
                score,
                reason,
                health,
                retry,
                snapshot,
              };
            },
          )
          .sort(
            (a, b) =>
              b.score -
              a.score,
          );

      return {
        success: true,
        data: {
          count:
            items.length,
          items,
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/operations-summary",
    async () => {
      const gameIds =
        listActiveBroadcastGameIds();

      const items =
        gameIds.map(
          (gameId) => ({
            gameId,
            snapshot:
              getBroadcastCoordinatorSnapshot(
                gameId,
              ),
            health:
              evaluateBroadcastCoordinatorHealth(
                gameId,
              ),
            retry:
              getBroadcastCoordinatorRetry(
                gameId,
              ),
          }),
        );

      return {
        success: true,
        data: {
          count:
            items.length,
          items,
        },
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
    "/broadcast-coordinator/:gameId/handoff-summary",
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
        getBroadcastCoordinatorSnapshot(
          gameId,
        );

      const health =
        evaluateBroadcastCoordinatorHealth(
          gameId,
        );

      const retry =
        getBroadcastCoordinatorRetry(
          gameId,
        );

      const notes =
        listBroadcastOperatorNotes(
          gameId,
          5,
        );

      const coordinatorEvents =
        listBroadcastCoordinatorAudit(
          gameId,
          10,
        ).map(
          (event) => ({
            source:
              "COORDINATOR",
            type:
              event.type,
            timestamp:
              event.timestamp,
            detail:
              event.detail,
          }),
        );

      const goLiveEvents =
        listGoLiveAuditEvents(
          gameId,
          10,
        ).map(
          (event) => ({
            source:
              "GO_LIVE",
            type:
              event.type,
            timestamp:
              event.timestamp,
            detail:
              event.detail,
          }),
        );

      const recentEvents =
        [
          ...coordinatorEvents,
          ...goLiveEvents,
        ]
          .sort(
            (a, b) =>
              Date.parse(
                b.timestamp,
              ) -
              Date.parse(
                a.timestamp,
              ),
          )
          .slice(
            0,
            10,
          );

      return {
        success: true,
        data: {
          gameId,
          generatedAt:
            new Date().toISOString(),
          snapshot,
          health,
          retry,
          notes,
          recentEvents,
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId/operator-notes",
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
          notes:
            listBroadcastOperatorNotes(
              gameId,
              100,
            ),
        },
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/operator-notes",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          operator?: string;
          note?: string;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      try {
        const note =
          addBroadcastOperatorNote({
            gameId,
            operator:
              body.operator ??
              "",
            note:
              body.note ??
              "",
          });

        return {
          success: true,
          data: {
            note,
          },
        };
      } catch (error) {
        return reply.code(400).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Unable to save operator note.",
        });
      }
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId/operator-timeline",
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

      const parsedLimit =
        Number.parseInt(
          query.limit ??
          "100",
          10,
        );

      const limit =
        Number.isFinite(
          parsedLimit,
        )
          ? Math.max(
              1,
              Math.min(
                parsedLimit,
                200,
              ),
            )
          : 100;

      const coordinatorEvents =
        listBroadcastCoordinatorAudit(
          gameId,
          limit,
        ).map(
          (event) => ({
            id:
              event.id,
            source:
              "COORDINATOR",
            type:
              event.type,
            timestamp:
              event.timestamp,
            detail:
              event.detail,
            operator:
              null,
            correlationId:
              event.correlationId,
          }),
        );

      const goLiveEvents =
        listGoLiveAuditEvents(
          gameId,
          limit,
        ).map(
          (event) => ({
            id:
              event.id,
            source:
              "GO_LIVE",
            type:
              event.type,
            timestamp:
              event.timestamp,
            detail:
              event.detail,
            operator:
              event.operator,
            correlationId:
              null,
          }),
        );

      const events =
        [
          ...coordinatorEvents,
          ...goLiveEvents,
        ]
          .sort(
            (a, b) =>
              Date.parse(
                b.timestamp,
              ) -
              Date.parse(
                a.timestamp,
              ),
          )
          .slice(
            0,
            limit,
          );

      return {
        success: true,
        data: {
          gameId,
          count:
            events.length,
          events,
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
