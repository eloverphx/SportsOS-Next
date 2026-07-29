import type { FastifyInstance } from "fastify";
import mysql, { type RowDataPacket } from "mysql2/promise";
import { z } from "zod";
import { pool } from "../infrastructure/database.js";
import { realtime } from "../infrastructure/realtime.js";
import { audit } from "../lib/audit.js";
import { PERMISSIONS, ROLES,requirePermission } from "../modules/auth/index.js";
import { logoUrl } from "../lib/media.js";

const color = z.string().regex(/^#[0-9a-fA-F]{6}$/);
const organizationSchema = z.object({
  name: z.string().trim().min(2).max(160),
  shortName: z.string().trim().max(50).nullable().optional(),
  defaultSport: z.string().trim().min(2).max(80).default("Hockey"),
  timezone: z.string().trim().min(2).max(100),
  primaryColor: color.default("#ef4444"),
  secondaryColor: color.default("#0f172a"),
  website: z.union([z.string().trim().url().max(255), z.literal(""), z.null()]).optional(),
  logoAssetId: z.number().int().positive().nullable().optional(),
  active: z.boolean().default(true),
});

function mapOrganization(row: RowDataPacket) {
  return {
    id: Number(row.id),
    name: row.name,
    shortName: row.short_name,
    defaultSport: row.default_sport,
    timezone: row.timezone,
    primaryColor: row.primary_color,
    secondaryColor: row.secondary_color,
    website: row.website,
    logoAssetId: row.logo_asset_id ? Number(row.logo_asset_id) : null,
    logoUrl: logoUrl(row.logo_asset_id ? Number(row.logo_asset_id) : null),
    active: Boolean(row.active),
    teamCount: Number(row.team_count ?? 0),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export async function organizationRoutes(app: FastifyInstance): Promise<void> {
  app.get("/organizations/:id", async (request, reply) => {
  const id = z.coerce
    .number()
    .int()
    .positive()
    .safeParse((request.params as { id: string }).id);

  if (!id.success) {
    return reply.code(400).send({
      error: "Invalid organization id",
    });
  }

  await requirePermission(request, {
    permission: PERMISSIONS.ORGANIZATION_READ,
    organizationId: id.data,
  });

  const [rows] = await pool.execute<RowDataPacket[]>(
    `SELECT o.*, COUNT(t.id) AS team_count
     FROM organizations o
     LEFT JOIN teams t ON t.organization_id = o.id
     WHERE o.id = ?
     GROUP BY o.id`,
    [id.data],
  );

  if (!rows[0]) {
    return reply.code(404).send({
      error: "Organization not found",
    });
  }

  return {
    organization: mapOrganization(rows[0]),
  };
});

  app.get("/organizations", async (request) => {
  const identity = await requirePermission(request, {
    permission: PERMISSIONS.ORGANIZATION_READ,
  });

  const systemAdministrator = identity.role === ROLES.SYSTEM_ADMIN;

  const [rows] = systemAdministrator
    ? await pool.query<RowDataPacket[]>(
        `SELECT o.*, COUNT(t.id) AS team_count
         FROM organizations o
         LEFT JOIN teams t ON t.organization_id = o.id
         GROUP BY o.id
         ORDER BY o.name`,
      )
    : await pool.execute<RowDataPacket[]>(
        `SELECT o.*, COUNT(t.id) AS team_count
         FROM organizations o
         LEFT JOIN teams t ON t.organization_id = o.id
         WHERE o.id = ?
         GROUP BY o.id
         ORDER BY o.name`,
        [identity.organizationId],
      );

  return {
    organizations: rows.map(mapOrganization),
  };
});

  app.post("/organizations", async (request, reply) => {
  const identity = await requirePermission(request, {
    permission: PERMISSIONS.ORGANIZATION_CREATE,
  });
    const parsed = organizationSchema.safeParse(request.body);
    if (!parsed.success)
      return reply
        .code(400)
        .send({ error: "Invalid organization data", details: parsed.error.flatten() });
    const d = parsed.data;
    const [result] = await pool.execute<mysql.ResultSetHeader>(
      "INSERT INTO organizations (name, short_name, default_sport, timezone, primary_color, secondary_color, website, logo_asset_id, active) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
      [
        d.name,
        d.shortName || null,
        d.defaultSport,
        d.timezone,
        d.primaryColor,
        d.secondaryColor,
        d.website || null,
        d.logoAssetId || null,
        d.active,
      ],
    );
    await audit(identity.sub, "organization.created", {
      organizationId: result.insertId,
      name: d.name,
    });
    realtime().emit("organization:created", { id: result.insertId });
    return reply.code(201).send({ id: result.insertId });
  });

  app.put("/organizations/:id", async (request, reply) => {
  const id = z.coerce
    .number()
    .int()
    .positive()
    .safeParse((request.params as { id: string }).id);

  const parsed = organizationSchema.safeParse(request.body);

  if (!id.success || !parsed.success) {
    return reply.code(400).send({
      error: "Invalid organization data",
    });
  }

  const identity = await requirePermission(request, {
    permission: PERMISSIONS.ORGANIZATION_UPDATE,
    organizationId: id.data,
  });

  const d = parsed.data;

  const [result] = await pool.execute<mysql.ResultSetHeader>(
    `UPDATE organizations
     SET name=?,
         short_name=?,
         default_sport=?,
         timezone=?,
         primary_color=?,
         secondary_color=?,
         website=?,
         logo_asset_id=?,
         active=?
     WHERE id=?`,
    [
      d.name,
      d.shortName || null,
      d.defaultSport,
      d.timezone,
      d.primaryColor,
      d.secondaryColor,
      d.website || null,
      d.logoAssetId || null,
      d.active,
      id.data,
    ],
  );

  if (!result.affectedRows) {
    return reply.code(404).send({
      error: "Organization not found",
    });
  }

  await audit(identity.sub, "organization.updated", {
    organizationId: id.data,
  });

  realtime().emit("organization:updated", {
    id: id.data,
  });

  return {
    success: true,
  };
});

  app.delete("/organizations/:id", async (request, reply) => {
  const id = z.coerce
    .number()
    .int()
    .positive()
    .safeParse((request.params as { id: string }).id);

  if (!id.success) {
    return reply.code(400).send({
      error: "Invalid organization id",
    });
  }

  const identity = await requirePermission(request, {
    permission: PERMISSIONS.ORGANIZATION_DELETE,
    organizationId: id.data,
  });

  const [count] = await pool.execute<RowDataPacket[]>(
    "SELECT COUNT(*) AS count FROM teams WHERE organization_id=?",
    [id.data],
  );

  if (Number(count[0]?.count ?? 0) > 0) {
    return reply.code(409).send({
      error: "Delete or move this organization’s teams first",
    });
  }

  const [result] = await pool.execute<mysql.ResultSetHeader>(
    "DELETE FROM organizations WHERE id=?",
    [id.data],
  );

  if (!result.affectedRows) {
    return reply.code(404).send({
      error: "Organization not found",
    });
  }

  await audit(identity.sub, "organization.deleted", {
    organizationId: id.data,
  });

  realtime().emit("organization:deleted", {
    id: id.data,
  });

  return {
    success: true,
  };
});

  
}
