import type {
  FastifyInstance,
} from "fastify";
import { encoderRuntimeSnapshot, startEncoderRuntime, stopEncoderRuntime } from "../services/encoderRuntime.js";
import { listEncoderAuditEvents, recordEncoderAuditEvent } from "../services/encoderRuntimeAudit.js";
import { evaluateStreamingReadiness } from "../services/streamingReadinessPreflight.js";

import {
  beginEncoderStart,
  beginEncoderStop,
  getEncoderSession,
} from "../services/encoderSession.js";

import {
  getStreamDestinationProfile,
} from "../services/streamDestinationProfile.js";

export async function registerEncoderSessionRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.get(
    "/encoder-sessions/:gameId",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const gameId =
        params.gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const snapshot =
        encoderRuntimeSnapshot(
          gameId,
        );

      return {
        success: true,
        data: {
          session:
            snapshot.session,
          runtimeActive:
            snapshot.runtimeActive,
        },
      };
    },
  );

  app.get(
    "/encoder-sessions/:gameId/preflight",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const gameId =
        params.gameId?.trim();

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
          preflight:
            evaluateStreamingReadiness(
              gameId,
            ),
        },
      };
    },
  );

  app.get(
    "/encoder-sessions/:gameId/audit",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const query =
        request.query as {
          limit?: string;
        };

      const gameId =
        params.gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const limit =
        Number.parseInt(
          query.limit ??
            "50",
          10,
        );

      return {
        success: true,
        data: {
          events:
            listEncoderAuditEvents(
              gameId,
              Number.isFinite(limit)
                ? limit
                : 50,
            ),
        },
      };
    },
  );

  app.get(
    "/encoder-sessions/:gameId/telemetry",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const gameId =
        params.gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const snapshot =
        encoderRuntimeSnapshot(
          gameId,
        );

      return {
        success: true,
        data: {
          runtimeActive:
            snapshot.runtimeActive,
          session:
            snapshot.session,
          telemetry:
            snapshot.telemetry,
          recovery:
            snapshot.recovery,
        },
      };
    },
  );

  app.post(
    "/encoder-sessions/:gameId/start",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const gameId =
        params.gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const destination =
        getStreamDestinationProfile(
          gameId,
        );

      if (
        !destination ||
        !destination.enabled
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Enabled stream destination is required before encoder start.",
        });
      }

      if (
        destination.status !==
          "READY" &&
        destination.status !==
          "LIVE"
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Stream destination must be READY before encoder start.",
        });
      }

      // STREAMING_READINESS_PREFLIGHT_20_9
      const preflight =
        evaluateStreamingReadiness(
          gameId,
        );

      if (!preflight.ready) {
        return reply.code(409).send({
          success: false,
          error:
            "Streaming readiness preflight failed.",
          data: {
            preflight,
          },
        });
      }

      recordEncoderAuditEvent({
        gameId,
        type:
          "START_REQUESTED",
      });

      beginEncoderStart(
        gameId,
      );

      try {
        await startEncoderRuntime({
          gameId,
          destination,
        });
      } catch (error) {
        const message =
          error instanceof Error
            ? error.message
            : "Unable to launch encoder runtime.";

        return reply.code(500).send({
          success: false,
          error:
            message,
        });
      }

      const snapshot =
        encoderRuntimeSnapshot(
          gameId,
        );

      return {
        success: true,
        data: {
          session:
            snapshot.session,
          runtimeActive:
            snapshot.runtimeActive,
        },
      };
    },
  );

  app.post(
    "/encoder-sessions/:gameId/stop",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const gameId =
        params.gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      recordEncoderAuditEvent({
        gameId,
        type:
          "STOP_REQUESTED",
      });

      beginEncoderStop(
        gameId,
      );

      await stopEncoderRuntime(
        gameId,
      );

      const snapshot =
        encoderRuntimeSnapshot(
          gameId,
        );

      return {
        success: true,
        data: {
          session:
            snapshot.session,
          runtimeActive:
            snapshot.runtimeActive,
        },
      };
    },
  );
}
