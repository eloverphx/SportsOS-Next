import { z } from "zod";
import { ROLES } from "../auth/index.js";

export const organizationIdParamsSchema = z.object({
  organizationId: z.coerce.number().int().positive(),
});

export const organizationMemberParamsSchema = z.object({
  organizationId: z.coerce.number().int().positive(),
  userId: z.coerce.number().int().positive(),
});

export const createOrganizationMemberSchema = z.object({
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

  role: z.enum([
    ROLES.SYSTEM_ADMIN,
    ROLES.ORGANIZATION_OWNER,
    ROLES.ORGANIZATION_ADMIN,
    ROLES.TEAM_ADMIN,
    ROLES.COACH,
    ROLES.SCOREKEEPER,
    ROLES.BROADCASTER,
    ROLES.VIEWER,
  ]),
});

export const updateOrganizationMemberRoleSchema = z.object({
  role: z.enum([
    ROLES.SYSTEM_ADMIN,
    ROLES.ORGANIZATION_OWNER,
    ROLES.ORGANIZATION_ADMIN,
    ROLES.TEAM_ADMIN,
    ROLES.COACH,
    ROLES.SCOREKEEPER,
    ROLES.BROADCASTER,
    ROLES.VIEWER,
  ]),
});
