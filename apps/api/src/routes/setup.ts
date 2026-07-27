import type { FastifyInstance } from "fastify";
import bcrypt from "bcryptjs";
import mysql, { type RowDataPacket } from "mysql2/promise";
import { z } from "zod";
import { pool } from "../infrastructure/database.js";

const setupSchema = z.object({
  firstName: z.string().trim().min(1).max(80),
  lastName: z.string().trim().min(1).max(80),
  email: z.string().trim().email().max(190),
  username: z.string().trim().min(3).max(80),
  password: z.string().min(10).max(128),
  organizationName: z.string().trim().min(2).max(160),
  defaultSport: z.string().trim().min(2).max(80).default("Hockey"),
  timezone: z.string().trim().min(2).max(100),
  serverName: z.string().trim().min(2).max(120),
});

export async function setupRoutes(app: FastifyInstance): Promise<void> {
  app.get("/setup/status", async () => {
    const [rows] = await pool.query<RowDataPacket[]>("SELECT COUNT(*) AS count FROM users");
    return { complete: Number(rows[0]?.count ?? 0) > 0 };
  });

  app.post("/setup/complete", async (request, reply) => {
    const parsed = setupSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "Invalid setup data", details: parsed.error.flatten() });
    }

    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();
      const [rows] = await connection.query<RowDataPacket[]>(
        "SELECT COUNT(*) AS count FROM users FOR UPDATE",
      );
      if (Number(rows[0]?.count ?? 0) > 0) {
        await connection.rollback();
        return reply.code(409).send({ error: "Setup has already been completed" });
      }

      const input = parsed.data;
      const [orgResult] = await connection.execute<mysql.ResultSetHeader>(
        "INSERT INTO organizations (name, default_sport, timezone) VALUES (?, ?, ?)",
        [input.organizationName, input.defaultSport, input.timezone],
      );
      const passwordHash = await bcrypt.hash(input.password, 12);
      const [userResult] = await connection.execute<mysql.ResultSetHeader>(
        "INSERT INTO users (organization_id, first_name, last_name, email, username, password_hash, role) VALUES (?, ?, ?, ?, ?, ?, ?)",
        [
          orgResult.insertId,
          input.firstName,
          input.lastName,
          input.email.toLowerCase(),
          input.username,
          passwordHash,
          "admin",
        ],
      );
      await connection.execute(
        "INSERT INTO settings (setting_key, setting_value) VALUES (?, ?), (?, ?)",
        ["server_name", input.serverName, "setup_complete", "true"],
      );
      await connection.execute(
        "INSERT INTO audit_log (user_id, action, details) VALUES (?, ?, ?)",
        [
          userResult.insertId,
          "setup.completed",
          JSON.stringify({ organizationId: orgResult.insertId }),
        ],
      );
      await connection.commit();
      return { success: true };
    } catch (error) {
      await connection.rollback();
      request.log.error(error);
      return reply.code(500).send({ error: "Setup failed" });
    } finally {
      connection.release();
    }
  });
}
