import type { FastifyInstance } from "fastify";
import { config } from "@sportsos/config";
import { API_DOCUMENTATION_PATH, API_NAME, API_VERSION } from "../platform/metadata.js";

const startedAt = Date.now();

export async function platformRoutes(app: FastifyInstance): Promise<void> {
  app.get(
    "/",
    {
      schema: {
        tags: ["Platform"],
        summary: "API information",
        response: {
          200: {
            type: "object",
            properties: {
              success: { type: "boolean" },
              requestId: { type: "string" },
              data: {
                type: "object",
                properties: {
                  name: { type: "string" },
                  version: { type: "string" },
                  environment: { type: "string" },
                  documentation: { type: "string" },
                },
              },
            },
          },
        },
      },
    },
    async (request) => ({
      success: true,
      requestId: request.id,
      data: {
        name: API_NAME,
        version: API_VERSION,
        environment: config.environment.name,
        documentation: API_DOCUMENTATION_PATH,
      },
    }),
  );

  app.get(
    "/ready",
    {
      schema: {
        tags: ["Platform"],
        summary: "Application readiness",
      },
    },
    async (request) => ({
      success: true,
      requestId: request.id,
      data: {
        status: "ready",
      },
    }),
  );

  app.get(
    "/version",
    {
      schema: {
        tags: ["Platform"],
        summary: "Application version",
      },
    },
    async (request) => ({
      success: true,
      requestId: request.id,
      data: {
        name: API_NAME,
        version: API_VERSION,
        nodeVersion: process.version,
      },
    }),
  );
}
