import type { FastifyInstance } from "fastify";
import { realtime } from "../../infrastructure/realtime.js";
import { audit } from "../../lib/audit.js";
import { PERMISSIONS, ROLES, requirePermission } from "../auth/index.js";
import { listActivePenalties } from "../penalties/repository.js";
import {
  applyGameScoringAction,
  deleteGame,
  findGameById,
  listGames,
  listGameTeamOptions,
  validateGameRelationships,
  GamePhaseError,
  IdempotencyConflictError,
} from "./repository.js";
import {
  gameIdSchema,
  gameInputSchema,
  gameListQuerySchema,
  scoreActionSchema,
} from "./schemas.js";
import {
  GameLifecycleError,
  gameLifecycleCommandSchema,
  resolveLifecycleAction,
} from "./lifecycle.js";
import { recordEngineTransition } from "./telemetry.js";
import {
  evaluateSchedulePreview,
  parseScheduleOverride,
} from "./schedule-enforcement.js";
import {
  createGameWithScheduleTransaction,
  updateGameWithScheduleTransaction,
} from "./schedule-mutations.js";
import { queryScheduleAuditEvents } from "./schedule-audit.js";
import { evaluatePregameReadinessGate } from "../../services/scoreboardPregameReadinessGate.js";
import { evaluateGameStartPreflight } from "../../services/gameStartPreflightGuard.js";
import { getActiveGameStartPreflightOverride } from "../../services/gameStartPreflightOverride.js";

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

  app.get("/games/schedule-audit/recent", async (request, reply) => {
  const identity = await requirePermission(request, {
    permission: PERMISSIONS.GAME_READ,
  });

  const query = request.query as {
    decision?: "ALL" | "BLOCKED" | "OVERRIDDEN";
    gameId?: string;
    venue?: string;
    actorUserId?: string;
    organizationId?: string;
    limit?: string;
    offset?: string;
  };

  const gameId = query.gameId ? Number(query.gameId) : null;
  const actorUserId = query.actorUserId ? Number(query.actorUserId) : null;
  const requestedOrganizationId = query.organizationId
    ? Number(query.organizationId)
    : null;
  const limit = query.limit ? Number(query.limit) : undefined;
  const offset = query.offset ? Number(query.offset) : undefined;

  if (
    identity.role !== ROLES.SYSTEM_ADMIN &&
    Number.isSafeInteger(requestedOrganizationId) &&
    (requestedOrganizationId as number) > 0 &&
    requestedOrganizationId !== identity.organizationId
  ) {
    return reply.code(403).send({
      error: "Cannot read schedule audit events for another organization",
      code: "AUDIT_ORGANIZATION_FORBIDDEN",
    });
  }

  return queryScheduleAuditEvents({
    organizationId:
      identity.role === ROLES.SYSTEM_ADMIN
        ? Number.isSafeInteger(requestedOrganizationId) &&
          (requestedOrganizationId as number) > 0
          ? (requestedOrganizationId as number)
          : null
        : identity.organizationId,
    decision: query.decision,
    gameId:
      Number.isSafeInteger(gameId) && (gameId as number) > 0
        ? (gameId as number)
        : null,
    venue: query.venue?.trim() || null,
    actorUserId:
      Number.isSafeInteger(actorUserId) && (actorUserId as number) > 0
        ? (actorUserId as number)
        : null,
    limit,
    offset,
  });
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
        gamePhase: game.gamePhase,
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
        intermissionRemainingMs: game.intermissionRemainingMs,
        intermissionRunning: game.intermissionRunning,
        intermissionStartedAt: game.intermissionStartedAt,
        intermissionReady: game.intermissionReady,
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

    const scheduleOverride = parseScheduleOverride(request.body);

    if (scheduleOverride.override && scheduleOverride.reasonTooLong) {
      return reply.code(400).send({
        error: "Schedule override reason must be 500 characters or fewer",
        code: "SCHEDULE_OVERRIDE_REASON_TOO_LONG",
      });
    }

    if (scheduleOverride.override) {
      await requirePermission(request, {
        permission: PERMISSIONS.GAME_SCHEDULE_OVERRIDE,
        organizationId: parsed.data.organizationId,
      });
    }

    const mutation = await createGameWithScheduleTransaction(
      parsed.data,
      scheduleOverride.override,
    );
    const scheduleEvaluation = mutation.evaluation;

    if (mutation.outcome === "blocked") {
      await audit(identity.sub, "game.schedule_create_conflict_blocked", {
        organizationId: parsed.data.organizationId,
        requestedScheduledStart: parsed.data.scheduledStart,
        requestedVenue: parsed.data.venue,
        conflicts: scheduleEvaluation.conflicts,
      });

      return reply.code(409).send({
        error: "Game creation creates a hard tournament conflict",
        code: "SCHEDULE_CONFLICT",
        conflicts: scheduleEvaluation.conflicts,
      });
    }

    const game = mutation.game;

    await audit(identity.sub, "game.created", {
      gameId: game.id,
      organizationId: game.organizationId,
      seasonId: game.seasonId,
      homeTeamId: game.homeTeamId,
      homeExternalName: game.homeExternalName,
      awayTeamId: game.awayTeamId,
      awayExternalName: game.awayExternalName,
      scheduleConflicts: scheduleEvaluation.conflicts,
      scheduleConflictOverride: scheduleOverride.override,
      scheduleConflictOverrideReason: scheduleOverride.reason,
    });

    if (scheduleEvaluation.hardConflict && scheduleOverride.override) {
      await audit(identity.sub, "game.schedule_create_conflict_overridden", {
        gameId: game.id,
        organizationId: game.organizationId,
        scheduledStart: game.scheduledStart,
        venue: game.venue,
        reason: scheduleOverride.reason,
        conflicts: scheduleEvaluation.conflicts,
      });
    }

    realtime().emit("games:changed", {
      reason: "created",
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

    const scheduleOverride = parseScheduleOverride(request.body);

    if (scheduleOverride.override && scheduleOverride.reasonTooLong) {
      return reply.code(400).send({
        error: "Schedule override reason must be 500 characters or fewer",
        code: "SCHEDULE_OVERRIDE_REASON_TOO_LONG",
      });
    }

    if (scheduleOverride.override) {
      await requirePermission(request, {
        permission: PERMISSIONS.GAME_SCHEDULE_OVERRIDE,
        organizationId: parsed.data.organizationId,
      });
    }

    const mutation = await updateGameWithScheduleTransaction(
      existing,
      parsed.data,
      scheduleOverride.override,
    );
    const scheduleChanged = mutation.scheduleChanged;
    const scheduleEvaluation = mutation.evaluation;

    if (mutation.outcome === "blocked") {
      await audit(identity.sub, "game.schedule_conflict_blocked", {
        gameId: existing.id,
        organizationId: parsed.data.organizationId,
        requestedScheduledStart: parsed.data.scheduledStart,
        requestedVenue: parsed.data.venue,
        conflicts: scheduleEvaluation.conflicts,
      });

      return reply.code(409).send({
        error: "Schedule change creates a hard tournament conflict",
        code: "SCHEDULE_CONFLICT",
        conflicts: scheduleEvaluation.conflicts,
      });
    }

    const game = mutation.game;

    await audit(identity.sub, "game.updated", {
      gameId: game.id,
      previousOrganizationId: existing.organizationId,
      organizationId: game.organizationId,
      scheduleChanged,
      scheduleConflictOverride: scheduleOverride.override,
      scheduleConflictOverrideReason: scheduleOverride.reason,
      scheduleConflicts: scheduleEvaluation.conflicts,
      previousScheduledStart: existing.scheduledStart,
      scheduledStart: game.scheduledStart,
      previousVenue: existing.venue,
      venue: game.venue,
    });

    if (
      scheduleChanged &&
      scheduleOverride.override &&
      scheduleEvaluation.hardConflict
    ) {
      await audit(identity.sub, "game.schedule_conflict_overridden", {
        gameId: game.id,
        organizationId: game.organizationId,
        reason: scheduleOverride.reason,
        scheduledStart: game.scheduledStart,
        venue: game.venue,
        conflicts: scheduleEvaluation.conflicts,
      });
    }

    realtime().to(`game:${game.id}`).emit("game:updated", {
      id: game.id,
      organizationId: game.organizationId,
    });
    realtime().emit("games:changed", {
      reason: "updated",
      id: game.id,
      organizationId: game.organizationId,
    });

    return { game };
  });

  app.post("/games/:id/schedule-preview", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);
    if (!id.success) {
      return reply.code(400).send({ error: "Invalid game id" });
    }

    const body =
      request.body && typeof request.body === "object"
        ? (request.body as Record<string, unknown>)
        : {};

    if (
      typeof body.scheduledStart !== "string" ||
      !Number.isFinite(new Date(body.scheduledStart).getTime()) ||
      !(
        body.venue === null ||
        body.venue === undefined ||
        (typeof body.venue === "string" && body.venue.trim().length <= 160)
      )
    ) {
      return reply.code(400).send({
        error: "Invalid schedule preview",
      });
    }

    const game = await findGameById(id.data);
    if (!game) {
      return reply.code(404).send({ error: "Game not found" });
    }

    await requirePermission(request, {
      permission: PERMISSIONS.GAME_MANAGE,
      organizationId: game.organizationId,
    });

    if (game.status !== "SCHEDULED") {
      return reply.code(409).send({
        error: "Only scheduled games can be previewed for schedule changes",
        code: "GAME_NOT_SCHEDULED",
      });
    }

    const scheduledStart = new Date(body.scheduledStart).toISOString();
    const venue =
      typeof body.venue === "string" ? body.venue.trim() || null : null;

    const evaluation = await evaluateSchedulePreview(game, {
      scheduledStart,
      venue,
    });

    return {
      gameId: game.id,
      scheduledStart,
      venue,
      hardConflict: evaluation.hardConflict,
      conflicts: evaluation.conflicts,
    };
  });

  app.post("/games/:id/scoring", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);
    const parsed = scoreActionSchema.safeParse(request.body);
    const rawBody =
      request.body && typeof request.body === "object"
        ? (request.body as Record<string, unknown>)
        : {};
    const actionId = typeof rawBody.actionId === "string" ? rawBody.actionId : undefined;
    const validActionId = actionId === undefined || /^[A-Za-z0-9._:-]{8,80}$/.test(actionId);

    if (!id.success || !parsed.success || !validActionId) {
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

    let result;

    try {
      result = await applyGameScoringAction(id.data, parsed.data, actionId);
    } catch (error) {
      if (error instanceof IdempotencyConflictError) {
        return reply.code(409).send({ error: error.message });
      }

      if (error instanceof GamePhaseError) {
        return reply.code(400).send({ error: error.message });
      }

      throw error;
    }

    if (!result) {
      // A replay is detected while the game row is locked. Reload the
      // authoritative committed state without applying or emitting again.
      if (actionId) {
        const game = await findGameById(id.data);
        if (!game) return reply.code(404).send({ error: "Game not found" });
        return { game, action: parsed.data.action, replayed: true };
      }

      return reply.code(404).send({ error: "Game not found" });
    }

    const { game } = result;

    await audit(identity.sub, "game.scored", {
      gameId: game.id,
      organizationId: game.organizationId,
      action: parsed.data.action,
      actionId,
      homeScore: game.homeScore,
      awayScore: game.awayScore,
      period: game.period,
      clockRemainingMs: game.clockRemainingMs,
      clockRunning: game.clockRunning,
      status: game.status,
    });

    return { game, action: parsed.data.action, replayed: false };
  });

  app.post("/games/:id/lifecycle", async (request, reply) => {
    const id = gameIdSchema.safeParse((request.params as { id: string }).id);
    const parsed = gameLifecycleCommandSchema.safeParse(request.body);

    if (!id.success || !parsed.success) {
      return reply.code(400).send({
        error: "Invalid lifecycle command",
        details: parsed.success ? undefined : parsed.error.flatten(),
      });
    }

    const existing = await findGameById(id.data);
    if (!existing) return reply.code(404).send({ error: "Game not found" });

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.GAME_SCORE,
      organizationId: existing.organizationId,
    });

    let action;
    try {
      action = resolveLifecycleAction(existing, parsed.data.command);
    } catch (error) {
      if (error instanceof GameLifecycleError) {
        return reply.code(400).send({ error: error.message });
      }
      throw error;
    }

    let result;
    try {
      result = await applyGameScoringAction(
        id.data,
        action,
        parsed.data.commandId,
      );
    } catch (error) {
      if (error instanceof IdempotencyConflictError) {
        return reply.code(409).send({ error: error.message });
      }
      if (error instanceof GamePhaseError) {
        return reply.code(400).send({ error: error.message });
      }
      throw error;
    }

    if (!result) {
      if (parsed.data.commandId) {
        const game = await findGameById(id.data);

    // PREGAME_SCOREBOARD_READINESS_GATE_16_9
    // Enforce only the explicit startGame lifecycle command. Other
    // startClock operations (period resume, recovery, etc.) remain unchanged.
    if (parsed.data.command === "startGame") {

      // GAME_START_PREFLIGHT_ENFORCEMENT_18_4
      const gameStartPreflight =
        evaluateGameStartPreflight(
          String(id.data),
        );

      if (
        !gameStartPreflight.allowed
      ) {
        // GAME_START_PREFLIGHT_OVERRIDE_18_6
        const activeEmergencyOverride =
          getActiveGameStartPreflightOverride(
            String(id.data),
            gameStartPreflight.deviceId ??
              "",
          );

        if (
          !activeEmergencyOverride
        ) {

        return reply.code(409).send({
          success: false,
          error: {
            code:
              gameStartPreflight.code,
            message:
              gameStartPreflight.message,
          },
          data: {
            preflight:
              gameStartPreflight,
          },
        });
        }
      }

      const assignmentsResponse = await app.inject({
        method: "GET",
        url: "/scoreboard-devices/assignments",
      });

      let assignedDeviceId: string | null = null;

      if (
        assignmentsResponse.statusCode >= 200 &&
        assignmentsResponse.statusCode < 300
      ) {
        try {
          const assignmentBody = assignmentsResponse.json() as {
            data?: {
              assignments?: Array<{
                gameId: string;
                deviceId: string;
              }>;
            };
            assignments?: Array<{
              gameId: string;
              deviceId: string;
            }>;
          };

          const assignments =
            assignmentBody.data?.assignments ??
            assignmentBody.assignments ??
            [];

          assignedDeviceId =
            assignments.find(
              (item) =>
                String(item.gameId) === String(id.data),
            )?.deviceId ?? null;
        } catch {
          assignedDeviceId = null;
        }
      }

      const readinessGate =
        evaluatePregameReadinessGate({
          gameId: String(id.data),
          deviceId: assignedDeviceId,
        });

      if (!readinessGate.allowed) {
        return reply.code(409).send({
          error:
            readinessGate.reason ??
            "Pregame scoreboard readiness gate blocked game start.",
          code: "PREGAME_SCOREBOARD_READINESS_BLOCKED",
          readinessGate,
        });
      }
    }

        if (!game) return reply.code(404).send({ error: "Game not found" });

        recordEngineTransition({
          source: "operator",
          gameId: game.id,
          action: parsed.data.command,
          outcome: "replayed",
          actorUserId: Number(identity.sub),
          actorRole: identity.role,
        });

        return {
          game,
          command: parsed.data.command,
          replayed: true,
        };
      }

      return reply.code(404).send({ error: "Game not found" });
    }

    const { game } = result;

    await audit(identity.sub, "game.lifecycle", {
      gameId: game.id,
      organizationId: game.organizationId,
      command: parsed.data.command,
      commandId: parsed.data.commandId,
      gamePhase: game.gamePhase,
      period: game.period,
      status: game.status,
      clockRemainingMs: game.clockRemainingMs,
    });

    recordEngineTransition({
      source: "operator",
      gameId: game.id,
      action: parsed.data.command,
      outcome: "applied",
      actorUserId: Number(identity.sub),
      actorRole: identity.role,
    });

    return {
      game,
      command: parsed.data.command,
      replayed: false,
    };
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

    realtime()
      .to(`game:${game.id}`)
      .emit("scoreboard:sound", {
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

    realtime().to(`game:${id.data}`).emit("game:deleted", {
      id: id.data,
      organizationId: game.organizationId,
    });
    realtime().emit("games:changed", {
      reason: "deleted",
      id: id.data,
      organizationId: game.organizationId,
    });

    return { success: true };
  });
}
