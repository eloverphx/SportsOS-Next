import type {
  FastifyInstance,
} from "fastify";

import {
  getEnrollment,
  issueClaimToken,
  isVerifiedDevice,
  listEnrollments,
  registerFirstBoot,
  rejectEnrollment,
  retireEnrollment,
  reactivateEnrollment,
  verifyEnrollmentWithClaim,
} from "../services/scoreboardDeviceEnrollment.js";

type FirstBootBody = {
  deviceId?: string;
  firmwareVersion?: string;
  chipId?: string;
};

type ClaimBody = {
  claimToken?: string;
};

export async function registerScoreboardDeviceEnrollmentRoutes(
  app: FastifyInstance,
) {
  app.get(
    "/scoreboard-devices/enrollment",
    async () => ({
      success: true,
      data: {
        devices:
          listEnrollments(),
      },
    }),
  );

  app.get(
    "/scoreboard-devices/enrollment/:deviceId",
    async (request, reply) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      const record =
        getEnrollment(deviceId);

      if (!record) {
        return reply.code(404).send({
          success: false,
          error:
            "Enrollment record not found.",
        });
      }

      return {
        success: true,
        data: record,
      };
    },
  );

  app.post(
    "/scoreboard-devices/enrollment/first-boot",
    async (request, reply) => {
      const body =
        request.body as FirstBootBody;

      if (
        !body?.deviceId ||
        !body?.firmwareVersion ||
        !body?.chipId
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "deviceId, firmwareVersion and chipId are required.",
        });
      }

      const record =
        registerFirstBoot({
          deviceId:
            body.deviceId,
          firmwareVersion:
            body.firmwareVersion,
          chipId:
            body.chipId,
        });

      return reply.code(201).send({
        success: true,
        data: record,
      });
    },
  );

  app.post(
    "/scoreboard-devices/enrollment/:deviceId/claim-token",
    async (request, reply) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      const token =
        issueClaimToken(
          deviceId,
        );

      if (!token) {
        return reply.code(404).send({
          success: false,
          error:
            "Enrollment record not found.",
        });
      }

      return {
        success: true,
        data: {
          deviceId,
          claimToken:
            token,
        },
      };
    },
  );

  app.post(
    "/scoreboard-devices/enrollment/:deviceId/verify",
    async (request, reply) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      const body =
        request.body as ClaimBody;

      if (!body?.claimToken) {
        return reply.code(400).send({
          success: false,
          error:
            "claimToken is required.",
        });
      }

      const record =
        verifyEnrollmentWithClaim(
          deviceId,
          body.claimToken,
        );

      if (!record) {
        return reply.code(403).send({
          success: false,
          error:
            "Invalid or consumed claim token.",
        });
      }

      return {
        success: true,
        data: record,
      };
    },
  );

  app.post(
    "/scoreboard-devices/enrollment/:deviceId/reject",
    async (request, reply) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      const record =
        rejectEnrollment(deviceId);

      if (!record) {
        return reply.code(404).send({
          success: false,
          error:
            "Enrollment record not found.",
        });
      }

      return {
        success: true,
        data: record,
      };
    },
  );

  app.get(
    "/scoreboard-devices/enrollment/:deviceId/verified",
    async (request) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      return {
        success: true,
        data: {
          verified:
            isVerifiedDevice(
              deviceId,
            ),
        },
      };
    },
  );

  app.post(
    "/scoreboard-devices/enrollment/:deviceId/retire",
    async (request, reply) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      const record =
        retireEnrollment(
          deviceId,
        );

      if (!record) {
        return reply.code(404).send({
          success: false,
          error:
            "Enrollment record not found.",
        });
      }

      return {
        success: true,
        data: record,
      };
    },
  );

  app.post(
    "/scoreboard-devices/enrollment/:deviceId/reactivate",
    async (request, reply) => {
      const { deviceId } =
        request.params as {
          deviceId: string;
        };

      const record =
        reactivateEnrollment(
          deviceId,
        );

      if (!record) {
        return reply.code(409).send({
          success: false,
          error:
            "Only retired devices can be reactivated.",
        });
      }

      return {
        success: true,
        data: record,
      };
    },
  );

}
