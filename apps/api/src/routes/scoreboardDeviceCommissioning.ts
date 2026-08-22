import type {
  FastifyInstance,
} from "fastify";
import { validateScoreboardCommissioning } from "../services/scoreboardCommissioningValidator.js";
import { createCommissioningSelfTestResult, latestCommissioningSelfTest } from "../services/scoreboardCommissioningSelfTest.js";
import { acknowledgeCommissioningSelfTestDispatch, completeCommissioningSelfTestDispatch, createCommissioningSelfTestDispatch, getCommissioningSelfTestDispatch } from "../services/scoreboardCommissioningSelfTestDispatch.js";
import { publishCommissioningSelfTestCommand } from "../services/scoreboardDeviceGateway.js";
import { buildCommissioningSelfTestTransportCommand } from "../services/scoreboardCommissioningSelfTestTransport.js";

import {
  beginScoreboardCommissioning,
  getScoreboardCommissioning,
  listScoreboardCommissioning,
  updateScoreboardCommissioningStep,
  type CommissioningStepId,
} from "../services/scoreboardDeviceCommissioning.js";

const VALID_STEPS =
  new Set<CommissioningStepId>([
    "FLASHED",
    "PROVISIONED",
    "ENROLLED",
    "VERIFIED",
    "ASSIGNED",
    "CONNECTIVITY",
    "READINESS",
    "FIRMWARE",
    "GAME_READY",
  ]);

export async function registerScoreboardDeviceCommissioningRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.get(
    "/scoreboard-device-commissioning/:deviceId/self-test",
    async (request, reply) => {
      const params =
        request.params as {
          deviceId?: string;
        };

      const deviceId =
        params.deviceId?.trim();

      if (!deviceId) {
        return reply.code(400).send({
          success: false,
          error:
            "Device ID is required.",
        });
      }

      return {
        success: true,
        data: {
          selfTest:
            latestCommissioningSelfTest(
              deviceId,
            ),
        },
      };
    },
  );

  app.post(
    "/scoreboard-device-commissioning/:deviceId/self-test",
    async (request, reply) => {
      const params =
        request.params as {
          deviceId?: string;
        };

      const body =
        request.body as {
          controllerPassed?: boolean;
          displayPassed?: boolean;
          inputPassed?: boolean;
          connectivityPassed?: boolean;
          firmwareRuntimePassed?: boolean;
          details?: {
            controller?: string;
            display?: string;
            input?: string;
            connectivity?: string;
            firmwareRuntime?: string;
          };
        };

      const deviceId =
        params.deviceId?.trim();

      if (!deviceId) {
        return reply.code(400).send({
          success: false,
          error:
            "Device ID is required.",
        });
      }

      const required = [
        body.controllerPassed,
        body.displayPassed,
        body.inputPassed,
        body.connectivityPassed,
        body.firmwareRuntimePassed,
      ];

      if (
        required.some(
          (value) =>
            typeof value !==
            "boolean",
        )
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "All hardware self-test checks must be reported.",
        });
      }

      const result =
        createCommissioningSelfTestResult({
          deviceId,
          source:
            "INSTALLER",
          startedAt:
            new Date().toISOString(),
          checks: [
            {
              id:
                "CONTROLLER",
              passed:
                body.controllerPassed ===
                true,
              detail:
                body.details?.controller ??
                "Controller runtime check.",
            },
            {
              id:
                "DISPLAY",
              passed:
                body.displayPassed ===
                true,
              detail:
                body.details?.display ??
                "Scoreboard display path check.",
            },
            {
              id:
                "INPUT",
              passed:
                body.inputPassed ===
                true,
              detail:
                body.details?.input ??
                "Physical control input path check.",
            },
            {
              id:
                "CONNECTIVITY",
              passed:
                body.connectivityPassed ===
                true,
              detail:
                body.details?.connectivity ??
                "SportsOS connectivity check.",
            },
            {
              id:
                "FIRMWARE_RUNTIME",
              passed:
                body.firmwareRuntimePassed ===
                true,
              detail:
                body.details?.firmwareRuntime ??
                "Firmware runtime check.",
            },
          ],
        });

      return {
        success: true,
        data: {
          selfTest:
            result,
        },
      };
    },
  );


  app.post(
    "/scoreboard-device-commissioning/:deviceId/self-test/dispatch",
    async (request, reply) => {
      const params =
        request.params as {
          deviceId?: string;
        };

      const deviceId =
        params.deviceId?.trim();

      if (!deviceId) {
        return reply.code(400).send({
          success: false,
          error:
            "Device ID is required.",
        });
      }

      const dispatch =
        createCommissioningSelfTestDispatch(
          deviceId,
        );

      /*
       * 17.8 establishes the correlated command contract.
       * MQTT/device-gateway publication can consume this command
       * object without changing the API correlation model.
       */
      const command =
        buildCommissioningSelfTestTransportCommand(
          dispatch,
        );

      try {
        await publishCommissioningSelfTestCommand(
          deviceId,
          command,
        );
      } catch (error) {
        return reply.code(503).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Unable to publish commissioning self-test command.",
          data: {
            dispatch,
          },
        });
      }

      return reply.code(202).send({
        success: true,
        data: {
          dispatch,
          command,
        },
      });
    },
  );

  app.get(
    "/scoreboard-device-commissioning/:deviceId/self-test/dispatch/:commandId",
    async (request, reply) => {
      const params =
        request.params as {
          deviceId?: string;
          commandId?: string;
        };

      const deviceId =
        params.deviceId?.trim();
      const commandId =
        params.commandId?.trim();

      if (
        !deviceId ||
        !commandId
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Device ID and command ID are required.",
        });
      }

      const dispatch =
        getCommissioningSelfTestDispatch(
          commandId,
        );

      if (
        !dispatch ||
        dispatch.deviceId !==
          deviceId
      ) {
        return reply.code(404).send({
          success: false,
          error:
            "Self-test dispatch not found.",
        });
      }

      return {
        success: true,
        data: {
          dispatch,
        },
      };
    },
  );

  app.post(
    "/scoreboard-device-commissioning/:deviceId/self-test/dispatch/:commandId/ack",
    async (request, reply) => {
      const params =
        request.params as {
          deviceId?: string;
          commandId?: string;
        };

      const deviceId =
        params.deviceId?.trim();
      const commandId =
        params.commandId?.trim();

      if (
        !deviceId ||
        !commandId
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Device ID and command ID are required.",
        });
      }

      try {
        return {
          success: true,
          data: {
            dispatch:
              acknowledgeCommissioningSelfTestDispatch(
                commandId,
                deviceId,
              ),
          },
        };
      } catch (error) {
        return reply.code(409).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Unable to acknowledge self-test command.",
        });
      }
    },
  );

  app.post(
    "/scoreboard-device-commissioning/:deviceId/self-test/telemetry",
    async (request, reply) => {
      const params =
        request.params as {
          deviceId?: string;
        };

      const body =
        request.body as {
          deviceId?: string;
          controllerPassed?: boolean;
          displayPassed?: boolean;
          inputPassed?: boolean;
          connectivityPassed?: boolean;
          firmwareRuntimePassed?: boolean;
          detail?: string;
          commandId?: string;
        };

      const deviceId =
        params.deviceId?.trim();

      if (!deviceId) {
        return reply.code(400).send({
          success: false,
          error:
            "Device ID is required.",
        });
      }

      if (
        body.deviceId &&
        body.deviceId.trim() !==
          deviceId
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Telemetry device ID does not match route device ID.",
        });
      }

      const required = [
        body.controllerPassed,
        body.displayPassed,
        body.inputPassed,
        body.connectivityPassed,
        body.firmwareRuntimePassed,
      ];

      if (
        required.some(
          (value) =>
            typeof value !==
            "boolean",
        )
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Firmware telemetry must report every self-test check.",
        });
      }

      const detail =
        typeof body.detail ===
          "string" &&
        body.detail.trim()
          ? body.detail.trim()
          : "Firmware-reported commissioning self-test.";

      const result =
        createCommissioningSelfTestResult({
          deviceId,
          source:
            "FIRMWARE",
          startedAt:
            new Date().toISOString(),
          checks: [
            {
              id:
                "CONTROLLER",
              passed:
                body.controllerPassed ===
                true,
              detail,
            },
            {
              id:
                "DISPLAY",
              passed:
                body.displayPassed ===
                true,
              detail,
            },
            {
              id:
                "INPUT",
              passed:
                body.inputPassed ===
                true,
              detail,
            },
            {
              id:
                "CONNECTIVITY",
              passed:
                body.connectivityPassed ===
                true,
              detail,
            },
            {
              id:
                "FIRMWARE_RUNTIME",
              passed:
                body.firmwareRuntimePassed ===
                true,
              detail,
            },
          ],
        });

      let correlatedDispatch =
        null;

      if (
        typeof body.commandId ===
          "string" &&
        body.commandId.trim()
      ) {
        try {
          correlatedDispatch =
            completeCommissioningSelfTestDispatch(
              body.commandId.trim(),
              deviceId,
              result.testId,
              result.status ===
                "PASS",
            );
        } catch (error) {
          return reply.code(409).send({
            success: false,
            error:
              error instanceof Error
                ? error.message
                : "Unable to correlate self-test result.",
          });
        }
      }

      return reply.code(202).send({
        success: true,
        data: {
          acknowledged:
            true,
          selfTest:
            result,
          dispatch:
            correlatedDispatch,
        },
      });
    },
  );


  app.post(
    "/scoreboard-device-commissioning/:deviceId/validate",
    async (request, reply) => {
      const params =
        request.params as {
          deviceId?: string;
        };

      const deviceId =
        params.deviceId?.trim();

      if (!deviceId) {
        return reply.code(400).send({
          success: false,
          error:
            "Device ID is required.",
        });
      }

      try {
        return {
          success: true,
          data: {
            commissioning:
              await validateScoreboardCommissioning(
                app,
                deviceId,
              ),
          },
        };
      } catch (error) {
        return reply.code(409).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Unable to validate scoreboard commissioning.",
        });
      }
    },
  );


  app.get(
    "/scoreboard-device-commissioning",
    async () => ({
      success: true,
      data: {
        devices:
          listScoreboardCommissioning(),
      },
    }),
  );

  app.get(
    "/scoreboard-device-commissioning/:deviceId",
    async (request, reply) => {
      const params =
        request.params as {
          deviceId?: string;
        };

      const deviceId =
        params.deviceId?.trim();

      if (!deviceId) {
        return reply.code(400).send({
          success: false,
          error:
            "Device ID is required.",
        });
      }

      const record =
        getScoreboardCommissioning(
          deviceId,
        );

      if (!record) {
        return reply.code(404).send({
          success: false,
          error:
            "Commissioning record not found.",
        });
      }

      return {
        success: true,
        data: {
          commissioning:
            record,
        },
      };
    },
  );

  app.post(
    "/scoreboard-device-commissioning/:deviceId",
    async (request, reply) => {
      const params =
        request.params as {
          deviceId?: string;
        };

      const deviceId =
        params.deviceId?.trim();

      if (!deviceId) {
        return reply.code(400).send({
          success: false,
          error:
            "Device ID is required.",
        });
      }

      return {
        success: true,
        data: {
          commissioning:
            beginScoreboardCommissioning(
              deviceId,
            ),
        },
      };
    },
  );

  app.put(
    "/scoreboard-device-commissioning/:deviceId/step",
    async (request, reply) => {
      const params =
        request.params as {
          deviceId?: string;
        };

      const body =
        request.body as {
          step?: string;
          complete?: boolean;
          note?: string | null;
        };

      const deviceId =
        params.deviceId?.trim();

      if (
        !deviceId ||
        !body.step ||
        typeof body.complete !==
          "boolean" ||
        !VALID_STEPS.has(
          body.step as
            CommissioningStepId,
        )
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Valid device ID, commissioning step, and completion state are required.",
        });
      }

      try {
        const commissioning =
          updateScoreboardCommissioningStep({
            deviceId,
            step:
              body.step as
                CommissioningStepId,
            complete:
              body.complete,
            note:
              body.note,
          });

        return {
          success: true,
          data: {
            commissioning,
          },
        };
      } catch (error) {
        return reply.code(409).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Unable to update commissioning state.",
        });
      }
    },
  );
}
