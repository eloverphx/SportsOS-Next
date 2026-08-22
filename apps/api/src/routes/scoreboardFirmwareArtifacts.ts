import fs from "node:fs";

import type {
  FastifyInstance,
} from "fastify";

import {
  getFirmwareArtifactPath,
  importFirmwareReleaseDirectory,
} from "../services/scoreboardFirmwareArtifactStore.js";

import {
  getFirmwareRelease,
} from "../services/scoreboardFirmwareReleaseRegistry.js";

import {
  isVerifiedDevice,
} from "../services/scoreboardDeviceEnrollment.js";

export async function registerScoreboardFirmwareArtifactRoutes(
  app: FastifyInstance,
) {
  app.post(
    "/scoreboard-firmware/import",
    async (request, reply) => {
      const body =
        request.body as {
          releaseDirectory?: string;
        };

      if (!body?.releaseDirectory) {
        return reply.code(400).send({
          success: false,
          error:
            "releaseDirectory is required.",
        });
      }

      try {
        const imported =
          importFirmwareReleaseDirectory(
            body.releaseDirectory,
          );

        return reply.code(201).send({
          success: true,
          data: {
            release:
              imported.release,
          },
        });
      } catch (error) {
        return reply.code(400).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Firmware release import failed.",
        });
      }
    },
  );

  app.get(
    "/scoreboard-firmware/releases/:releaseId/artifact",
    async (request, reply) => {
      const { releaseId } =
        request.params as {
          releaseId: string;
        };

      const query =
        request.query as {
          deviceId?: string;
        };

      if (!query.deviceId) {
        return reply.code(400).send({
          success: false,
          error:
            "deviceId is required.",
        });
      }

      if (
        !isVerifiedDevice(
          query.deviceId,
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Verified scoreboard device required.",
        });
      }

      const release =
        getFirmwareRelease(
          releaseId,
        );

      if (!release) {
        return reply.code(404).send({
          success: false,
          error:
            "Firmware release not found.",
        });
      }

      const artifactPath =
        getFirmwareArtifactPath(
          releaseId,
        );

      if (!artifactPath) {
        return reply.code(404).send({
          success: false,
          error:
            "Firmware artifact not found.",
        });
      }

      reply.header(
        "Content-Type",
        "application/octet-stream",
      );

      reply.header(
        "Content-Length",
        String(
          release.firmwareSizeBytes,
        ),
      );

      reply.header(
        "X-SportsOS-Firmware-SHA256",
        release.firmwareSha256,
      );

      reply.header(
        "X-SportsOS-Firmware-Version",
        release.version,
      );

      return reply.send(
        fs.createReadStream(
          artifactPath,
        ),
      );
    },
  );
}
