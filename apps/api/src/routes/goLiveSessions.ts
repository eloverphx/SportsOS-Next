import type {
  FastifyInstance,
} from "fastify";
import { listGoLiveAuditEvents, recordGoLiveAuditEvent } from "../services/goLiveAudit.js";
import { evaluateGameDayGoLivePreflight } from "../services/gameDayGoLivePreflight.js";

import {
  acknowledgeGoLiveIncident,
  armGoLiveSession,
  clearGoLiveIncidentAcknowledgement,
  completeGoLiveSession,
  configureGoLiveAutoArm,
  configureGoLiveHealthHold,
  evaluateGoLiveHealthHold,
  configureGoLiveSchedule,
  evaluateGoLiveCountdown,
  evaluateGoLiveStartWindow,
  getGoLiveSession,
  clearGoLiveDegraded,
  markGoLiveDegraded,
  markGoLiveEmergencyStopped,
  markGoLiveError,
  markGoLiveLive,
  markGoLiveStarting,
  markGoLiveStopping,
  resetGoLiveSession,
} from "../services/goLiveSession.js";

import {
  evaluateStreamingReadiness,
} from "../services/streamingReadinessPreflight.js";

import {
  encoderRuntimeSnapshot,
  startEncoderRuntime,
  stopEncoderRuntime,
  suppressEncoderRecovery,
} from "../services/encoderRuntime.js";

import {
  getStreamDestinationProfile,
} from "../services/streamDestinationProfile.js";

