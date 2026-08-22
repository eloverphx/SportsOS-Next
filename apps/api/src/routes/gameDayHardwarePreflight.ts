import type {
  FastifyInstance,
} from "fastify";
import { createGameStartPreflightOverride, listGameStartPreflightOverrides, revokeGameStartPreflightOverride } from "../services/gameStartPreflightOverride.js";

import {
  gameDayHardwarePreflightFreshness,
  latestGameDayHardwarePreflight,
  listGameDayHardwarePreflights,
  runGameDayHardwarePreflight,
} from "../services/gameDayHardwarePreflight.js";

type Assignment = {
  gameId: string;
  deviceId: string;
};

async function assignedDeviceForGame(
  app: FastifyInstance,
  gameId: string,
): Promise<string | null> {
  const response =
    await app.inject({
      method:
        "GET",
      url:
        "/scoreboard-devices/assignments",
    });

  if (
    response.statusCode < 200 ||
    response.statusCode >= 300
  ) {
    return null;
  }

  try {
    const body =
      response.json() as {
        data?: {
          assignments?: Assignment[];
        };
        assignments?: Assignment[];
      };

    const assignments =
      body.data?.assignments ??
      body.assignments ??
      [];

    return (
      assignments.find(
        (item) =>
          String(
            item.gameId,
          ) ===
          String(
            gameId,
          ),
      )?.deviceId ??
      null
    );
  } catch {
    return null;
  }
}

export async function registerGameDayHardwarePreflightRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.get(
    "/game-day-hardware-preflight/:gameId/overrides",
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
          overrides:
            listGameStartPreflightOverrides(
              gameId,
            ),
        },
      };
    },
  );


  app.post(
    "/game-day-hardware-preflight/:gameId/override",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const body =
        request.body as {
          deviceId?: string;
          reason?: string;
          actorUserId?: string | null;
          actorRoles?: string[];
        };

      const gameId =
        params.gameId?.trim();

      const deviceId =
        body.deviceId?.trim();

      const reason =
        body.reason?.trim();

      if (
        !gameId ||
        !deviceId ||
        !reason
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID, device ID, and emergency override reason are required.",
        });
      }

      const override =
        createGameStartPreflightOverride({
          gameId,
          deviceId,
          reason,
          actorUserId:
            body.actorUserId ??
            null,
          actorRoles:
            Array.isArray(
              body.actorRoles,
            )
              ? body.actorRoles
              : [],
        });

      return reply.code(201).send({
        success: true,
        data: {
          override,
        },
      });
    },
  );


  app.delete(
    "/game-day-hardware-preflight/:gameId/override/:overrideId",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
          overrideId?: string;
        };

      if (
        !params.gameId?.trim() ||
        !params.overrideId?.trim()
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID and override ID are required.",
        });
      }

      return {
        success: true,
        data: {
          revoked:
            revokeGameStartPreflightOverride(
              params.overrideId.trim(),
            ),
        },
      };
    },
  );


  app.post(
    "/game-day-hardware-preflight/:gameId",
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

      const deviceId =
        await assignedDeviceForGame(
          app,
          gameId,
        );

      if (!deviceId) {
        return reply.code(409).send({
          success: false,
          error:
            "No scoreboard device is assigned to this game.",
        });
      }

      const preflight =
        await runGameDayHardwarePreflight({
          gameId,
          deviceId,
        });

      return reply
        .code(
          preflight.status ===
            "PASS"
            ? 200
            : 409,
        )
        .send({
          success:
            preflight.status ===
            "PASS",
          data: {
            preflight,
          },
          error:
            preflight.status ===
              "PASS"
              ? undefined
              : "Game-day hardware preflight failed.",
        });
    },
  );

  app.get(
    "/game-day-hardware-preflight/:gameId/latest",
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

      const preflight =
        latestGameDayHardwarePreflight(
          gameId,
        );

      return {
        success: true,
        data: {
          preflight,
          assignmentFingerprint:
            preflight?.assignmentFingerprint ??
            null,
          freshness:
            gameDayHardwarePreflightFreshness(
              preflight,
            ),
        },
      };
    },
  );

  app.get(
    "/game-day-hardware-preflight/:gameId/freshness",
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

      const preflight =
        latestGameDayHardwarePreflight(
          gameId,
        );

      return {
        success: true,
        data: {
          preflight,
          freshness:
            gameDayHardwarePreflightFreshness(
              preflight,
            ),
        },
      };
    },
  );

  app.get(
    "/game-day-hardware-preflight/:gameId/history",
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
          preflights:
            listGameDayHardwarePreflights(
              gameId,
            ),
        },
      };
    },
  );
}
