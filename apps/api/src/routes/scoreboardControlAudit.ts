import type {
  FastifyInstance,
} from "fastify";

import {
  listScoreboardControlAudit,
} from "../services/scoreboardControlAudit.js";

export async function registerScoreboardControlAuditRoutes(
  app: FastifyInstance,
) {
  app.get(
    "/scoreboard-control-audit",
    async (request) => {
      const query =
        request.query as {
          deviceId?: string;
          gameId?: string;
          disposition?: string;
          limit?: string;
        };

      const limit =
        query.limit
          ? Number.parseInt(
              query.limit,
              10,
            )
          : undefined;

      return {
        success: true,
        data: {
          records:
            listScoreboardControlAudit({
              deviceId:
                query.deviceId,
              gameId:
                query.gameId,
              disposition:
                query.disposition,
              limit:
                Number.isFinite(limit)
                  ? limit
                  : undefined,
            }),
        },
      };
    },
  );
}
