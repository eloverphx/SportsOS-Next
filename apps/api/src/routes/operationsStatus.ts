import { timingSafeEqual } from "node:crypto";
import { readFile } from "node:fs/promises";
import type { FastifyInstance } from "fastify";

const DEFAULT_STATUS_FILE =
  "/app/data/operations-status/latest.json";

const ROUTE =
  "/deployment/operations/status";

type OperationsSnapshot = {
  schemaVersion: number;
  generatedAt: string;
  windowHours: number;
  overallStatus: string;
  reliability: unknown;
  latest: unknown;
  recent: unknown;
};

function tokenMatches(
  supplied: string | undefined,
  expected: string,
): boolean {
  if (!supplied?.startsWith("Bearer ")) {
    return false;
  }

  const suppliedToken =
    supplied.slice("Bearer ".length).trim();

  const left = Buffer.from(suppliedToken);
  const right = Buffer.from(expected);

  if (left.length !== right.length) {
    return false;
  }

  return timingSafeEqual(left, right);
}

export async function registerOperationsStatusRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.get(
    ROUTE,
    async (request, reply) => {
      const enabled =
        process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED ===
        "true";

      if (!enabled) {
        return reply.code(404).send({
          success: false,
          error: "Not Found",
        });
      }

      const expectedToken =
        process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN ?? "";

      if (expectedToken.length < 32) {
        request.log.error(
          "Operations status API is enabled but token is missing or too short",
        );

        return reply.code(503).send({
          success: false,
          error: "Operations status unavailable",
        });
      }

      if (
        !tokenMatches(
          request.headers.authorization,
          expectedToken,
        )
      ) {
        return reply.code(403).send({
          success: false,
          error: "Forbidden",
        });
      }

      const statusFile =
        process.env.SPORTSOS_OPERATIONS_STATUS_FILE ??
        DEFAULT_STATUS_FILE;

      let snapshot: OperationsSnapshot;

      try {
        snapshot =
          JSON.parse(
            await readFile(statusFile, "utf8"),
          ) as OperationsSnapshot;
      } catch (error) {
        request.log.error(
          { err: error },
          "Unable to read operations status snapshot",
        );

        return reply.code(503).send({
          success: false,
          error: "Operations status unavailable",
        });
      }

      return reply
        .header("Cache-Control", "no-store")
        .code(200)
        .send({
          success: true,
          data: snapshot,
        });
    },
  );
}