export async function registerGoLiveSessionRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.get(
    "/go-live-sessions/:gameId/game-day-preflight",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

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
          preflight:
            evaluateGameDayGoLivePreflight(
              gameId,
            ),
        },
      };
    },
  );

  app.get(
    "/go-live-sessions/:gameId/audit",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const query =
        request.query as {
          limit?: string;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const limit =
        Number.parseInt(
          query.limit ??
          "100",
          10,
        );

      return {
        success: true,
        data: {
          events:
            listGoLiveAuditEvents(
              gameId,
              Number.isFinite(limit)
                ? limit
                : 100,
            ),
        },
      };
    },
  );

  app.get(
    "/go-live-sessions/:gameId",
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
          session:
            getGoLiveSession(
              gameId,
            ),
        },
      };
    },
  );

  app.put(
    "/go-live-sessions/:gameId/health-hold",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          seconds?: number;
        };

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
          session:
            configureGoLiveHealthHold(
              gameId,
              Number(
                body.seconds ??
                10,
              ),
            ),
        },
      };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/incident/acknowledge",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          operator?: string | null;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const current =
        getGoLiveSession(
          gameId,
        );

      if (
        current.status !==
        "DEGRADED"
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Only a DEGRADED go-live session can be acknowledged.",
        });
      }

      recordGoLiveAuditEvent({
        gameId,
        type:
          "INCIDENT_ACKNOWLEDGED",
        operator:
          body.operator ??
          null,
      });

      return {
        success: true,
        data: {
          session:
            acknowledgeGoLiveIncident(
              gameId,
              body.operator ??
              null,
            ),
        },
      };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/incident/retry-watchdog",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const current =
        clearGoLiveIncidentAcknowledgement(
          gameId,
        );

      recordGoLiveAuditEvent({
        gameId,
        type:
          "INCIDENT_RETRY",
      });

      return {
        success: true,
        data: {
          session:
            current,
          retryRequired:
            true,
        },
      };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/watchdog",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const current =
        getGoLiveSession(
          gameId,
        );

      const runtime =
        encoderRuntimeSnapshot(
          gameId,
        );

      let session =
        current;

      if (
        current.status ===
          "LIVE" ||
        current.status ===
          "DEGRADED"
      ) {
        const encoderLive =
          runtime.session.status ===
          "LIVE";

        const publishHealthy =
          runtime.telemetry.health ===
          "HEALTHY";

        if (
          !encoderLive ||
          !publishHealthy
        ) {
          const reason =
            !encoderLive
              ? `Encoder session is ${runtime.session.status}.`
              : `Publish health is ${runtime.telemetry.health}.`;

          session =
            markGoLiveDegraded(
              gameId,
              reason,
            );

          recordGoLiveAuditEvent({
            gameId,
            type:
              "DEGRADED",
            detail:
              reason,
          });

          recordGoLiveAuditEvent({
            gameId,
            type:
              "DEGRADED",
            detail:
              reason,
          });
        } else if (
          current.status ===
          "DEGRADED"
        ) {
          session =
            clearGoLiveDegraded(
              gameId,
            );

          recordGoLiveAuditEvent({
            gameId,
            type:
              "RECOVERED",
          });

          recordGoLiveAuditEvent({
            gameId,
            type:
              "RECOVERED",
          });
        }
      }

      return {
        success: true,
        data: {
          session,
          runtime,
          watchdog: {
            healthy:
              session.status !==
              "DEGRADED",
            degradationReason:
              session.degradationReason,
          },
        },
      };
    },
  );

  app.get(
    "/go-live-sessions/:gameId/health-hold",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const runtime =
        encoderRuntimeSnapshot(
          gameId,
        );

      const hold =
        evaluateGoLiveHealthHold({
          gameId,
          encoderLive:
            runtime.session.status ===
            "LIVE",
          publishHealthy:
            runtime.telemetry.health ===
            "HEALTHY",
        });

      return {
        success: true,
        data: {
          session:
            getGoLiveSession(
              gameId,
            ),
          runtime,
          healthHold:
            hold,
        },
      };
    },
  );

  app.put(
    "/go-live-sessions/:gameId/auto-arm",
    async (request, reply) => {
      const params = request.params as { gameId?: string };
      const body = request.body as { enabled?: boolean; leadMinutes?: number };
      const gameId = params.gameId?.trim();
      if (!gameId) return reply.code(400).send({ success:false, error:"Game ID is required." });
      const session = configureGoLiveAutoArm({ gameId, enabled:body.enabled === true, leadMinutes:body.leadMinutes });
      return { success:true, data:{ session, countdown:evaluateGoLiveCountdown(gameId) } };
    },
  );

  app.get(
    "/go-live-sessions/:gameId/countdown",
    async (request, reply) => {
      const gameId = (request.params as { gameId?: string }).gameId?.trim();
      if (!gameId) return reply.code(400).send({ success:false, error:"Game ID is required." });
      return { success:true, data:{ session:getGoLiveSession(gameId), countdown:evaluateGoLiveCountdown(gameId) } };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/auto-arm/evaluate",
    async (request, reply) => {
      const gameId = (request.params as { gameId?: string }).gameId?.trim();
      if (!gameId) return reply.code(400).send({ success:false, error:"Game ID is required." });
      const countdown = evaluateGoLiveCountdown(gameId);
      const current = getGoLiveSession(gameId);
      if (countdown.autoArmDue && ["IDLE","COMPLETE","ERROR"].includes(current.status)) {
        const preflight = evaluateStreamingReadiness(gameId);
        if (preflight.ready) return { success:true, data:{ autoArmed:true, session:armGoLiveSession(gameId), countdown, preflight } };
        return reply.code(409).send({ success:false, error:"Auto-arm is due but streaming readiness preflight failed.", data:{ autoArmed:false, session:current, countdown, preflight } });
      }
      return { success:true, data:{ autoArmed:false, session:current, countdown } };
    },
  );

  app.put(
    "/go-live-sessions/:gameId/schedule",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const body =
        request.body as {
          scheduledStartAt?: string | null;
          startWindowEarlyMinutes?: number;
          startWindowLateMinutes?: number;
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

      try {
        const session =
          configureGoLiveSchedule({
            gameId,
            scheduledStartAt:
              body.scheduledStartAt ??
              null,
            startWindowEarlyMinutes:
              body.startWindowEarlyMinutes,
            startWindowLateMinutes:
              body.startWindowLateMinutes,
          });

        return {
          success: true,
          data: {
            session,
            startWindow:
              evaluateGoLiveStartWindow(
                gameId,
              ),
          },
        };
      } catch {
        return reply.code(400).send({
          success: false,
          error:
            "Invalid scheduled start timestamp.",
        });
      }
    },
  );

  app.get(
    "/go-live-sessions/:gameId/start-window",
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
          session:
            getGoLiveSession(
              gameId,
            ),
          startWindow:
            evaluateGoLiveStartWindow(
              gameId,
            ),
        },
      };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/arm",
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

      // GAME_DAY_GO_LIVE_PREFLIGHT_21_9
      const gameDayPreflight =
        evaluateGameDayGoLivePreflight(
          gameId,
        );

      if (
        !gameDayPreflight.ready
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Game-day go-live preflight failed.",
          data: {
            preflight:
              gameDayPreflight,
          },
        });
      }

      const preflight =
        evaluateStreamingReadiness(
          gameId,
        );

      if (!preflight.ready) {
        return reply.code(409).send({
          success: false,
          error:
            "Streaming readiness preflight must pass before arming go-live.",
          data: {
            preflight,
          },
        });
      }

      recordGoLiveAuditEvent({
        gameId,
        type:
          "ARMED",
      });

      return {
        success: true,
        data: {
          session:
            armGoLiveSession(
              gameId,
            ),
          preflight,
        },
      };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/start",
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

      // GO_LIVE_START_WINDOW_21_2
      const startWindow =
        evaluateGoLiveStartWindow(
          gameId,
        );

      if (!startWindow.withinWindow) {
        return reply.code(409).send({
          success: false,
          error:
            startWindow.tooEarly
              ? "Go-live start window has not opened yet."
              : "Go-live start window has expired.",
          data: {
            startWindow,
          },
        });
      }

      const current =
        getGoLiveSession(
          gameId,
        );

      if (
        current.status ===
        "EMERGENCY_STOPPED"
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Emergency-stopped go-live session must be reset before start.",
        });
      }

      if (
        current.status !==
        "ARMED"
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Go-live session must be ARMED before start.",
        });
      }

      const preflight =
        evaluateStreamingReadiness(
          gameId,
        );

      if (!preflight.ready) {
        return reply.code(409).send({
          success: false,
          error:
            "Streaming readiness preflight failed before go-live start.",
          data: {
            preflight,
          },
        });
      }

      const destination =
        getStreamDestinationProfile(
          gameId,
        );

      if (!destination) {
        return reply.code(409).send({
          success: false,
          error:
            "Stream destination is missing.",
        });
      }

      recordGoLiveAuditEvent({
        gameId,
        type:
          "START_REQUESTED",
      });

      markGoLiveStarting(
        gameId,
      );

      recordGoLiveAuditEvent({
        gameId,
        type:
          "STARTING",
      });

      try {
        await startEncoderRuntime({
          gameId,
          destination,
        });
      } catch (error) {
        const message =
          error instanceof Error
            ? error.message
            : "Unable to start encoder runtime.";

        const session =
          markGoLiveError(
            gameId,
            message,
          );

        return reply.code(500).send({
          success: false,
          error:
            message,
          data: {
            session,
          },
        });
      }

      return {
        success: true,
        data: {
          session:
            getGoLiveSession(
              gameId,
            ),
          runtime:
            encoderRuntimeSnapshot(
              gameId,
            ),
        },
      };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/confirm-live",
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

      const runtime =
        encoderRuntimeSnapshot(
          gameId,
        );

      // GO_LIVE_HEALTH_HOLD_21_4
      const healthHold =
        evaluateGoLiveHealthHold({
          gameId,
          encoderLive:
            runtime.session.status ===
            "LIVE",
          publishHealthy:
            runtime.telemetry.health ===
            "HEALTHY",
        });

      if (
        !healthHold.readyToConfirm
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Publish health has not remained healthy for the required confirmation hold.",
          data: {
            runtime,
            healthHold,
          },
        });
      }


      if (
        runtime.session.status !==
          "LIVE" ||
        runtime.telemetry.health !==
          "HEALTHY"
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Encoder must be LIVE with HEALTHY publish telemetry before go-live confirmation.",
          data: {
            runtime,
          },
        });
      }

      recordGoLiveAuditEvent({
        gameId,
        type:
          "LIVE_CONFIRMED",
      });

      return {
        success: true,
        data: {
          session:
            markGoLiveLive(
              gameId,
            ),
          runtime,
        },
      };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/emergency-stop",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          reason?: string | null;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      suppressEncoderRecovery(
        gameId,
      );

      await stopEncoderRuntime(
        gameId,
      );

      const session =
        markGoLiveEmergencyStopped(
          gameId,
          body.reason ??
          null,
        );

      recordGoLiveAuditEvent({
        gameId,
        type:
          "EMERGENCY_STOP",
        detail:
          body.reason ??
          null,
      });

      return {
        success: true,
        data: {
          session,
          runtime:
            encoderRuntimeSnapshot(
              gameId,
            ),
        },
      };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/stop",
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

      recordGoLiveAuditEvent({
        gameId,
        type:
          "STOP_REQUESTED",
      });

      markGoLiveStopping(
        gameId,
      );

      await stopEncoderRuntime(
        gameId,
      );

      recordGoLiveAuditEvent({
        gameId,
        type:
          "COMPLETE",
      });

      return {
        success: true,
        data: {
          session:
            completeGoLiveSession(
              gameId,
            ),
          runtime:
            encoderRuntimeSnapshot(
              gameId,
            ),
        },
      };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/reset",
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
          session:
            resetGoLiveSession(
              gameId,
            ),
        },
      };
    },
  );
}
