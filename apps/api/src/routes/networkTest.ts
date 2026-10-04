import type { FastifyInstance } from "fastify";

const MAX_UPLOAD_BYTES = 1024 * 1024;

export async function registerNetworkTestRoutes(app: FastifyInstance): Promise<void> {
  app.get(
    "/streaming/network-test/ping",
    {
      schema: {
        tags: ["Streaming"],
        summary: "Camera network latency probe",
      },
    },
    async (request) => {
      return {
        success: true,
        requestId: request.id,
        data: {
          serverTimeMs: Date.now(),
        },
      };
    },
  );

  app.post<{ Body: string }>(
    "/streaming/network-test/upload",
    {
      bodyLimit: MAX_UPLOAD_BYTES,
      config: {
        rateLimit: {
          max: 20,
          timeWindow: "1 minute",
        },
      },
      schema: {
        tags: ["Streaming"],
        summary: "Camera upload throughput probe",
      },
    },
    async (request, reply) => {
      const body = request.body ?? "";

      const receivedBytes = Buffer.byteLength(body, "utf8");

      if (receivedBytes > MAX_UPLOAD_BYTES) {
        return reply.code(413).send({
          success: false,
          requestId: request.id,
          error: {
            code: "NETWORK_TEST_PAYLOAD_TOO_LARGE",
            message: "Network test payload exceeded maximum size",
          },
        });
      }

      return {
        success: true,
        requestId: request.id,
        data: {
          receivedBytes,
          serverTimeMs: Date.now(),
        },
      };
    },
  );
}
