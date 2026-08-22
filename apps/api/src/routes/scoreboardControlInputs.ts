import type {
  FastifyInstance,
} from "fastify";
import { executePhysicalScoreboardControl } from "../services/scoreboardPhysicalControlExecution.js";
import { reconcilePhysicalControlResult } from "../services/scoreboardPhysicalControlReconciliation.js";
import { recordScoreboardControlAudit } from "../services/scoreboardControlAudit.js";
import { evaluateScoreboardPhysicalControlPolicy } from "../services/scoreboardControlPolicy.js";
import { evaluateGameLifecyclePhysicalControlPolicy } from "../services/scoreboardControlLifecyclePolicy.js";
import { getEmergencyPhysicalControlLock } from "../services/scoreboardEmergencyControlLock.js";
import { evaluateScoreboardControlReadiness } from "../services/scoreboardControlReadiness.js";

import {
  SCOREBOARD_CONTROL_INPUT_PROTOCOL_VERSION,
  isScoreboardControlInputType,
  type ScoreboardControlInputEvent,
} from "@sportsos/core";

import type {
  AutomaticGameScoreboardSync,
} from "../services/automaticGameScoreboardSync.js";

import {
  isVerifiedDevice,
} from "../services/scoreboardDeviceEnrollment.js";

import {
  processScoreboardControlInput,
} from "../services/scoreboardControlInputs.js";

const DEVICE_ORIGINATED_CONTROL_AUTHORIZATION =
  "VERIFIED_DEVICE_ASSIGNMENT_POLICY_LIFECYCLE_SEQUENCE" as const;

void DEVICE_ORIGINATED_CONTROL_AUTHORIZATION;

