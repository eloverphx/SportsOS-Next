import crypto from "node:crypto";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";

import {
  acknowledgeOperationsIncident,
  findOperationsIncidentById,
  listOperationsIncidents,
  openOrUpdateOperationsIncident,
  resolveOperationsIncident,
} from "../services/operationsIncidentJournal.js";

export const OPERATIONS_INCIDENTS_PATH =
  "/deployment/operations/incidents";

function isEnabled(): boolean {
  return (
    process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED
      ?.trim()
      .toLowerCase() === "true"
  );
}

function configuredToken(): string | null {
  const token =
    process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN?.trim() ?? "";
  return token.length >= 32 ? token : null;
}

function bearerToken(request: FastifyRequest): string | null {
  const authorization = request.headers.authorization;
  if (!authorization) {
    return null;
  }

  const match = /^Bearer\s+(.+)$/i.exec(authorization);
  return match?.[1]?.trim() || null;
}

function constantTimeEqual(
  left: string,
  right: string,
): boolean {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);

  if (leftBuffer.length !== rightBuffer.length) {
    return false;
  }

  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

async function authorize(
  request: FastifyRequest,
  reply: FastifyReply,
): Promise<boolean> {
  if (!isEnabled()) {
    await reply.code(404).send({
      success: false,
      error: {
        code: "NOT_FOUND",
        message: "Resource not found.",
      },
    });
    return false;
  }

  const expected = configuredToken();
  if (!expected) {
    await reply.code(503).send({
      success: false,
      error: {
        code: "OPERATIONS_STATUS_MISCONFIGURED",
        message:
          "Protected operations status access is not configured.",
      },
    });
    return false;
  }

  const supplied = bearerToken(request);
  if (!supplied || !constantTimeEqual(supplied, expected)) {
    await reply.code(403).send({
      success: false,
      error: {
        code: "FORBIDDEN",
        message: "Forbidden.",
      },
    });
    return false;
  }

  return true;
}

function setProtectedResponseHeaders(
  reply: FastifyReply,
): void {
  reply.header("Cache-Control", "no-store");
}

export async function registerOperationsIncidentRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.get(
    OPERATIONS_INCIDENTS_PATH,
    async (request, reply) => {
      setProtectedResponseHeaders(reply);

      if (!(await authorize(request, reply))) {
        return;
      }

      const incidents = await listOperationsIncidents();

      return reply.code(200).send({
        success: true,
        data: {
          schemaVersion: 1,
          incidents,
          summary: {
            total: incidents.length,
            open: incidents.filter(
              (incident) => incident.status === "open",
            ).length,
            acknowledged: incidents.filter(
              (incident) =>
                incident.status === "acknowledged",
            ).length,
            resolved: incidents.filter(
              (incident) => incident.status === "resolved",
            ).length,
            critical: incidents.filter(
              (incident) =>
                incident.severity === "critical" &&
                incident.status !== "resolved",
            ).length,
            warning: incidents.filter(
              (incident) =>
                incident.severity === "warning" &&
                incident.status !== "resolved",
            ).length,
          },
        },
      });
    },
  );

  app.get<{
    Params: {
      incidentId: string;
    };
  }>(
    `${OPERATIONS_INCIDENTS_PATH}/:incidentId`,
    async (request, reply) => {
      setProtectedResponseHeaders(reply);

      if (!(await authorize(request, reply))) {
        return;
      }

      const incident = await findOperationsIncidentById(
        request.params.incidentId,
      );

      if (!incident) {
        return reply.code(404).send({
          success: false,
          error: {
            code: "OPERATIONS_INCIDENT_NOT_FOUND",
            message: "Operations incident not found.",
          },
        });
      }

      return reply.code(200).send({
        success: true,
        data: {
          schemaVersion: 1,
          incident,
        },
      });
    },
  );

  // SPORTSOS_M35_6_DELIVERY_FAILURE_SIGNAL_ROUTE
  app.post<{
    Body: {
      incidentId?: string;
      channel?: string;
      detail?: string | null;
      observedAt?: string;
    };
  }>(
    `${OPERATIONS_INCIDENTS_PATH}/signals/escalation-delivery-failure`,
    async (request, reply) => {
      setProtectedResponseHeaders(reply);
      if (!(await authorize(request, reply))) return;

      const incidentId = request.body?.incidentId?.trim() || null;
      const channel = request.body?.channel?.trim() || "webhook";
      const detail = request.body?.detail?.trim() || null;
      const observedAt = request.body?.observedAt?.trim() || undefined;

      const incident = await openOrUpdateOperationsIncident({
        fingerprint:
          "operations:incident-escalation-delivery-failure",
        source: "operations",
        severity: "critical",
        title: "Incident escalation delivery failure",
        summary:
          "SportsOS could not deliver an incident escalation notification.",
        service: "incident-escalation",
        metadata: {
          channel,
          failedIncidentId: incidentId,
          detail,
        },
        observedAt,
      });

      return reply.code(200).send({
        success: true,
        data: {
          schemaVersion: 1,
          incident,
        },
      });
    },
  );

  // SPORTSOS_M34_6_INCIDENT_LIFECYCLE_ROUTES
  app.post<{
    Params: { incidentId: string };
    Body: { actor?: string; note?: string | null };
  }>(
    `${OPERATIONS_INCIDENTS_PATH}/:incidentId/acknowledge`,
    async (request, reply) => {
      setProtectedResponseHeaders(reply);
      if (!(await authorize(request, reply))) return;

      const actor = request.body?.actor?.trim() ?? "";
      if (!actor) {
        return reply.code(400).send({
          success: false,
          error: { code: "INVALID_INCIDENT_ACTOR", message: "actor is required." },
        });
      }

      try {
        const incident = await acknowledgeOperationsIncident(
          request.params.incidentId,
          { actor, note: request.body?.note ?? null },
        );
        if (!incident) {
          return reply.code(404).send({
            success: false,
            error: {
              code: "OPERATIONS_INCIDENT_NOT_FOUND",
              message: "Operations incident not found.",
            },
          });
        }
        return reply.code(200).send({
          success: true,
          data: { schemaVersion: 1, incident },
        });
      } catch (error) {
        return reply.code(409).send({
          success: false,
          error: {
            code: "INVALID_INCIDENT_TRANSITION",
            message: error instanceof Error ? error.message : "Invalid incident transition.",
          },
        });
      }
    },
  );

  app.post<{
    Params: { incidentId: string };
    Body: { actor?: string; note?: string | null };
  }>(
    `${OPERATIONS_INCIDENTS_PATH}/:incidentId/resolve`,
    async (request, reply) => {
      setProtectedResponseHeaders(reply);
      if (!(await authorize(request, reply))) return;

      const actor = request.body?.actor?.trim() ?? "";
      if (!actor) {
        return reply.code(400).send({
          success: false,
          error: { code: "INVALID_INCIDENT_ACTOR", message: "actor is required." },
        });
      }

      const incident = await resolveOperationsIncident(
        request.params.incidentId,
        { actor, note: request.body?.note ?? null },
      );
      if (!incident) {
        return reply.code(404).send({
          success: false,
          error: {
            code: "OPERATIONS_INCIDENT_NOT_FOUND",
            message: "Operations incident not found.",
          },
        });
      }

      return reply.code(200).send({
        success: true,
        data: { schemaVersion: 1, incident },
      });
    },
  );

}
