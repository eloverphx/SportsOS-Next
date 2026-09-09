import type { FastifyInstance } from "fastify";
import bcrypt from "bcryptjs";
import type { RowDataPacket } from "mysql2/promise";
import { z } from "zod";
import { pool } from "../infrastructure/database.js";
import { audit } from "../lib/audit.js";
import { authUser, requireAuth } from "../lib/auth.js";
import { normalizeRole, permissionsForRole, ROLES } from "../modules/auth/index.js";
import {
  createPendingSignup,
  organizationAcceptsSignup,
} from "../modules/auth/account-repository.js";
import {
  createAuthSession,
  revokeAuthSession,
  revokeRefreshToken,
  rotateAuthSession,
  type SessionUser,
} from "../modules/auth/session-repository.js";

const loginSchema = z.object({
  identifier: z.string().trim().min(1),
  password: z.string().min(1),
});

const signupSchema = z.object({
  organizationId: z.coerce.number().int().positive(),
  firstName: z.string().trim().min(1).max(80),
  lastName: z.string().trim().min(1).max(80),
  email: z
    .string()
    .trim()
    .email()
    .max(190)
    .transform((value) => value.toLowerCase()),
  username: z
    .string()
    .trim()
    .min(3)
    .max(80)
    .regex(
      /^[a-zA-Z0-9._-]+$/,
      "Username may only contain letters, numbers, periods, underscores, and hyphens",
    ),
  password: z.string().min(10).max(128),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(32),
});

const logoutSchema = z
  .object({
    refreshToken: z.string().min(32).optional(),
  })
  .optional();

function accessToken(
  app: FastifyInstance,
  user: {
    id: number;
    organizationId: number;
    role: ReturnType<typeof normalizeRole>;
  },
  sessionId: string,
): string {
  return app.jwt.sign(
    {
      sub: String(user.id),
      organizationId: user.organizationId,
      role: user.role,
      sessionId,
    },
    { expiresIn: "8h" },
  );
}

function userPayload(user: SessionUser) {
  return {
    id: user.id,
    organizationId: user.organizationId,
    organizationName: user.organizationName,
    firstName: user.firstName,
    lastName: user.lastName,
    email: user.email,
    username: user.username,
    role: user.role,
    permissions: user.permissions,
  };
}

export async function authRoutes(app: FastifyInstance): Promise<void> {
  app.post("/auth/signup", async (request, reply) => {
    const parsed = signupSchema.safeParse(request.body);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid signup data",
        details: parsed.error.flatten(),
      });
    }

    const input = parsed.data;

    if (!(await organizationAcceptsSignup(input.organizationId))) {
      return reply.code(404).send({
        error: "Organization is not available for signup",
      });
    }

    try {
      const passwordHash = await bcrypt.hash(input.password, 12);

      const userId = await createPendingSignup({
        organizationId: input.organizationId,
        firstName: input.firstName,
        lastName: input.lastName,
        email: input.email,
        username: input.username,
        passwordHash,
      });

      await audit(String(userId), "auth.signup.requested", {
        organizationId: input.organizationId,
      });

      return reply.code(201).send({
        success: true,
        status: "PENDING_APPROVAL",
        message:
          "Signup received. An organization administrator must approve the account before login.",
      });
    } catch (error) {
      const databaseError = error as {
        code?: string;
      };

      if (databaseError.code === "ER_DUP_ENTRY") {
        return reply.code(409).send({
          error: "A user with that email or username already exists",
        });
      }

      throw error;
    }
  });

  app.post("/auth/login", async (request, reply) => {
    const parsed = loginSchema.safeParse(request.body);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Username/email and password are required",
      });
    }

    const [rows] = await pool.execute<RowDataPacket[]>(
      `SELECT
         u.id,
         u.organization_id,
         u.first_name,
         u.last_name,
         u.email,
         u.username,
         u.password_hash,
         u.role,
         u.account_status,
         o.name AS organization_name
       FROM users u
       JOIN organizations o ON o.id = u.organization_id
       WHERE u.username = ?
          OR u.email = ?
       LIMIT 1`,
      [parsed.data.identifier, parsed.data.identifier.toLowerCase()],
    );

    const user = rows[0];

    if (!user || !(await bcrypt.compare(parsed.data.password, String(user.password_hash)))) {
      return reply.code(401).send({
        error: "Invalid username/email or password",
      });
    }

    const accountStatus = String(user.account_status);

    if (accountStatus !== "ACTIVE") {
      const error =
        accountStatus === "PENDING"
          ? "Account is pending administrator approval"
          : "Account is not active";

      return reply.code(403).send({ error });
    }

    const role = normalizeRole(user.role);

    const session = await createAuthSession({
      userId: Number(user.id),
      organizationId: Number(user.organization_id),
    });

    const token = accessToken(
      app,
      {
        id: Number(user.id),
        organizationId: Number(user.organization_id),
        role,
      },
      session.sessionId,
    );

    await audit(String(user.id), "auth.login", {
      username: user.username,
      sessionId: session.sessionId,
    });

    return {
      token,
      refreshToken: session.refreshToken,
      session: {
        id: session.sessionId,
        expiresAt: session.expiresAt,
      },
      user: {
        id: Number(user.id),
        organizationId: Number(user.organization_id),
        organizationName: String(user.organization_name),
        firstName: String(user.first_name),
        lastName: String(user.last_name),
        email: String(user.email),
        username: String(user.username),
        role,
        permissions: permissionsForRole(role),
      },
    };
  });

  app.post("/auth/refresh", async (request, reply) => {
    const parsed = refreshSchema.safeParse(request.body);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Refresh token is required",
      });
    }

    const session = await rotateAuthSession(parsed.data.refreshToken);

    if (!session) {
      return reply.code(401).send({
        error: "Refresh session is invalid or expired",
      });
    }

    const token = accessToken(app, session.user, session.sessionId);

    await audit(String(session.user.id), "auth.session.refreshed", {
      sessionId: session.sessionId,
    });

    return {
      token,
      refreshToken: session.refreshToken,
      session: {
        id: session.sessionId,
        expiresAt: session.expiresAt,
      },
      user: userPayload(session.user),
    };
  });

  app.get("/auth/me", { preHandler: requireAuth }, async (request, reply) => {
    const identity = authUser(request);

    const [rows] = await pool.execute<RowDataPacket[]>(
      `SELECT
             u.id,
             u.organization_id,
             u.first_name,
             u.last_name,
             u.email,
             u.username,
             u.role,
             o.name AS organization_name
           FROM users u
           JOIN organizations o
             ON o.id = u.organization_id
           WHERE u.id = ?
           LIMIT 1`,
      [identity.userId],
    );

    const user = rows[0];

    if (!user) {
      return reply.code(404).send({
        error: "User not found",
      });
    }

    return {
      user: {
        id: Number(user.id),
        organizationId: Number(user.organization_id),
        organizationName: user.organization_name,
        firstName: user.first_name,
        lastName: user.last_name,
        email: user.email,
        username: user.username,
        role: identity.role,
        permissions: identity.permissions,
      },
    };
  });

  app.post("/auth/logout", { preHandler: requireAuth }, async (request) => {
    const identity = authUser(request);
    const parsed = logoutSchema.safeParse(request.body);

    if (identity.sessionId) {
      await revokeAuthSession(identity.sessionId, identity.userId);
    }

    if (parsed.success && parsed.data?.refreshToken) {
      await revokeRefreshToken(parsed.data.refreshToken);
    }

    await audit(identity.sub, "auth.logout", {
      sessionId: identity.sessionId ?? null,
    });

    return { success: true };
  });
}
