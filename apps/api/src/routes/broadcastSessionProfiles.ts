import type {
  FastifyInstance,
} from "fastify";
import { realtime } from "../infrastructure/realtime.js";

import {
  deleteBroadcastSessionProfile,
  getBroadcastSessionProfile,
  upsertBroadcastSessionProfile,
} from "../services/broadcastSessionProfile.js";

export async function registerBroadcastSessionProfileRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.get(
    "/broadcast-sessions/:gameId",
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
            getBroadcastSessionProfile(
              gameId,
            ),
        },
      };
    },
  );

  app.put(
    "/broadcast-sessions/:gameId",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const body =
        request.body as {
          enabled?: boolean;
          title?: string | null;
          sponsorUrl?: string | null;
          showPowerPlay?: boolean;
          showTeamLogos?: boolean;
          scenePreset?:
            | "STANDARD"
            | "MINIMAL"
            | "SPONSOR_FOCUS";
          sponsorUrls?: string[];
          sponsorRotationSeconds?: number;
          soundEnabled?: boolean;
          goalSoundUrl?: string | null;
          penaltySoundUrl?: string | null;
          hornSoundUrl?: string | null;
          intermissionSoundUrl?: string | null;
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
        upsertBroadcastSessionProfile({
          gameId,
          enabled:
            body.enabled,
          title:
            body.title,
          sponsorUrl:
            body.sponsorUrl,
          showPowerPlay:
            body.showPowerPlay,
          showTeamLogos:
            body.showTeamLogos,
          scenePreset:
            body.scenePreset,
          sponsorUrls:
            body.sponsorUrls,
          sponsorRotationSeconds:
            body.sponsorRotationSeconds,
          soundEnabled:
            body.soundEnabled,
          goalSoundUrl:
            body.goalSoundUrl,
          penaltySoundUrl:
            body.penaltySoundUrl,
          hornSoundUrl:
            body.hornSoundUrl,
          intermissionSoundUrl:
            body.intermissionSoundUrl,
        });

      realtime().to(
        `game:${gameId}`,
      ).emit(
        "broadcast-session:updated",
        {
          gameId,
          profile,
        },
      );

      return {
        success: true,
        data: {
          profile,
        },
      };
    },
  );

  app.delete(
    "/broadcast-sessions/:gameId",
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

      const deleted =
        deleteBroadcastSessionProfile(
          gameId,
        );

      realtime().to(
        `game:${gameId}`,
      ).emit(
        "broadcast-session:deleted",
        {
          gameId,
        },
      );

      return {
        success: true,
        data: {
          deleted,
        },
      };
    },
  );

  app.get(
    "/public/games/:gameId/broadcast-session",
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
        getBroadcastSessionProfile(
          gameId,
        );

      return {
        success: true,
        data: {
          profile:
            profile?.enabled
              ? profile
              : null,
        },
      };
    },
  );
}
