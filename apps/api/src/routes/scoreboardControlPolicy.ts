import type {
  FastifyInstance,
} from "fastify";
import { hasScoreboardControlPermission } from "../services/scoreboardControlAuthorization.js";
import { listScoreboardControlPolicyAudit, recordScoreboardControlPolicyAudit } from "../services/scoreboardControlPolicyAudit.js";
import { getScoreboardControlPrincipal } from "../services/scoreboardControlAuthorization.js";
import { getEmergencyPhysicalControlLock, setEmergencyPhysicalControlLock } from "../services/scoreboardEmergencyControlLock.js";
import { getPhysicalControlHealthStatus } from "../services/scoreboardPhysicalControlHealth.js";
import { listScoreboardControlIncidents } from "../services/scoreboardControlAudit.js";
import { getScoreboardControlIncidentResolution, listScoreboardControlIncidentResolutions, setScoreboardControlIncidentResolution } from "../services/scoreboardControlIncidentResolution.js";
import { evaluateScoreboardControlReadiness } from "../services/scoreboardControlReadiness.js";
import { checkScoreboardReadinessIncidents } from "../services/scoreboardReadinessIncidentMonitor.js";
import { listScoreboardControlReadinessEvents } from "../services/scoreboardControlAudit.js";
import { listScoreboardReadinessMetrics, readinessAvailabilityPercent } from "../services/scoreboardReadinessMetrics.js";
import { getScoreboardReliabilityThresholds, listScoreboardReliabilityClassifications } from "../services/scoreboardReadinessReliability.js";
import { clearPregameReadinessOverride, evaluatePregameReadinessGate, setPregameReadinessOverride } from "../services/scoreboardPregameReadinessGate.js";

import type {
  ScoreboardPhysicalControlPolicyMode,
  ScoreboardPhysicalControlPolicyScope,
} from "@sportsos/core";

import {
  deleteScoreboardPhysicalControlPolicy,
  getScoreboardPhysicalControlPolicyByScope,
  listScoreboardPhysicalControlPolicies,
  setScoreboardPhysicalControlPolicy,
} from "../services/scoreboardControlPolicy.js";

function parseScope(
  body: unknown,
): ScoreboardPhysicalControlPolicyScope | null {
  const value =
    body as {
      scopeType?: string;
      gameId?: string | null;
      deviceId?: string | null;
    };

  const gameId =
    value?.gameId?.trim() ||
    null;

  const deviceId =
    value?.deviceId?.trim() ||
    null;

  if (
    value?.scopeType ===
      "GAME" &&
    gameId
  ) {
    return {
      scopeType: "GAME",
      gameId,
      deviceId: null,
    };
  }

  if (
    value?.scopeType ===
      "DEVICE" &&
    deviceId
  ) {
    return {
      scopeType: "DEVICE",
      gameId: null,
      deviceId,
    };
  }

  if (
    value?.scopeType ===
      "GAME_DEVICE" &&
    gameId &&
    deviceId
  ) {
    return {
      scopeType:
        "GAME_DEVICE",
      gameId,
      deviceId,
    };
  }

  return null;
}

