import type {
  FastifyInstance,
} from "fastify";

import type {
  FirmwareReleaseChannel,
  FirmwareReleaseTarget,
  ScoreboardFirmwareRelease,
} from "@sportsos/core";

import {
  getFirmwareRelease,
  getLatestCompatibleFirmwareRelease,
  listFirmwareReleases,
  registerFirmwareRelease,
} from "../services/scoreboardFirmwareReleaseRegistry.js";

import {
  isVerifiedDevice,
} from "../services/scoreboardDeviceEnrollment.js";

import {
  findActiveRolloutForDevice,
} from "../services/scoreboardFirmwareRollouts.js";

type ReleaseQuery = {
  channel?: FirmwareReleaseChannel;
  target?: FirmwareReleaseTarget;
};

type LatestQuery = {
  currentVersion?: string;
  channel?: FirmwareReleaseChannel;
  target?: FirmwareReleaseTarget;
};

type DeviceOfferQuery = {
  deviceId?: string;
  currentVersion?: string;
  channel?: FirmwareReleaseChannel;
  target?: FirmwareReleaseTarget;
};

export async function registerScoreboardFirmwareReleaseRoutes(
  app: FastifyInstance,
) {
  /*
   * Operator/API release inventory.
   */
  app.get(
    "/scoreboard-firmware/releases",
    async (request) => {
      const query =
        request.query as ReleaseQuery;

      return {
        success: true,
        data: {
          releases:
            listFirmwareReleases({
              channel:
                query.channel,
              target:
                query.target,
            }),
        },
      };
    },
  );

  /*
   * Single release lookup.
   */
  app.get(
    "/scoreboard-firmware/releases/:releaseId",
    async (request, reply) => {
      const { releaseId } =
        request.params as {
          releaseId: string;
        };

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

      return {
        success: true,
        data:
          release,
      };
    },
  );

  /*
   * Register a validated release manifest.
   * Artifact validation/import remains owned by Milestone 13.3.
   */
  app.post(
    "/scoreboard-firmware/releases",
    async (request, reply) => {
      const body =
        request.body as ScoreboardFirmwareRelease;

      if (
        !body?.releaseId ||
        !body?.version ||
        !body?.channel ||
        !body?.target ||
        !body?.firmwareFile ||
        !body?.firmwareSha256 ||
        !body?.firmwareSizeBytes
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Invalid firmware release manifest.",
        });
      }

      const release =
        registerFirmwareRelease(
          body,
        );

      return reply.code(201).send({
        success: true,
        data:
          release,
      });
    },
  );

  /*
   * General compatibility lookup.
   *
   * This route is intentionally NOT rollout-aware. It answers:
   * "Does a newer compatible release exist?"
   *
   * Rollout authorization is enforced only by /device-offer.
   */
  app.get(
    "/scoreboard-firmware/latest",
    async (request, reply) => {
      const query =
        request.query as LatestQuery;

      if (!query.currentVersion) {
        return reply.code(400).send({
          success: false,
          error:
            "currentVersion is required.",
        });
      }

      const release =
        getLatestCompatibleFirmwareRelease({
          currentVersion:
            query.currentVersion,
          channel:
            query.channel ??
            "stable",
          target:
            query.target ??
            "esp32dev",
        });

      return {
        success: true,
        data: {
          updateAvailable:
            release !== null,
          release,
        },
      };
    },
  );

  /*
   * Device-facing OTA offer.
   *
   * A device receives an OTA offer only when:
   *  - it is verified
   *  - an ACTIVE rollout explicitly targets it
   *  - the rollout's release exists
   *  - channel and target match the device request
   *  - the device is not already on that version
   */
  app.get(
    "/scoreboard-firmware/device-offer",
    async (request, reply) => {
      const query =
        request.query as DeviceOfferQuery;

      if (
        !query.deviceId ||
        !query.currentVersion
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "deviceId and currentVersion are required.",
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

      const rollout =
        findActiveRolloutForDevice(
          query.deviceId,
        );

      if (!rollout) {
        return {
          success: true,
          data: {
            updateAvailable: false,
            offer: null,
            rollout: null,
          },
        };
      }

      const release =
        getFirmwareRelease(
          rollout.releaseId,
        );

      if (!release) {
        return {
          success: true,
          data: {
            updateAvailable: false,
            offer: null,
            rollout: {
              rolloutId:
                rollout.rolloutId,
              state:
                rollout.state,
            },
          },
        };
      }

      const requestedChannel =
        query.channel ??
        "stable";

      const requestedTarget =
        query.target ??
        "esp32dev";

      if (
        release.channel !==
          requestedChannel ||
        release.target !==
          requestedTarget
      ) {
        return {
          success: true,
          data: {
            updateAvailable: false,
            offer: null,
            rollout: {
              rolloutId:
                rollout.rolloutId,
              state:
                rollout.state,
            },
          },
        };
      }

      if (
        release.version ===
        query.currentVersion
      ) {
        return {
          success: true,
          data: {
            updateAvailable: false,
            offer: null,
            rollout: {
              rolloutId:
                rollout.rolloutId,
              state:
                rollout.state,
            },
          },
        };
      }

      const artifactUrl =
        `/scoreboard-firmware/releases/${encodeURIComponent(
          release.releaseId,
        )}/artifact?deviceId=${encodeURIComponent(
          query.deviceId,
        )}`;

      return {
        success: true,
        data: {
          updateAvailable: true,
          rollout: {
            rolloutId:
              rollout.rolloutId,
            state:
              rollout.state,
          },
          offer: {
            deviceId:
              query.deviceId,
            currentVersion:
              query.currentVersion,
            release,
            artifactUrl,
          },
        },
      };
    },
  );
}
