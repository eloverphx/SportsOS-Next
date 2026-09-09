import { randomUUID } from "node:crypto";
import type { RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import { permissionsForRole } from "./permissions.js";
import { normalizeRole, type Role } from "./roles.js";
import { createRefreshToken, hashRefreshToken, REFRESH_SESSION_TTL_MS } from "./session-tokens.js";

export interface SessionUser {
  readonly id: number;
  readonly organizationId: number;
  readonly organizationName: string;
  readonly firstName: string;
  readonly lastName: string;
  readonly email: string;
  readonly username: string;
  readonly role: Role;
  readonly permissions: ReturnType<typeof permissionsForRole>;
}

export interface IssuedAuthSession {
  readonly sessionId: string;
  readonly refreshToken: string;
  readonly expiresAt: string;
}

export interface RotatedAuthSession extends IssuedAuthSession {
  readonly user: SessionUser;
}

function expirationDate(): Date {
  return new Date(Date.now() + REFRESH_SESSION_TTL_MS);
}

export async function createAuthSession(input: {
  userId: number;
  organizationId: number;
}): Promise<IssuedAuthSession> {
  const sessionId = randomUUID();
  const refreshToken = createRefreshToken();
  const refreshTokenHash = hashRefreshToken(refreshToken);
  const expiresAt = expirationDate();

  await pool.execute(
    `INSERT INTO auth_sessions (
       session_id,
       user_id,
       organization_id,
       refresh_token_hash,
       expires_at
     )
     VALUES (?, ?, ?, ?, ?)`,
    [sessionId, input.userId, input.organizationId, refreshTokenHash, expiresAt],
  );

  return {
    sessionId,
    refreshToken,
    expiresAt: expiresAt.toISOString(),
  };
}

export async function rotateAuthSession(refreshToken: string): Promise<RotatedAuthSession | null> {
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    const [rows] = await connection.execute<RowDataPacket[]>(
      `SELECT
         s.session_id,
         s.expires_at,
         s.revoked_at,
         u.id,
         u.organization_id,
         u.first_name,
         u.last_name,
         u.email,
         u.username,
         u.role,
         u.account_status,
         o.name AS organization_name
       FROM auth_sessions s
       JOIN users u ON u.id = s.user_id
       JOIN organizations o ON o.id = s.organization_id
       WHERE s.refresh_token_hash = ?
       LIMIT 1
       FOR UPDATE`,
      [hashRefreshToken(refreshToken)],
    );

    const row = rows[0];

    if (
      !row ||
      row.revoked_at != null ||
      String(row.account_status) !== "ACTIVE" ||
      new Date(String(row.expires_at)).getTime() <= Date.now()
    ) {
      await connection.rollback();
      return null;
    }

    const nextRefreshToken = createRefreshToken();
    const nextExpiresAt = expirationDate();

    await connection.execute(
      `UPDATE auth_sessions
       SET refresh_token_hash = ?,
           expires_at = ?,
           last_seen_at = CURRENT_TIMESTAMP(3)
       WHERE session_id = ?`,
      [hashRefreshToken(nextRefreshToken), nextExpiresAt, String(row.session_id)],
    );

    await connection.commit();

    const role = normalizeRole(row.role);

    return {
      sessionId: String(row.session_id),
      refreshToken: nextRefreshToken,
      expiresAt: nextExpiresAt.toISOString(),
      user: {
        id: Number(row.id),
        organizationId: Number(row.organization_id),
        organizationName: String(row.organization_name),
        firstName: String(row.first_name),
        lastName: String(row.last_name),
        email: String(row.email),
        username: String(row.username),
        role,
        permissions: permissionsForRole(role),
      },
    };
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}

export async function revokeAuthSession(sessionId: string, userId: number): Promise<void> {
  await pool.execute(
    `UPDATE auth_sessions
     SET revoked_at = COALESCE(revoked_at, CURRENT_TIMESTAMP(3))
     WHERE session_id = ?
       AND user_id = ?`,
    [sessionId, userId],
  );
}

export async function revokeRefreshToken(refreshToken: string): Promise<void> {
  await pool.execute(
    `UPDATE auth_sessions
     SET revoked_at = COALESCE(revoked_at, CURRENT_TIMESTAMP(3))
     WHERE refresh_token_hash = ?`,
    [hashRefreshToken(refreshToken)],
  );
}
