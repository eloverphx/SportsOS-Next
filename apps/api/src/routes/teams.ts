import type { FastifyInstance } from "fastify";
import mysql, { type RowDataPacket } from "mysql2/promise";
import { z } from "zod";
import { pool } from "../infrastructure/database.js";
import { realtime } from "../infrastructure/realtime.js";
import { audit } from "../lib/audit.js";
import { logoUrl } from "../lib/media.js";
import { PERMISSIONS, ROLES, requirePermission } from "../modules/auth/index.js";

const color = z.string().regex(/^#[0-9a-fA-F]{6}$/);

const teamSchema = z.object({
  organizationId: z.number().int().positive(),
  name: z.string().trim().min(2).max(160),
  nickname: z.string().trim().max(100).nullable().optional(),
  sport: z.string().trim().min(2).max(80).default("Hockey"),
  division: z.string().trim().max(100).nullable().optional(),
  season: z.string().trim().max(40).nullable().optional(),
  homeArena: z.string().trim().max(160).nullable().optional(),
  primaryColor: color.default("#ef4444"),
  secondaryColor: color.default("#0f172a"),
  logoAssetId: z.number().int().positive().nullable().optional(),
  active: z.boolean().default(true),
});

function mapTeam(row: RowDataPacket) {
  return {
    id: Number(row.id),
    organizationId: Number(row.organization_id),
    organizationName: row.organization_name,
    name: row.name,
    nickname: row.nickname,
    sport: row.sport,
    division: row.division,
    season: row.season,
    homeArena: row.home_arena,
    primaryColor: row.primary_color,
    secondaryColor: row.secondary_color,
    logoAssetId: row.logo_asset_id ? Number(row.logo_asset_id) : null,
    logoUrl: logoUrl(row.logo_asset_id ? Number(row.logo_asset_id) : null),
    active: Boolean(row.active),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function findTeamOrganizationId(teamId: number): Promise<number | null> {
  const [rows] = await pool.execute<RowDataPacket[]>(
    "SELECT organization_id FROM teams WHERE id=? LIMIT 1",
    [teamId],
  );

  return rows[0] ? Number(rows[0].organization_id) : null;
}

export async function teamRoutes(app: FastifyInstance): Promise<void> {
  app.get("/teams", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.TEAM_READ,
    });

    const query = request.query as {
      organizationId?: string;
      search?: string;
    };

    const conditions: string[] = [];
    const params: Array<string | number> = [];

    if (identity.role === ROLES.SYSTEM_ADMIN) {
      if (query.organizationId) {
        const organizationId = z.coerce.number().int().positive().safeParse(query.organizationId);

        if (!organizationId.success) {
          return reply.code(400).send({
            error: "Invalid organization id",
          });
        }

        conditions.push("t.organization_id=?");
        params.push(organizationId.data);
      }
    } else {
      conditions.push("t.organization_id=?");
      params.push(identity.organizationId);
    }

    if (query.search?.trim()) {
      conditions.push("(t.name LIKE ? OR t.nickname LIKE ? OR t.division LIKE ?)");

      const search = `%${query.search.trim()}%`;
      params.push(search, search, search);
    }

    const where = conditions.length ? `WHERE ${conditions.join(" AND ")}` : "";

    const [rows] = await pool.execute<RowDataPacket[]>(
      `SELECT t.*, o.name AS organization_name
       FROM teams t
       JOIN organizations o ON o.id=t.organization_id
       ${where}
       ORDER BY t.name`,
      params,
    );

    return {
      teams: rows.map(mapTeam),
    };
  });

  app.get("/teams/:id", async (request, reply) => {
    const id = z.coerce
      .number()
      .int()
      .positive()
      .safeParse((request.params as { id: string }).id);

    if (!id.success) {
      return reply.code(400).send({
        error: "Invalid team id",
      });
    }

    const [rows] = await pool.execute<RowDataPacket[]>(
      `SELECT t.*, o.name AS organization_name
       FROM teams t
       JOIN organizations o ON o.id=t.organization_id
       WHERE t.id=?
       LIMIT 1`,
      [id.data],
    );

    const team = rows[0];

    if (!team) {
      return reply.code(404).send({
        error: "Team not found",
      });
    }

    await requirePermission(request, {
      permission: PERMISSIONS.TEAM_READ,
      organizationId: Number(team.organization_id),
    });

    return {
      team: mapTeam(team),
    };
  });

  app.post("/teams", async (request, reply) => {
    const parsed = teamSchema.safeParse(request.body);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid team data",
        details: parsed.error.flatten(),
      });
    }

    const data = parsed.data;

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.TEAM_CREATE,
      organizationId: data.organizationId,
    });

    const [result] = await pool.execute<mysql.ResultSetHeader>(
      `INSERT INTO teams (
           organization_id,
           name,
           nickname,
           sport,
           division,
           season,
           home_arena,
           primary_color,
           secondary_color,
           logo_asset_id,
           active
         )
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        data.organizationId,
        data.name,
        data.nickname || null,
        data.sport,
        data.division || null,
        data.season || null,
        data.homeArena || null,
        data.primaryColor,
        data.secondaryColor,
        data.logoAssetId || null,
        data.active,
      ],
    );

    await audit(identity.sub, "team.created", {
      teamId: result.insertId,
      organizationId: data.organizationId,
      name: data.name,
    });

    realtime().emit("team:created", {
      id: result.insertId,
      organizationId: data.organizationId,
    });

    return reply.code(201).send({
      id: result.insertId,
    });
  });

  app.put("/teams/:id", async (request, reply) => {
    const id = z.coerce
      .number()
      .int()
      .positive()
      .safeParse((request.params as { id: string }).id);

    const parsed = teamSchema.safeParse(request.body);

    if (!id.success || !parsed.success) {
      return reply.code(400).send({
        error: "Invalid team data",
      });
    }

    const existingOrganizationId = await findTeamOrganizationId(id.data);

    if (existingOrganizationId === null) {
      return reply.code(404).send({
        error: "Team not found",
      });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.TEAM_UPDATE,
      organizationId: existingOrganizationId,
    });

    const data = parsed.data;

    if (identity.role !== ROLES.SYSTEM_ADMIN && data.organizationId !== existingOrganizationId) {
      return reply.code(403).send({
        error: "You do not have permission to move this team to another organization",
      });
    }

    await requirePermission(request, {
      permission: PERMISSIONS.TEAM_UPDATE,
      organizationId: data.organizationId,
    });

    const [result] = await pool.execute<mysql.ResultSetHeader>(
      `UPDATE teams
         SET organization_id=?,
             name=?,
             nickname=?,
             sport=?,
             division=?,
             season=?,
             home_arena=?,
             primary_color=?,
             secondary_color=?,
             logo_asset_id=?,
             active=?
         WHERE id=?`,
      [
        data.organizationId,
        data.name,
        data.nickname || null,
        data.sport,
        data.division || null,
        data.season || null,
        data.homeArena || null,
        data.primaryColor,
        data.secondaryColor,
        data.logoAssetId || null,
        data.active,
        id.data,
      ],
    );

    if (!result.affectedRows) {
      return reply.code(404).send({
        error: "Team not found",
      });
    }

    await audit(identity.sub, "team.updated", {
      teamId: id.data,
      previousOrganizationId: existingOrganizationId,
      organizationId: data.organizationId,
    });

    realtime().emit("team:updated", {
      id: id.data,
      organizationId: data.organizationId,
    });

    return {
      success: true,
    };
  });

  app.delete("/teams/:id", async (request, reply) => {
    const id = z.coerce
      .number()
      .int()
      .positive()
      .safeParse((request.params as { id: string }).id);

    if (!id.success) {
      return reply.code(400).send({
        error: "Invalid team id",
      });
    }

    const organizationId = await findTeamOrganizationId(id.data);

    if (organizationId === null) {
      return reply.code(404).send({
        error: "Team not found",
      });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.TEAM_DELETE,
      organizationId,
    });

    const [result] = await pool.execute<mysql.ResultSetHeader>("DELETE FROM teams WHERE id=?", [
      id.data,
    ]);

    if (!result.affectedRows) {
      return reply.code(404).send({
        error: "Team not found",
      });
    }

    await audit(identity.sub, "team.deleted", {
      teamId: id.data,
      organizationId,
    });

    realtime().emit("team:deleted", {
      id: id.data,
      organizationId,
    });

    return {
      success: true,
    };
  });
}
