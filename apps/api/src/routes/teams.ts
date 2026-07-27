import type { FastifyInstance } from "fastify";
import mysql, { type RowDataPacket } from "mysql2/promise";
import { z } from "zod";
import { pool } from "../infrastructure/database.js";
import { realtime } from "../infrastructure/realtime.js";
import { audit } from "../lib/audit.js";
import { authUser, requireAuth } from "../lib/auth.js";
import { logoUrl } from "../lib/media.js";

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

export async function teamRoutes(app: FastifyInstance): Promise<void> {
  app.get("/teams", { preHandler: requireAuth }, async (request) => {
    const query = request.query as { organizationId?: string; search?: string };
    const conditions: string[] = [];
    const params: Array<string | number> = [];
    if (query.organizationId) {
      conditions.push("t.organization_id=?");
      params.push(Number(query.organizationId));
    }
    if (query.search) {
      conditions.push("(t.name LIKE ? OR t.nickname LIKE ? OR t.division LIKE ?)");
      const s = `%${query.search}%`;
      params.push(s, s, s);
    }
    const where = conditions.length ? `WHERE ${conditions.join(" AND ")}` : "";
    const [rows] = await pool.execute<RowDataPacket[]>(
      `SELECT t.*, o.name AS organization_name FROM teams t JOIN organizations o ON o.id=t.organization_id ${where} ORDER BY t.name`,
      params,
    );
    return { teams: rows.map(mapTeam) };
  });

  app.get("/teams/:id", { preHandler: requireAuth }, async (request, reply) => {
    const id = z.coerce
      .number()
      .int()
      .positive()
      .safeParse((request.params as { id: string }).id);
    if (!id.success) return reply.code(400).send({ error: "Invalid team id" });
    const [rows] = await pool.execute<RowDataPacket[]>(
      "SELECT t.*, o.name AS organization_name FROM teams t JOIN organizations o ON o.id=t.organization_id WHERE t.id=?",
      [id.data],
    );
    if (!rows[0]) return reply.code(404).send({ error: "Team not found" });
    return { team: mapTeam(rows[0]) };
  });

  app.post("/teams", { preHandler: requireAuth }, async (request, reply) => {
    const parsed = teamSchema.safeParse(request.body);
    if (!parsed.success)
      return reply.code(400).send({ error: "Invalid team data", details: parsed.error.flatten() });
    const d = parsed.data;
    const [result] = await pool.execute<mysql.ResultSetHeader>(
      "INSERT INTO teams (organization_id, name, nickname, sport, division, season, home_arena, primary_color, secondary_color, logo_asset_id, active) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      [
        d.organizationId,
        d.name,
        d.nickname || null,
        d.sport,
        d.division || null,
        d.season || null,
        d.homeArena || null,
        d.primaryColor,
        d.secondaryColor,
        d.logoAssetId || null,
        d.active,
      ],
    );
    await audit(authUser(request).sub, "team.created", { teamId: result.insertId, name: d.name });
    realtime().emit("team:created", { id: result.insertId });
    return reply.code(201).send({ id: result.insertId });
  });

  app.put("/teams/:id", { preHandler: requireAuth }, async (request, reply) => {
    const id = z.coerce
      .number()
      .int()
      .positive()
      .safeParse((request.params as { id: string }).id);
    const parsed = teamSchema.safeParse(request.body);
    if (!id.success || !parsed.success) return reply.code(400).send({ error: "Invalid team data" });
    const d = parsed.data;
    const [result] = await pool.execute<mysql.ResultSetHeader>(
      "UPDATE teams SET organization_id=?, name=?, nickname=?, sport=?, division=?, season=?, home_arena=?, primary_color=?, secondary_color=?, logo_asset_id=?, active=? WHERE id=?",
      [
        d.organizationId,
        d.name,
        d.nickname || null,
        d.sport,
        d.division || null,
        d.season || null,
        d.homeArena || null,
        d.primaryColor,
        d.secondaryColor,
        d.logoAssetId || null,
        d.active,
        id.data,
      ],
    );
    if (!result.affectedRows) return reply.code(404).send({ error: "Team not found" });
    await audit(authUser(request).sub, "team.updated", { teamId: id.data });
    realtime().emit("team:updated", { id: id.data });
    return { success: true };
  });

  app.delete("/teams/:id", { preHandler: requireAuth }, async (request, reply) => {
    const id = z.coerce
      .number()
      .int()
      .positive()
      .safeParse((request.params as { id: string }).id);
    if (!id.success) return reply.code(400).send({ error: "Invalid team id" });
    const [result] = await pool.execute<mysql.ResultSetHeader>("DELETE FROM teams WHERE id=?", [
      id.data,
    ]);
    if (!result.affectedRows) return reply.code(404).send({ error: "Team not found" });
    await audit(authUser(request).sub, "team.deleted", { teamId: id.data });
    realtime().emit("team:deleted", { id: id.data });
    return { success: true };
  });
}
