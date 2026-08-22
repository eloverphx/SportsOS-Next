import type {
  FastifyInstance,
} from "fastify";

import {
  createFirmwareRollout,
  getFirmwareRollout,
  listFirmwareRollouts,
  updateFirmwareRolloutState,
  type FirmwareRolloutState,
} from "../services/scoreboardFirmwareRollouts.js";

import {
  getFirmwareRelease,
} from "../services/scoreboardFirmwareReleaseRegistry.js";

import {
  isVerifiedDevice,
} from "../services/scoreboardDeviceEnrollment.js";

const allowedTransitions: Record<
  FirmwareRolloutState,
  FirmwareRolloutState[]
> = {
  DRAFT: [
    "ACTIVE",
    "CANCELLED",
  ],
  ACTIVE: [
    "PAUSED",
    "COMPLETED",
    "CANCELLED",
  ],
  PAUSED: [
    "ACTIVE",
    "CANCELLED",
  ],
  COMPLETED: [],
  CANCELLED: [],
};

export async function registerScoreboardFirmwareRolloutRoutes(
  app: FastifyInstance,
) {
  app.get(
    "/scoreboard-firmware/rollouts",
    async () => ({
      success: true,
      data: {
        rollouts:
          listFirmwareRollouts(),
      },
    }),
  );

  app.get(
    "/scoreboard-firmware/rollouts/:rolloutId",
    async (request, reply) => {
      const { rolloutId } =
        request.params as {
          rolloutId: string;
        };

      const rollout =
        getFirmwareRollout(
          rolloutId,
        );

      if (!rollout) {
        return reply.code(404).send({
          success: false,
          error:
            "Firmware rollout not found.",
        });
      }

      return {
        success: true,
        data:
          rollout,
      };
    },
  );

  app.post(
    "/scoreboard-firmware/rollouts",
    async (request, reply) => {
      const body =
        request.body as {
          releaseId?: string;
          targetDeviceIds?: string[];
        };

      if (
        !body?.releaseId ||
        !Array.isArray(
          body.targetDeviceIds,
        ) ||
        body.targetDeviceIds.length === 0
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "releaseId and targetDeviceIds are required.",
        });
      }

      const release =
        getFirmwareRelease(
          body.releaseId,
        );

      if (!release) {
        return reply.code(404).send({
          success: false,
          error:
            "Firmware release not found.",
        });
      }

      const unverified =
        body.targetDeviceIds.filter(
          (deviceId) =>
            !isVerifiedDevice(
              deviceId,
            ),
        );

      if (
        unverified.length > 0
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "All rollout targets must be verified scoreboard devices.",
          data: {
            unverified,
          },
        });
      }

      const rollout =
        createFirmwareRollout({
          releaseId:
            body.releaseId,
          targetDeviceIds:
            body.targetDeviceIds,
        });

      return reply.code(201).send({
        success: true,
        data:
          rollout,
      });
    },
  );

  app.post(
    "/scoreboard-firmware/rollouts/:rolloutId/state",
    async (request, reply) => {
      const { rolloutId } =
        request.params as {
          rolloutId: string;
        };

      const body =
        request.body as {
          state?: FirmwareRolloutState;
        };

      const rollout =
        getFirmwareRollout(
          rolloutId,
        );

      if (!rollout) {
        return reply.code(404).send({
          success: false,
          error:
            "Firmware rollout not found.",
        });
      }

      if (
        !body?.state ||
        !allowedTransitions[
          rollout.state
        ].includes(
          body.state,
        )
      ) {
        return reply.code(409).send({
          success: false,
          error:
            `Invalid rollout transition from ${rollout.state}.`,
        });
      }

      return {
        success: true,
        data:
          updateFirmwareRolloutState(
            rolloutId,
            body.state,
          ),
      };
    },
  );
}
