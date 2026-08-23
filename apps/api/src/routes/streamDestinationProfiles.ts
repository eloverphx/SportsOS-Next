import type {
  FastifyInstance,
} from "fastify";
import { probeStreamDestination } from "../services/streamDestinationProbe.js";

import {
  deleteStreamDestinationProfile,
  getStreamDestinationProfile,
  publicStreamDestinationSummary,
  upsertStreamDestinationProfile,
  updateStreamDestinationProbeResult,
  type StreamLatencyMode,
  type StreamProtocol,
} from "../services/streamDestinationProfile.js";

export async function registerStreamDestinationProfileRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.get(
    "/stream-destinations/:gameId",
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
          profile:
            getStreamDestinationProfile(
              gameId,
            ),
        },
      };
    },
  );

  app.put(
    "/stream-destinations/:gameId",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const body =
        request.body as {
          enabled?: boolean;
          protocol?: StreamProtocol;
          ingestUrl?: string | null;
          streamName?: string | null;
          credentialRef?: string | null;
          latencyMode?: StreamLatencyMode;
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

      const profile =
        upsertStreamDestinationProfile({
          gameId,
          enabled:
            body.enabled,
          protocol:
            body.protocol,
          ingestUrl:
            body.ingestUrl,
          streamName:
            body.streamName,
          credentialRef:
            body.credentialRef,
          latencyMode:
            body.latencyMode,
        });

      return {
        success: true,
        data: {
          profile,
        },
      };
    },
  );

  app.post(
    "/stream-destinations/:gameId/probe",
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

      const profile =
        getStreamDestinationProfile(
          gameId,
        );

      if (
        !profile ||
        !profile.enabled ||
        !profile.ingestUrl
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Enabled stream destination with ingest URL is required before probing.",
        });
      }

      const result =
        await probeStreamDestination({
          protocol:
            profile.protocol,
          ingestUrl:
            profile.ingestUrl,
        });

      const updated =
        updateStreamDestinationProbeResult({
          gameId,
          reachable:
            result.reachable,
          checkedAt:
            result.checkedAt,
          latencyMs:
            result.latencyMs,
          error:
            result.error,
        });

      return {
        success: true,
        data: {
          probe:
            result,
          profile:
            updated,
        },
      };
    },
  );

  app.delete(
    "/stream-destinations/:gameId",
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
          deleted:
            deleteStreamDestinationProfile(
              gameId,
            ),
        },
      };
    },
  );

  app.get(
    "/public/games/:gameId/stream-status",
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
          stream:
            publicStreamDestinationSummary(
              gameId,
            ),
        },
      };
    },
  );
}
