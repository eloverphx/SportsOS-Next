import type { FastifyInstance } from "fastify";
import {
  validateScoreboardDeviceCommand,
  type ScoreboardDeviceCommand,
} from "@sportsos/core";
import {
  ScoreboardDeviceGateway,
} from "../services/scoreboardDeviceGateway.js";
import {
  GameScoreboardSyncService,
  type AuthoritativeGameSnapshot,
} from "../services/gameScoreboardSync.js";
import {
  AutomaticGameScoreboardSync,
} from "../services/automaticGameScoreboardSync.js";
import {
  bindAutomaticGameScoreboardSync,
  bindScoreboardDeviceRecovery,
} from "../services/gameScoreboardEventBinding.js";
import {
  ScoreboardDeviceRecoveryService,
} from "../services/scoreboardDeviceRecovery.js";
import { authorizeVerifiedScoreboardDevice } from "../services/scoreboardDeviceAuthorization.js";
import { registerScoreboardControlInputRoutes } from "./scoreboardControlInputs.js";

const gateway = new ScoreboardDeviceGateway();
const syncService =
  new GameScoreboardSyncService(gateway);
const automaticSync =
  new AutomaticGameScoreboardSync(syncService);
const recoveryService =
  new ScoreboardDeviceRecoveryService(
    automaticSync,
  );

bindScoreboardDeviceRecovery(
  recoveryService,
);

gateway.onPresence(
  async (deviceId, online) => {
    if (!online) {
      return;
    }

    await recoveryService
      .reconcileDevice(
        deviceId,
      );
  },
);
bindAutomaticGameScoreboardSync(automaticSync);

export async function scoreboardDevicesRoutes(
  app: FastifyInstance,
): Promise<void> {


  app.post<{
    Params: { deviceId: string };
    Body: ScoreboardDeviceCommand;
  }>(
    "/scoreboard-devices/:deviceId/commands",
    async (request, reply) => {
      let command: ScoreboardDeviceCommand;

      try {
        command = validateScoreboardDeviceCommand(request.body);
      } catch (error) {
        return reply.code(400).send({
          success: false,
          error: {
            code: "INVALID_SCOREBOARD_COMMAND",
            message:
              error instanceof Error
                ? error.message
                : "Invalid scoreboard command.",
          },
        });
      }

      await gateway.sendCommand(request.params.deviceId, command);

      return reply.code(202).send({
        success: true,
        data: {
          accepted: true,
          deviceId: request.params.deviceId,
          commandId: command.commandId,
        },
      });
    },
  );

  app.post<{
    Params: {
      deviceId: string;
    };
    Body: AuthoritativeGameSnapshot;
  }>(
    "/scoreboard-devices/:deviceId/sync-game",
    async (request, reply) => {
      try {
        const commandId =
          await syncService.sync(
            request.body,
            request.params.deviceId,
          );

        return reply
          .code(202)
          .send({
            success: true,
            data: {
              accepted: true,
              deviceId:
                request.params.deviceId,
              gameId:
                request.body.gameId,
              commandId,
            },
          });
      } catch (error) {
        return reply
          .code(400)
          .send({
            success: false,
            error: {
              code:
                "INVALID_SCOREBOARD_SYNC",
              message:
                error instanceof Error
                  ? error.message
                  : "Invalid scoreboard synchronization request.",
            },
          });
      }
    },
  );

  app.get(
    "/scoreboard-devices/assignments",
    async () => ({
      success: true,
      data: {
        assignments:
          automaticSync.listAssignments(),
      },
    }),
  );

  app.put<{
    Params: {
      gameId: string;
    };
    Body: {
      deviceId: string;
    };
  }>(
    "/scoreboard-devices/assignments/:gameId",
    async (request, reply) => {
      try {
        const assignment =
          automaticSync.assign(
            request.params.gameId,
            request.body.deviceId,
          );

        return reply.send({
          success: true,
          data: {
            assignment,
          },
        });
      } catch (error) {
        return reply
          .code(400)
          .send({
            success: false,
            error: {
              code:
                "INVALID_SCOREBOARD_ASSIGNMENT",
              message:
                error instanceof Error
                  ? error.message
                  : "Invalid scoreboard assignment.",
            },
          });
      }
    },
  );

  app.delete<{
    Params: {
      gameId: string;
    };
  }>(
    "/scoreboard-devices/assignments/:gameId",
    async (request) => ({
      success: true,
      data: {
        removed:
          automaticSync.unassign(
            request.params.gameId,
          ),
      },
    }),
  );

  app.post<{
    Body: AuthoritativeGameSnapshot;
  }>(
    "/scoreboard-devices/realtime-sync",
    async (request, reply) => {
      try {
        const result =
          await automaticSync
            .handleAuthoritativeSnapshot(
              request.body,
            );

        return reply.send({
          success: true,
          data: {
            result,
          },
        });
      } catch (error) {
        return reply
          .code(400)
          .send({
            success: false,
            error: {
              code:
                "SCOREBOARD_REALTIME_SYNC_FAILED",
              message:
                error instanceof Error
                  ? error.message
                  : "Realtime scoreboard synchronization failed.",
            },
          });
      }
    },
  );

  app.post<{
    Params: {
      deviceId: string;
    };
  }>(
    "/scoreboard-devices/:deviceId/reconcile",
    async (request, reply) => {
      const result =
        await recoveryService
          .reconcileDevice(
            request.params.deviceId,
          );

      return reply.send({
        success: true,
        data: {
          result,
        },
      });
    },
  );
  await registerScoreboardControlInputRoutes(
    app,
    automaticSync,
  );

}
