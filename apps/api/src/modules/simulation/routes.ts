import type { FastifyInstance } from "fastify";
import { PERMISSIONS, requirePermission } from "../auth/index.js";
import {
  generateGameEventStream,
  generateTournamentPlan,
  normalizeTournamentSimulationConfig,
  summarizeTournamentSimulation,
} from "./tournament-simulator.js";
import {
  cleanupSimulationRun,
  executeProvisionedSimulationRun,
  getProvisionedSimulationRun,
  provisionSimulationRun,
} from "./provisioner.js";
import { qualifySimulationRun } from "./qualification.js";
import { ROLES } from "../auth/index.js";

export async function simulationRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.post("/simulation/tournaments/preview", async (request) => {
    await requirePermission(request, {
      permission: PERMISSIONS.GAME_READ,
    });

    const config = normalizeTournamentSimulationConfig(
      (request.body ?? {}) as Record<string, unknown>,
    );

    const plan = generateTournamentPlan(config);

    return {
      config,
      plan,
      summary: summarizeTournamentSimulation(plan, config),
    };
  });

  app.post("/simulation/games/:id/events", async (request, reply) => {
    await requirePermission(request, {
      permission: PERMISSIONS.GAME_READ,
    });

    const gameId = Number((request.params as { id: string }).id);
    if (!Number.isInteger(gameId) || gameId <= 0) {
      return reply.code(400).send({ error: "Invalid simulated game id" });
    }

    const config = normalizeTournamentSimulationConfig(
      (request.body ?? {}) as Record<string, unknown>,
    );
    const plan = generateTournamentPlan(config);
    const game = plan.games.find((candidate) => candidate.id === gameId);

    if (!game) {
      return reply.code(404).send({ error: "Simulated game not found" });
    }

    return {
      game,
      events: generateGameEventStream(game, config),
    };
  });

  app.post("/simulation/runs/provision", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
    });

    if (identity.role !== ROLES.SYSTEM_ADMIN) {
      return reply.code(403).send({
        error: "Tournament simulation provisioning requires system administrator access",
      });
    }

    const body = request.body as {
      runId?: string;
      organizationId?: number;
      seasonId?: number;
      config?: Record<string, unknown>;
    };

    if (
      typeof body.runId !== "string" ||
      !Number.isInteger(Number(body.organizationId)) ||
      !Number.isInteger(Number(body.seasonId))
    ) {
      return reply.code(400).send({ error: "Invalid simulation provisioning request" });
    }

    return provisionSimulationRun({
      runId: body.runId,
      organizationId: Number(body.organizationId),
      seasonId: Number(body.seasonId),
      actorUserId: identity.sub,
      config: body.config ?? {},
    });
  });

  app.get("/simulation/runs/:runId", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_READ,
    });

    if (identity.role !== ROLES.SYSTEM_ADMIN) {
      return reply.code(403).send({
        error: "Tournament simulation access requires system administrator access",
      });
    }

    const runId = (request.params as { runId: string }).runId;
    const run = await getProvisionedSimulationRun(runId);

    if (!run) return reply.code(404).send({ error: "Simulation run not found" });
    return run;
  });

  app.post("/simulation/runs/:runId/execute", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
    });

    if (identity.role !== ROLES.SYSTEM_ADMIN) {
      return reply.code(403).send({
        error: "Tournament simulation execution requires system administrator access",
      });
    }

    const runId = (request.params as { runId: string }).runId;
    const body = (request.body ?? {}) as { concurrency?: number };

    return executeProvisionedSimulationRun(
      runId,
      identity.sub,
      body.concurrency,
    );
  });

  app.delete("/simulation/runs/:runId", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
    });

    if (identity.role !== ROLES.SYSTEM_ADMIN) {
      return reply.code(403).send({
        error: "Tournament simulation cleanup requires system administrator access",
      });
    }

    const runId = (request.params as { runId: string }).runId;
    return cleanupSimulationRun(runId);
  });

  app.post("/simulation/qualification/run", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
    });

    if (identity.role !== ROLES.SYSTEM_ADMIN) {
      return reply.code(403).send({
        error: "Simulation qualification requires system administrator access",
      });
    }

    const body = request.body as {
      runId?: string;
      organizationId?: number;
      seasonId?: number;
      concurrency?: number;
      cleanupOnPass?: boolean;
      config?: Record<string, unknown>;
    };

    if (
      typeof body.runId !== "string" ||
      !Number.isInteger(Number(body.organizationId)) ||
      !Number.isInteger(Number(body.seasonId))
    ) {
      return reply.code(400).send({
        error: "Invalid simulation qualification request",
      });
    }

    return qualifySimulationRun({
      runId: body.runId,
      organizationId: Number(body.organizationId),
      seasonId: Number(body.seasonId),
      actorUserId: identity.sub,
      concurrency:
        body.concurrency === undefined
          ? undefined
          : Number(body.concurrency),
      cleanupOnPass: body.cleanupOnPass ?? false,
      config: body.config ?? {},
    });
  });
}
