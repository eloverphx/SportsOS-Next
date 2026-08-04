import type { FastifyInstance } from "fastify";
import { realtime } from "../../infrastructure/realtime.js";
import { audit } from "../../lib/audit.js";
import { PERMISSIONS, ROLES, requirePermission } from "../auth/index.js";
import { listActivePenalties } from "../penalties/repository.js";
import {
  applyGameScoringAction,
  createGame,
  deleteGame,
  findGameById,
  listGames,
  listGameTeamOptions,
  updateGame,
  validateGameRelationships,
} from "./repository.js";
import {
  gameIdSchema,
  gameInputSchema,
  gameListQuerySchema,
  scoreActionSchema,
} from "./schemas.js";

function relationshipErrorMessage(
  error: "organization" | "season" | "homeTeam" | "awayTeam",
): string {
  switch (error) {
    case "organization":
      return "Managing organization not found";
    case "season":
      return "Season does not belong to the managing organization";
    case "homeTeam":
      return "Registered home team was not found";
    case "awayTeam":
      return "Registered away team was not found";
  }
}

export async function gameRoutes(app: FastifyInstance): Promise<void> {
  app.get("/games/team-options", async (request) => {
    await requirePermission(request, {
      permission: PERMISSIONS.GAME_READ,
    });

    return { teams: await listGameTeamOptions() };
  });

  app.get("/games", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_READ,
    });

    const parsed = gameListQuerySchema.safeParse(request.query);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid game filters",
        details: parsed.error.flatten(),
      });
    }

    return {
      games: await listGames(
        identity.role === ROLES.SYSTEM_ADMIN
          ? parsed.data
          : { ...parsed.data, organizationId: identity.organizationId },
      ),
    };
  });

  app.get("/games/:id", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);
    if (!id.success) return reply.code(400).send({ error: "Invalid game id" });

    const game = await findGameById(id.data);
    if (!game) return reply.code(404).send({ error: "Game not found" });

    await requirePermission(request, {
      permission: PERMISSIONS.GAME_READ,
      organizationId: game.organizationId,
    });

    return { game };
  });

  app.get("/public/games/:id/scoreboard", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);
    if (!id.success) return reply.code(400).send({ error: "Invalid game id" });

    const game = await findGameById(id.data);
    if (!game) return reply.code(404).send({ error: "Game not found" });

    const penalties = await listActivePenalties(game.id);

    return {
      game: {
        id: game.id,
        organizationName: game.organizationName,
        organizationLogoUrl: game.organizationLogoUrl,
        organizationPrimaryColor: game.organizationPrimaryColor,
        organizationSecondaryColor: game.organizationSecondaryColor,
        seasonName: game.seasonName,
        homeTeamName: game.homeTeamName,
        homeTeamLogoUrl: game.homeTeamLogoUrl,
        homeTeamPrimaryColor: game.homeTeamPrimaryColor,
        homeTeamSecondaryColor: game.homeTeamSecondaryColor,
        awayTeamName: game.awayTeamName,
        awayTeamLogoUrl: game.awayTeamLogoUrl,
        awayTeamPrimaryColor: game.awayTeamPrimaryColor,
        awayTeamSecondaryColor: game.awayTeamSecondaryColor,
        scheduledStart: game.scheduledStart,
        timezone: game.timezone,
        venue: game.venue,
        status: game.status,
        homeScore: game.homeScore,
        awayScore: game.awayScore,
        period: game.period,
        periodLengthMs: game.periodLengthMs,
        clockRemainingMs: game.clockRemainingMs,
        clockRunning: game.clockRunning,
        clockStartedAt: game.clockStartedAt,
        regulationPeriods: game.regulationPeriods,
        regulationPeriodLengthMs: game.regulationPeriodLengthMs,
        intermissionLengthMs: game.intermissionLengthMs,
        overtimeEnabled: game.overtimeEnabled,
        overtimeLengthMs: game.overtimeLengthMs,
        periodLabel: game.periodLabel,
        canAdvancePeriod: game.canAdvancePeriod,
        penalties,
      },
    };
  });

  app.post("/games", async (request, reply) => {
    const parsed = gameInputSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid game data",
        details: parsed.error.flatten(),
      });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
      organizationId: parsed.data.organizationId,
    });

    const relationshipError = await validateGameRelationships(parsed.data);
    if (relationshipError) {
      return reply.code(400).send({
        error: relationshipErrorMessage(relationshipError),
      });
    }

    const game = await createGame(parsed.data);

    await audit(identity.sub, "game.created", {
      gameId: game.id,
      organizationId: game.organizationId,
      seasonId: game.seasonId,
      homeTeamId: game.homeTeamId,
      homeExternalName: game.homeExternalName,
      awayTeamId: game.awayTeamId,
      awayExternalName: game.awayExternalName,
    });

    realtime().emit("game:created", {
      id: game.id,
      organizationId: game.organizationId,
    });

    return reply.code(201).send({ game });
  });

  app.put("/games/:id", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);
    const parsed = gameInputSchema.safeParse(request.body);

    if (!id.success || !parsed.success) {
      return reply.code(400).send({
        error: "Invalid game data",
        details: parsed.success ? undefined : parsed.error.flatten(),
      });
    }

    const existing = await findGameById(id.data);
    if (!existing) return reply.code(404).send({ error: "Game not found" });

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
      organizationId: existing.organizationId,
    });

    if (
      identity.role !== ROLES.SYSTEM_ADMIN &&
      parsed.data.organizationId !== existing.organizationId
    ) {
      return reply.code(403).send({
        error: "You do not have permission to move this game to another organization",
      });
    }

    await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
      organizationId: parsed.data.organizationId,
    });

    const relationshipError = await validateGameRelationships(parsed.data);
    if (relationshipError) {
      return reply.code(400).send({
        error: relationshipErrorMessage(relationshipError),
      });
    }

    const game = await updateGame(id.data, parsed.data);
    if (!game) return reply.code(404).send({ error: "Game not found" });

    await audit(identity.sub, "game.updated", {
      gameId: game.id,
      previousOrganizationId: existing.organizationId,
      organizationId: game.organizationId,
    });

    realtime().emit("game:updated", {
      id: game.id,
      organizationId: game.organizationId,
    });

    return { game };
  });

  app.post("/games/:id/scoring", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);
    const parsed = scoreActionSchema.safeParse(request.body);

    if (!id.success || !parsed.success) {
      return reply.code(400).send({
        error: "Invalid scoring action",
        details: parsed.success ? undefined : parsed.error.flatten(),
      });
    }

    const existing = await findGameById(id.data);
    if (!existing) return reply.code(404).send({ error: "Game not found" });

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_SCORE,
      organizationId: existing.organizationId,
    });

    const game = await applyGameScoringAction(id.data, parsed.data);
    if (!game) return reply.code(404).send({ error: "Game not found" });

    await audit(identity.sub, "game.scored", {
      gameId: game.id,
      organizationId: game.organizationId,
      action: parsed.data.action,
      homeScore: game.homeScore,
      awayScore: game.awayScore,
      period: game.period,
      clockRemainingMs: game.clockRemainingMs,
      clockRunning: game.clockRunning,
      status: game.status,
    });

    const payload = { game, action: parsed.data.action };
    realtime().emit("game:scored", payload);
    realtime().emit("game:updated", {
      id: game.id,
      organizationId: game.organizationId,
    });

    return payload;
  });

  app.post("/games/:id/broadcast", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);
    const body = request.body as { type?: string };

    if (!id.success || body.type !== "HORN") {
      return reply.code(400).send({ error: "Invalid broadcast action" });
    }

    const game = await findGameById(id.data);
    if (!game) return reply.code(404).send({ error: "Game not found" });

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_SCORE,
      organizationId: game.organizationId,
    });

    await audit(identity.sub, "scoreboard.horn.triggered", {
      gameId: game.id,
      organizationId: game.organizationId,
    });

    realtime().emit("scoreboard:sound", {
      gameId: game.id,
      soundId: `manual-horn-${game.id}-${Date.now()}`,
      type: "HORN",
    });

    return { success: true };
  });
  app.delete("/games/:id", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);
    if (!id.success) return reply.code(400).send({ error: "Invalid game id" });

    const game = await findGameById(id.data);
    if (!game) return reply.code(404).send({ error: "Game not found" });

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
      organizationId: game.organizationId,
    });

    if (!(await deleteGame(id.data))) {
      return reply.code(404).send({ error: "Game not found" });
    }

    await audit(identity.sub, "game.deleted", {
      gameId: id.data,
      organizationId: game.organizationId,
    });

    realtime().emit("game:deleted", {
      id: id.data,
      organizationId: game.organizationId,
    });

    return { success: true };
  });
}
