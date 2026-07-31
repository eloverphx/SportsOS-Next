import type { FastifyInstance } from "fastify";
import { type RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import { realtime } from "../../infrastructure/realtime.js";
import { audit } from "../../lib/audit.js";
import { PERMISSIONS, requirePermission } from "../auth/index.js";
import {
  createRosterEntry,
  deleteRosterEntry,
  findRosterEntryById,
  jerseyConflict,
  listAvailablePlayers,
  listRoster,
  rosterEntryExists,
  updateRosterEntry,
  validateRosterRelationships,
} from "./repository.js";
import {
  availablePlayersQuerySchema,
  rosterIdSchema,
  rosterInputSchema,
  rosterListQuerySchema,
  rosterUpdateSchema,
} from "./schemas.js";

async function findRosterOrganizationId(
  seasonId: number,
  teamId: number,
): Promise<{ organizationId: number } | { error: "season" | "team" | "organization" }> {
  const [rows] = await pool.execute<RowDataPacket[]>(
    `SELECT
       s.organization_id AS season_organization_id,
       t.organization_id AS team_organization_id
     FROM seasons s
     JOIN teams t ON t.id = ?
     WHERE s.id = ?
     LIMIT 1`,
    [teamId, seasonId],
  );

  const row = rows[0];

  if (row) {
    const seasonOrganizationId = Number(row.season_organization_id);
    const teamOrganizationId = Number(row.team_organization_id);

    if (seasonOrganizationId !== teamOrganizationId) {
      return { error: "organization" };
    }

    return {
      organizationId: teamOrganizationId,
    };
  }

  const [seasonRows] = await pool.execute<RowDataPacket[]>(
    "SELECT id FROM seasons WHERE id = ? LIMIT 1",
    [seasonId],
  );

  if (!seasonRows[0]) {
    return { error: "season" };
  }

  const [teamRows] = await pool.execute<RowDataPacket[]>(
    "SELECT id FROM teams WHERE id = ? LIMIT 1",
    [teamId],
  );

  if (!teamRows[0]) {
    return { error: "team" };
  }

  return { error: "organization" };
}

function relationshipErrorMessage(error: "season" | "team" | "player" | "organization"): string {
  if (error === "organization") {
    return "Season, team, and player must belong to the same organization";
  }

  return `${error[0]?.toUpperCase()}${error.slice(1)} not found`;
}

export async function rosterRoutes(app: FastifyInstance): Promise<void> {
  app.get("/rosters", async (request, reply) => {
    const parsed = rosterListQuerySchema.safeParse(request.query);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid roster filters",
        details: parsed.error.flatten(),
      });
    }

    const context = await findRosterOrganizationId(parsed.data.seasonId, parsed.data.teamId);

    if ("error" in context) {
      return reply.code(400).send({
        error: relationshipErrorMessage(context.error),
      });
    }

    await requirePermission(request, {
      permission: PERMISSIONS.TEAM_READ,
      organizationId: context.organizationId,
    });

    const active = parsed.data.active === undefined ? undefined : parsed.data.active === "true";

    return {
      roster: await listRoster({
        seasonId: parsed.data.seasonId,
        teamId: parsed.data.teamId,
        active,
      }),
    };
  });

  app.get("/rosters/available", async (request, reply) => {
    const parsed = availablePlayersQuerySchema.safeParse(request.query);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid player filters",
        details: parsed.error.flatten(),
      });
    }

    const context = await findRosterOrganizationId(parsed.data.seasonId, parsed.data.teamId);

    if ("error" in context) {
      return reply.code(400).send({
        error: relationshipErrorMessage(context.error),
      });
    }

    if (context.organizationId !== parsed.data.organizationId) {
      return reply.code(400).send({
        error: "Organization, season, and team must match",
      });
    }

    await requirePermission(request, {
      permission: PERMISSIONS.TEAM_ROSTER_MANAGE,
      organizationId: context.organizationId,
    });

    return {
      players: await listAvailablePlayers(parsed.data),
    };
  });

  app.post("/rosters", async (request, reply) => {
    const parsed = rosterInputSchema.safeParse(request.body);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid roster data",
        details: parsed.error.flatten(),
      });
    }

    const relationshipError = await validateRosterRelationships(parsed.data);

    if (relationshipError) {
      return reply.code(400).send({
        error: relationshipErrorMessage(relationshipError),
      });
    }

    const context = await findRosterOrganizationId(parsed.data.seasonId, parsed.data.teamId);

    if ("error" in context) {
      return reply.code(400).send({
        error: relationshipErrorMessage(context.error),
      });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.TEAM_ROSTER_MANAGE,
      organizationId: context.organizationId,
    });

    if (await rosterEntryExists(parsed.data.seasonId, parsed.data.teamId, parsed.data.playerId)) {
      return reply.code(409).send({
        error: "Player is already on this roster",
      });
    }

    if (
      parsed.data.active &&
      (await jerseyConflict(parsed.data.seasonId, parsed.data.teamId, parsed.data.jerseyNumber))
    ) {
      return reply.code(409).send({
        error: "Jersey number is already assigned on this active roster",
      });
    }

    const entry = await createRosterEntry(parsed.data);

    await audit(identity.sub, "roster.created", {
      rosterId: entry.id,
      organizationId: context.organizationId,
      teamId: entry.teamId,
      seasonId: entry.seasonId,
      playerId: entry.playerId,
    });

    realtime().emit("roster:created", {
      id: entry.id,
      organizationId: context.organizationId,
      teamId: entry.teamId,
      seasonId: entry.seasonId,
    });

    return reply.code(201).send({
      entry,
    });
  });

  app.put("/rosters/:id", async (request, reply) => {
    const id = rosterIdSchema.safeParse((request.params as { id: string }).id);

    const parsed = rosterUpdateSchema.safeParse(request.body);

    if (!id.success || !parsed.success) {
      return reply.code(400).send({
        error: "Invalid roster data",
        details: parsed.success ? undefined : parsed.error.flatten(),
      });
    }

    const existing = await findRosterEntryById(id.data);

    if (!existing) {
      return reply.code(404).send({
        error: "Roster entry not found",
      });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.TEAM_ROSTER_MANAGE,
      organizationId: existing.organizationId,
    });

    if (
      parsed.data.active &&
      (await jerseyConflict(existing.seasonId, existing.teamId, parsed.data.jerseyNumber, id.data))
    ) {
      return reply.code(409).send({
        error: "Jersey number is already assigned on this active roster",
      });
    }

    const entry = await updateRosterEntry(id.data, parsed.data);

    if (!entry) {
      return reply.code(404).send({
        error: "Roster entry not found",
      });
    }

    await audit(identity.sub, "roster.updated", {
      rosterId: entry.id,
      organizationId: existing.organizationId,
      teamId: entry.teamId,
      seasonId: entry.seasonId,
    });

    realtime().emit("roster:updated", {
      id: entry.id,
      organizationId: existing.organizationId,
      teamId: entry.teamId,
      seasonId: entry.seasonId,
    });

    return {
      entry,
    };
  });

  app.delete("/rosters/:id", async (request, reply) => {
    const id = rosterIdSchema.safeParse((request.params as { id: string }).id);

    if (!id.success) {
      return reply.code(400).send({
        error: "Invalid roster id",
      });
    }

    const existing = await findRosterEntryById(id.data);

    if (!existing) {
      return reply.code(404).send({
        error: "Roster entry not found",
      });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.TEAM_ROSTER_MANAGE,
      organizationId: existing.organizationId,
    });

    if (!(await deleteRosterEntry(id.data))) {
      return reply.code(404).send({
        error: "Roster entry not found",
      });
    }

    await audit(identity.sub, "roster.deleted", {
      rosterId: id.data,
      organizationId: existing.organizationId,
      teamId: existing.teamId,
      seasonId: existing.seasonId,
      playerId: existing.playerId,
    });

    realtime().emit("roster:deleted", {
      id: id.data,
      organizationId: existing.organizationId,
      teamId: existing.teamId,
      seasonId: existing.seasonId,
    });

    return {
      success: true,
    };
  });
}
