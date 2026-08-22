import type {
  FastifyInstance,
} from "fastify";

import type {
  ScoreboardFirmwareUpdateReport,
} from "@sportsos/core";

import {
  getLatestFirmwareDeploymentStatus,
  listFirmwareDeploymentReports,
  recordFirmwareDeploymentStatus,
} from "../services/scoreboardFirmwareDeploymentStatus.js";

import {
  isVerifiedDevice,
} from "../services/scoreboardDeviceEnrollment.js";

export async function registerScoreboardFirmwareDeploymentStatusRoutes(
  app: FastifyInstance,
) {
  app.post(
    "/scoreboard-firmware/deployments/report",
    async (request, reply) => {
      const body =
        request.body as ScoreboardFirmwareUpdateReport;

      if (
        !body?.deviceId ||
        !body?.releaseId ||
        !body?.targetVersion ||
        !body?.status ||
        !body?.reportedAt
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Invalid firmware deployment report.",
        });
      }

      if (
        !isVerifiedDevice(
          body.deviceId,
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Verified scoreboard device required.",
        });
      }

      return {
        success: true,
        data:
          recordFirmwareDeploymentStatus(
            body,
          ),
      };
    },
  );

  app.get(
    "/scoreboard-firmware/deployments",
    async (request) => {
      const query =
        request.query as {
          deviceId?: string;
          releaseId?: string;
        };

      return {
        success: true,
        data: {
          reports:
            listFirmwareDeploymentReports(
              query,
            ),
        },
      };
    },
  );

  app.get(
    "/scoreboard-firmware/deployments/:deviceId/latest",
    async (request) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      return {
        success: true,
        data:
          getLatestFirmwareDeploymentStatus(
            deviceId,
          ),
      };
    },
  );
}