export async function registerScoreboardControlInputRoutes(
  app: FastifyInstance,
  automaticSync: AutomaticGameScoreboardSync,
) {
  app.post(
    "/scoreboard-control-inputs",
    async (request, reply) => {
      const body =
        request.body as ScoreboardControlInputEvent;

      if (
        !body?.inputId ||
        !body?.deviceId ||
        !body?.type ||
        !body?.occurredAt ||
        !Number.isInteger(
          body?.sequence,
        ) ||
        body.sequence <= 0
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Invalid scoreboard control input.",
        });
      }

      if (
        body.protocolVersion !==
        SCOREBOARD_CONTROL_INPUT_PROTOCOL_VERSION
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Unsupported scoreboard control input protocol version.",
        });
      }

      if (
        !isScoreboardControlInputType(
          body.type,
        )
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Unsupported scoreboard control input type.",
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

      const result =
        processScoreboardControlInput(
          body,
          automaticSync,
        ) as ReturnType<
          typeof processScoreboardControlInput
        > & {
          command?: unknown;
        };

      /*
       * Milestone 14.4:
       * This route now exposes the authoritative command mapping alongside
       * the acceptance decision. Actual game mutation is delegated to the
       * same server-side game command path in the next binding layer; the
       * ESP32 never mutates game state directly.
       */
      if (
        result.disposition !==
          "ACCEPTED" ||
        !result.authoritativeGameId
      ) {
        recordScoreboardControlAudit({
          auditId: body.inputId,
          deviceId: body.deviceId,
          gameId: result.authoritativeGameId,
          inputId: body.inputId,
          inputType: body.type,
          sequence: body.sequence,
          disposition: result.disposition,
          command:
            "command" in result
              ? result.command
              : null,
          execution: null,
          reconciliation: null,
          error: result.reason,
          createdAt:
            new Date().toISOString(),
        });

        return {
          success: true,
          data:
            result,
        };
      }

      const readinessDecision =
        await evaluateScoreboardControlReadiness(
          body.deviceId,
        );

      if (!readinessDecision.ready) {
        recordScoreboardControlAudit({
          auditId:
            body.inputId,
          deviceId:
            body.deviceId,
          gameId:
            result.authoritativeGameId,
          inputId:
            body.inputId,
          inputType:
            body.type,
          sequence:
            body.sequence,
          disposition:
            "REJECTED",
          command:
            "command" in result
              ? result.command
              : null,
          execution:
            null,
          reconciliation:
            null,
          error:
            readinessDecision.reason ??
            "Scoreboard device is not ready for physical control.",
          createdAt:
            new Date().toISOString(),
        });

        return reply.code(409).send({
          success: false,
          error:
            readinessDecision.reason ??
            "Scoreboard device is not ready for physical control.",
          data: {
            acknowledgement: {
              ...result,
              disposition:
                "REJECTED",
              reason:
                readinessDecision.reason ??
                "Scoreboard device is not ready for physical control.",
            },
            readiness:
              readinessDecision,
          },
        });
      }

      const emergencyPhysicalControlLock =
        getEmergencyPhysicalControlLock();

      if (emergencyPhysicalControlLock.active) {
        recordScoreboardControlAudit({
          auditId: body.inputId,
          deviceId: body.deviceId,
          gameId: result.authoritativeGameId,
          inputId: body.inputId,
          inputType: body.type,
          sequence: body.sequence,
          disposition: "REJECTED",
          command:
            "command" in result
              ? result.command
              : null,
          execution: null,
          reconciliation: null,
          error:
            emergencyPhysicalControlLock.reason ??
            "Emergency physical-control lock is active.",
          createdAt: new Date().toISOString(),
        });

        return reply.code(423).send({
          success: false,
          error:
            emergencyPhysicalControlLock.reason ??
            "Emergency physical-control lock is active.",
          data: {
            acknowledgement: {
              ...result,
              disposition: "REJECTED",
              reason:
                emergencyPhysicalControlLock.reason ??
                "Emergency physical-control lock is active.",
            },
            emergencyLock:
              emergencyPhysicalControlLock,
          },
        });
      }

      const policyDecision =
        evaluateScoreboardPhysicalControlPolicy(
          result.authoritativeGameId,
          body.deviceId,
        );

      const lifecycleDecision =
        await evaluateGameLifecyclePhysicalControlPolicy(
          app,
          result.authoritativeGameId,
        );

      if (!lifecycleDecision.allowed) {
        recordScoreboardControlAudit({
          auditId:
            body.inputId,
          deviceId:
            body.deviceId,
          gameId:
            result.authoritativeGameId,
          inputId:
            body.inputId,
          inputType:
            body.type,
          sequence:
            body.sequence,
          disposition:
            "REJECTED",
          command:
            "command" in result
              ? result.command
              : null,
          execution:
            null,
          reconciliation:
            null,
          error:
            lifecycleDecision.reason ??
            "Physical scoreboard controls are unavailable for the current game lifecycle.",
          createdAt:
            new Date().toISOString(),
        });

        return reply.code(423).send({
          success: false,
          error:
            lifecycleDecision.reason ??
            "Physical scoreboard controls are unavailable for the current game lifecycle.",
          data: {
            acknowledgement: {
              ...result,
              disposition:
                "REJECTED",
              reason:
                lifecycleDecision.reason ??
                "Physical scoreboard controls are unavailable for the current game lifecycle.",
            },
            lifecycle:
              lifecycleDecision,
          },
        });
      }

      if (!policyDecision.allowed) {
        recordScoreboardControlAudit({
          auditId:
            body.inputId,
          deviceId:
            body.deviceId,
          gameId:
            result.authoritativeGameId,
          inputId:
            body.inputId,
          inputType:
            body.type,
          sequence:
            body.sequence,
          disposition:
            "REJECTED",
          command:
            "command" in result
              ? result.command
              : null,
          execution:
            null,
          reconciliation:
            null,
          error:
            policyDecision.reason ??
            "Physical scoreboard controls are locked.",
          createdAt:
            new Date().toISOString(),
        });

        return reply.code(423).send({
          success: false,
          error:
            policyDecision.reason ??
            "Physical scoreboard controls are locked.",
          data: {
            acknowledgement: {
              ...result,
              disposition:
                "REJECTED",
              reason:
                policyDecision.reason ??
                "Physical scoreboard controls are locked.",
            },
            policy:
              policyDecision,
          },
        });
      }

      const execution =
        await executePhysicalScoreboardControl(
          app,
          result.authoritativeGameId,
          body,
        );

      if (!execution.executed) {
        recordScoreboardControlAudit({
          auditId: body.inputId,
          deviceId: body.deviceId,
          gameId: result.authoritativeGameId,
          inputId: body.inputId,
          inputType: body.type,
          sequence: body.sequence,
          disposition: "EXECUTION_FAILED",
          command: execution.command,
          execution,
          reconciliation: null,
          error:
            execution.reason ??
            "Physical scoreboard command was not executed.",
          createdAt:
            new Date().toISOString(),
        });

        return reply.code(
          execution.statusCode >= 400 &&
          execution.statusCode <= 599
            ? execution.statusCode
            : 409,
        ).send({
          success: false,
          error:
            execution.reason ??
            "Physical scoreboard command was not executed.",
          data: {
            acknowledgement:
              result,
            execution,
          },
        });
      }

      if (
        execution.command.kind ===
          "HORN"
      ) {
        recordScoreboardControlAudit({
          auditId:
            body.inputId,
          deviceId:
            body.deviceId,
          gameId:
            result.authoritativeGameId,
          inputId:
            body.inputId,
          inputType:
            body.type,
          sequence:
            body.sequence,
          disposition:
            "ACCEPTED",
          command:
            execution.command,
          execution,
          reconciliation:
            null,
          error:
            null,
          createdAt:
            new Date().toISOString(),
        });

        return {
          success: true,
          data: {
            ...result,
            execution,
            reconciliation:
              null,
          },
        };
      }

      const assignment =
        automaticSync
          .getAssignmentByDeviceId(
            body.deviceId,
          );

      if (!assignment) {
        return reply.code(409).send({
          success: false,
          error:
            "Scoreboard assignment disappeared before reconciliation.",
          data: {
            acknowledgement:
              result,
            execution,
          },
        });
      }

      const reconciliation =
        await reconcilePhysicalControlResult(
          app,
          automaticSync,
          assignment,
        );

      recordScoreboardControlAudit({
        auditId: body.inputId,
        deviceId: body.deviceId,
        gameId: result.authoritativeGameId,
        inputId: body.inputId,
        inputType: body.type,
        sequence: body.sequence,
        disposition: "ACCEPTED",
        command: execution.command,
        execution,
        reconciliation,
        error: reconciliation.reason,
        createdAt:
          new Date().toISOString(),
      });

      return {
        success: true,
        data: {
          ...result,
          execution,
          reconciliation,
        },
      };
    },
  );
}
