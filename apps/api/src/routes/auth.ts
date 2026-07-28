import type { FastifyInstance } from "fastify";
import bcrypt from "bcryptjs";
import type { RowDataPacket } from "mysql2/promise";
import { z } from "zod";
import { pool } from "../infrastructure/database.js";
import { audit } from "../lib/audit.js";
import { authUser, requireAuth } from "../lib/auth.js";
import { normalizeRole } from "../modules/auth/index.js";

const loginSchema = z.object({
  identifier: z.string().trim().min(1),
  password: z.string().min(1),
});

export async function authRoutes(app: FastifyInstance): Promise<void> {
  app.post("/auth/login", async (request, reply) => {
    const parsed = loginSchema.safeParse(request.body);
    if (!parsed.success)
      return reply.code(400).send({ error: "Username/email and password are required" });

    const [rows] = await pool.execute<RowDataPacket[]>(
      `SELECT u.id, u.organization_id, u.first_name, u.last_name, u.email, u.username,
              u.password_hash, u.role, o.name AS organization_name
       FROM users u
       JOIN organizations o ON o.id = u.organization_id
       WHERE u.username = ? OR u.email = ? LIMIT 1`,
      [parsed.data.identifier, parsed.data.identifier.toLowerCase()],
    );
    const user = rows[0];
    if (!user || !(await bcrypt.compare(parsed.data.password, String(user.password_hash)))) {
      return reply.code(401).send({ error: "Invalid username/email or password" });
    }

    const role = normalizeRole(user.role);

    const token = app.jwt.sign(
    {
      sub: String(user.id),
      organizationId: Number(user.organization_id),
      role,
    },
  { expiresIn: "8h" },
);
    await audit(String(user.id), "auth.login", { username: user.username });
    return {
      token,
      user: {
        id: user.id,
        firstName: user.first_name,
        lastName: user.last_name,
        email: user.email,
        username: user.username,
        role,
        organizationName: user.organization_name,
      },
    };
  });

  app.get("/auth/me", { preHandler: requireAuth }, async (request, reply) => {
    const [rows] = await pool.execute<RowDataPacket[]>(
      `SELECT u.id, u.first_name, u.last_name, u.email, u.username, u.role,
              o.name AS organization_name
       FROM users u
       JOIN organizations o ON o.id = u.organization_id
       WHERE u.id = ? LIMIT 1`,
      [authUser(request).sub],
    );
    const user = rows[0];
    if (!user) return reply.code(404).send({ error: "User not found" });
    return {
      user: {
        id: user.id,
        firstName: user.first_name,
        lastName: user.last_name,
        email: user.email,
        username: user.username,
        role: user.role,
        organizationName: user.organization_name,
      },
    };
  });

  app.post("/auth/logout", { preHandler: requireAuth }, async () => ({ success: true }));
}