export async function registerScoreboardControlPolicyRoutes(
  app: FastifyInstance,
) {
  app.get(
    "/scoreboard-control-pregame-gate",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy read permission required.",
        });
      }

      const query =
        request.query as {
          gameId?: string;
          deviceId?: string;
        };

      const gameId =
        query.gameId?.trim();

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
          gate:
            evaluatePregameReadinessGate({
              gameId,
              deviceId:
                query.deviceId?.trim() ||
                null,
            }),
        },
      };
    },
  );

  app.put(
    "/scoreboard-control-pregame-gate/override",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_WRITE",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy write permission required.",
        });
      }

      const body =
        request.body as {
          gameId?: string;
          deviceId?: string;
          reason?: string;
        };

      const gameId =
        body.gameId?.trim();

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
            "Game ID, device ID, and override reason are required.",
        });
      }

      const principal =
        getScoreboardControlPrincipal(
          request,
        );

      const override =
        setPregameReadinessOverride({
          gameId,
          deviceId,
          reason,
          actorUserId:
            principal.userId,
          actorRoles:
            principal.roles,
        });

      return {
        success: true,
        data: {
          override,
          gate:
            evaluatePregameReadinessGate({
              gameId,
              deviceId,
            }),
        },
      };
    },
  );

  app.delete(
    "/scoreboard-control-pregame-gate/override",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_WRITE",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy write permission required.",
        });
      }

      const body =
        request.body as {
          gameId?: string;
          deviceId?: string;
        };

      const gameId =
        body.gameId?.trim();

      const deviceId =
        body.deviceId?.trim();

      if (
        !gameId ||
        !deviceId
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID and device ID are required.",
        });
      }

      return {
        success: true,
        data: {
          cleared:
            clearPregameReadinessOverride(
              gameId,
              deviceId,
            ),
        },
      };
    },
  );


  app.get(
    "/scoreboard-control-readiness-reliability",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy read permission required.",
        });
      }

      return {
        success: true,
        data: {
          thresholds:
            getScoreboardReliabilityThresholds(),
          devices:
            listScoreboardReliabilityClassifications(),
        },
      };
    },
  );


  app.get(
    "/scoreboard-control-readiness-metrics",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy read permission required.",
        });
      }

      const metrics =
        listScoreboardReadinessMetrics();

      return {
        success: true,
        data: {
          metrics:
            metrics.map(
              (metric) => ({
                ...metric,
                availabilityPercent:
                  readinessAvailabilityPercent(
                    metric,
                  ),
              }),
            ),
        },
      };
    },
  );


  app.get(
    "/scoreboard-control-readiness-stability",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy read permission required.",
        });
      }

      const configured =
        Number.parseInt(
          process.env.SPORTSOS_READINESS_STABILITY_WINDOW_MS ??
            "20000",
          10,
        );

      return {
        success: true,
        data: {
          stabilityWindowMs:
            Number.isFinite(
              configured,
            ) &&
            configured >= 0
              ? configured
              : 20000,
        },
      };
    },
  );


  app.get(
    "/scoreboard-control-readiness-events",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy read permission required.",
        });
      }

      const query =
        request.query as {
          limit?: string;
        };

      const parsed =
        query.limit
          ? Number.parseInt(
              query.limit,
              10,
            )
          : 50;

      const limit =
        Number.isFinite(
          parsed,
        )
          ? parsed
          : 50;

      return {
        success: true,
        data: {
          events:
            listScoreboardControlReadinessEvents(
              limit,
            ),
        },
      };
    },
  );


  app.post(
    "/scoreboard-control-readiness/check",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_WRITE",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy write permission required.",
        });
      }

      await checkScoreboardReadinessIncidents(
        app,
      );

      return {
        success: true,
        data: {
          checked: true,
        },
      };
    },
  );


  app.get(
    "/scoreboard-control-readiness/:deviceId",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy read permission required.",
        });
      }

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
            "Scoreboard device ID is required.",
        });
      }

      return {
        success: true,
        data: {
          readiness:
            await evaluateScoreboardControlReadiness(
              deviceId,
            ),
        },
      };
    },
  );


  app.get(
    "/scoreboard-control-incident-resolutions",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy read permission required.",
        });
      }

      return {
        success: true,
        data: {
          resolutions:
            listScoreboardControlIncidentResolutions(),
        },
      };
    },
  );

  app.put(
    "/scoreboard-control-incidents/:auditId",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_WRITE",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy write permission required.",
        });
      }

      const params =
        request.params as {
          auditId?: string;
        };

      const body =
        request.body as {
          status?:
            | "OPEN"
            | "ACKNOWLEDGED"
            | "RESOLVED";
          note?: string | null;
        };

      const auditId =
        params.auditId?.trim();

      if (!auditId) {
        return reply.code(400).send({
          success: false,
          error:
            "Incident audit ID is required.",
        });
      }

      if (
        body.status !== "OPEN" &&
        body.status !== "ACKNOWLEDGED" &&
        body.status !== "RESOLVED"
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Incident status must be OPEN, ACKNOWLEDGED, or RESOLVED.",
        });
      }

      if (
        body.status === "RESOLVED" &&
        !body.note?.trim()
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "A resolution note is required when resolving an incident.",
        });
      }

      const principal =
        getScoreboardControlPrincipal(
          request,
        );

      const previous =
        getScoreboardControlIncidentResolution(
          auditId,
        );

      const resolution =
        setScoreboardControlIncidentResolution({
          auditId,
          status:
            body.status,
          note:
            body.note,
          actorUserId:
            principal.userId,
          actorRoles:
            principal.roles,
        });

      return {
        success: true,
        data: {
          previous,
          resolution,
        },
      };
    },
  );


  app.get(
    "/scoreboard-control-incidents",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy read permission required.",
        });
      }

      const query =
        request.query as {
          limit?: string;
        };

      const parsed =
        query.limit
          ? Number.parseInt(
              query.limit,
              10,
            )
          : 50;

      const limit =
        Number.isFinite(parsed)
          ? parsed
          : 50;

      return {
        success: true,
        data: {
          incidents:
            listScoreboardControlIncidents(
              limit,
            ),
        },
      };
    },
  );


  app.get(
    "/scoreboard-control-health",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy read permission required.",
        });
      }

      return {
        success: true,
        data: {
          health:
            getPhysicalControlHealthStatus(),
        },
      };
    },
  );


  app.get(
    "/scoreboard-control-emergency-lock",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error: "Physical control policy read permission required.",
        });
      }

      return {
        success: true,
        data: {
          emergencyLock:
            getEmergencyPhysicalControlLock(),
        },
      };
    },
  );

  app.put(
    "/scoreboard-control-emergency-lock",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_WRITE",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error: "Physical control policy write permission required.",
        });
      }

      const body =
        request.body as {
          active?: boolean;
          reason?: string | null;
        };

      if (typeof body?.active !== "boolean") {
        return reply.code(400).send({
          success: false,
          error: "Emergency lock active state is required.",
        });
      }

      if (
        body.active &&
        !body.reason?.trim()
      ) {
        return reply.code(400).send({
          success: false,
          error: "A reason is required to activate the emergency lock.",
        });
      }

      const principal =
        getScoreboardControlPrincipal(request);

      const previous =
        getEmergencyPhysicalControlLock();

      const emergencyLock =
        setEmergencyPhysicalControlLock({
          active: body.active,
          reason: body.reason,
          actorUserId: principal.userId,
          actorRoles: principal.roles,
        });

      recordScoreboardControlPolicyAudit({
        auditId:
          `${Date.now()}-${Math.random().toString(36).slice(2)}`,
        action: "SET",
        actorUserId: principal.userId,
        actorRoles: principal.roles,
        previousPolicy: null,
        nextPolicy: null,
        reason:
          body.reason?.trim() ||
          (
            body.active
              ? "Emergency physical-control lock activated."
              : "Emergency physical-control lock cleared."
          ),
        createdAt:
          new Date().toISOString(),
      });

      return {
        success: true,
        data: {
          previousEmergencyLock: previous,
          emergencyLock,
        },
      };
    },
  );


  app.get(
    "/scoreboard-control-policy-audit",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy read permission required.",
        });
      }

      const query =
        request.query as {
          limit?: string;
        };

      const limit =
        query.limit
          ? Number.parseInt(
              query.limit,
              10,
            )
          : 100;

      return {
        success: true,
        data: {
          records:
            listScoreboardControlPolicyAudit(
              Number.isFinite(limit)
                ? limit
                : 100,
            ),
        },
      };
    },
  );


  app.get(
    "/scoreboard-control-policies",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error: "Physical control policy read permission required.",
        });
      }

      return ({
      success: true,
      data: {
        policies:
          listScoreboardPhysicalControlPolicies(),
      },
    });
    },
  );

  app.put(
    "/scoreboard-control-policies",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_WRITE",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error: "Physical control policy write permission required.",
        });
      }

      const body =
        request.body as {
          scopeType?: string;
          gameId?: string | null;
          deviceId?: string | null;
          mode?: string;
          reason?: string | null;
        };

      const scope =
        parseScope(body);

      if (!scope) {
        return reply.code(400).send({
          success: false,
          error:
            "Invalid physical control policy scope.",
        });
      }

      if (
        body.mode !==
          "ENABLED" &&
        body.mode !==
          "LOCKED"
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Physical control policy mode must be ENABLED or LOCKED.",
        });
      }

      const previousPolicy =
        getScoreboardPhysicalControlPolicyByScope(
          scope,
        );

      const policy =
        setScoreboardPhysicalControlPolicy(
          scope,
          body.mode as
            ScoreboardPhysicalControlPolicyMode,
          body.reason,
        );

      const principal =
        getScoreboardControlPrincipal(
          request,
        );

      recordScoreboardControlPolicyAudit({
        auditId:
          `${Date.now()}-${Math.random().toString(36).slice(2)}`,
        action:
          "SET",
        actorUserId:
          principal.userId,
        actorRoles:
          principal.roles,
        previousPolicy,
        nextPolicy:
          policy,
        reason:
          body.reason?.trim() ||
          null,
        createdAt:
          new Date().toISOString(),
      });

      return {
        success: true,
        data: {
          policy,
        },
      };
    },
  );

  app.delete(
    "/scoreboard-control-policies",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_WRITE",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error: "Physical control policy write permission required.",
        });
      }

      const scope =
        parseScope(
          request.body,
        );

      if (!scope) {
        return reply.code(400).send({
          success: false,
          error:
            "Invalid physical control policy scope.",
        });
      }

      const previousPolicy =
        getScoreboardPhysicalControlPolicyByScope(
          scope,
        );

      const deleted =
        deleteScoreboardPhysicalControlPolicy(
          scope,
        );

      if (deleted) {
        const principal =
          getScoreboardControlPrincipal(
            request,
          );

        recordScoreboardControlPolicyAudit({
          auditId:
            `${Date.now()}-${Math.random().toString(36).slice(2)}`,
          action:
            "DELETE",
          actorUserId:
            principal.userId,
          actorRoles:
            principal.roles,
          previousPolicy,
          nextPolicy:
            null,
          reason:
            previousPolicy?.reason ??
            null,
          createdAt:
            new Date().toISOString(),
        });
      }

      return {
        success: true,
        data: {
          deleted,
        },
      };
    },
  );
}
